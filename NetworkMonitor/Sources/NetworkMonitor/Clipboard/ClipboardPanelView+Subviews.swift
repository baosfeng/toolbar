import AppKit
import NetworkMonitorCore

// MARK: - 面板视图子视图构建（从 ClipboardPanelView 拆出，守住单文件 15 KiB 上限）
//
// 只做「建视图 + 接线回调」，布局与状态更新仍在主文件；底部件数计数文本与右键菜单
// 响应链分发也在此文件，避免主文件继续膨胀。跨文件访问的成员已在主文件放宽为 internal。

extension ClipboardPanelView {

    // MARK: 两级材质与发丝分隔线（视图定义见 ClipboardPanelChrome.swift）

    /// 面板内衬：两级材料的里层，挂成首个（最底层）子视图
    /// 层次因此是「外层 .hudWindow → 内衬 → 发丝分隔线 → 控件与卡片 → 浮层」，内容仍铺满可用区
    func buildInnerMaterial() {
        let inset = ClipboardPanelInnerMaterialView.inset
        innerMaterial.frame = bounds.insetBy(dx: inset, dy: inset)
        addSubview(innerMaterial)
    }

    /// 发丝分隔线层：内衬作为子视图会盖住父视图自绘的线条，故单独成层；
    /// 位置紧跟内衬（在所有控件与卡片之下），与改动前父视图自绘的层次保持一致
    func buildSeparatorLayer() {
        separatorView.frame = bounds
        addSubview(separatorView)
    }

    func buildSearchField() {
        searchField.placeholderString = "搜索剪贴板"
        searchField.delegate = self
        searchField.font = NSFont.systemFont(ofSize: 13)
        // 置空 nextKeyView：Tab 不进入搜索框焦点环（Tab 由面板统一拦截为切换过滤）
        searchField.nextKeyView = nil
        addSubview(searchField)
    }

    func buildFilterControl() {
        filterControl.segmentCount = ClipboardFilter.allCases.count
        filterControl.segmentStyle = .texturedRounded
        filterControl.trackingMode = .selectOne
        filterControl.font = NSFont.systemFont(ofSize: 12)
        for filter in ClipboardFilter.allCases {
            filterControl.setLabel(filter.label, forSegment: filter.rawValue)
            filterControl.setWidth(40, forSegment: filter.rawValue)
            filterControl.setToolTip(filter.label, forSegment: filter.rawValue)
        }
        filterControl.selectedSegment = ClipboardFilter.all.rawValue
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        addSubview(filterControl)
    }

    func buildCaptureButton() {
        captureButton.title = "采集当前剪贴板"
        captureButton.bezelStyle = .rounded
        captureButton.controlSize = .small
        captureButton.font = NSFont.systemFont(ofSize: 12)
        captureButton.target = self
        captureButton.action = #selector(captureNow)
        addSubview(captureButton)
    }

    func buildFooter() {
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byClipping
        countLabel.stringValue = ClipboardPanelFooterText.countsLabel(total: 0, pinned: 0)
        countLabel.setAccessibilityLabel(ClipboardPanelFooterText.countsAccessibilityLabel(total: 0, pinned: 0))
        addSubview(countLabel)

        stackLabel.font = NSFont.systemFont(ofSize: 11)
        stackLabel.textColor = .secondaryLabelColor
        stackLabel.lineBreakMode = .byTruncatingTail
        stackLabel.isHidden = true
        addSubview(stackLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.alignment = .right
        hintLabel.stringValue = Self.keyHint
        addSubview(hintLabel)

        accessibilityButton.isBordered = false
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        applyPermissionStyle(accessibilityGranted: true)
        addSubview(accessibilityButton)
    }

    /// 工具条「?」按钮：键盘快捷键自身没有自述入口，靠它弹出键位浮层
    func buildHelpButton() {
        helpButton.isBordered = false
        helpButton.controlSize = .small
        // 不参与焦点环：点「?」后搜索框仍是第一响应者，弹出浮层不打断输入
        helpButton.refusesFirstResponder = true
        // 图标单独按 13pt 配置：10pt 符号在 24pt 按钮里点击目标过小
        helpButton.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor])))
        helpButton.imagePosition = .imageOnly
        helpButton.toolTip = "快捷键帮助"
        helpButton.setAccessibilityLabel("快捷键帮助")
        helpButton.target = self
        helpButton.action = #selector(toggleShortcutHelp)
        addSubview(helpButton)
    }

    /// 首次引导态与快捷键帮助浮层：都挂在面板最上层，帮助浮层压在引导态之上
    func buildOverlays() {
        guideView.onDismiss = { [weak self] in
            guard let self else { return }
            self.delegate?.panelViewDidDismissGuide(self)
        }
        // 引导态由控制器按「未引导过 + 历史为空」显式打开，视图自己不猜
        guideView.isHidden = true
        // 可读名与角色由 ClipboardGuideView.build 自己给（一句完整说明），此处不再覆盖
        addSubview(guideView)

        helpOverlay.onDismiss = { [weak self] in self?.hideShortcutHelp() }
        helpOverlay.isHidden = true
        addSubview(helpOverlay)
    }

    /// 引导态与「无匹配结果」空态互斥：引导态出现时空态不再显示同一句「没有匹配…」
    ///
    /// 判定条件由控制器给出（未引导过 + 历史为空），视图只负责呈现，不关心偏好从哪来。
    func updateGuideState(visible: Bool, toggleHotKey: String) {
        guideView.updateToggleHotKey(toggleHotKey)
        guideView.isHidden = !visible
        // 引导态独占卡片区：历史为空，卡片流里只有空态文案，隐藏后不与引导文案叠字
        cardFlow.isHidden = visible
        needsLayout = true
    }

    /// 权限入口样式：有权限时 10pt muted，无权限时改为 systemOrange 并带警示符号（不得静默）
    func applyPermissionStyle(accessibilityGranted: Bool) {
        let color: NSColor = accessibilityGranted ? .secondaryLabelColor : .systemOrange
        accessibilityButton.attributedTitle = NSAttributedString(
            string: "辅助功能权限",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: color])
        accessibilityButton.image = accessibilityGranted
            ? nil
            : symbolImage(named: "exclamationmark.triangle", color: .systemOrange)
        accessibilityButton.imagePosition = accessibilityGranted ? .noImage : .imageLeading
    }

    /// 卡片流：点击 / 双击动作全部转交控制器，视图不持有业务依赖
    func buildCardFlow() {
        cardFlow.onSelect = { [weak self] index in
            guard let self else { return }
            self.delegate?.panelView(self, didSelect: index)
        }
        cardFlow.onActivate = { [weak self] index in
            guard let self else { return }
            self.delegate?.panelView(self, didActivate: index)
        }
        cardFlow.onPin = { [weak self] index in
            guard let self else { return }
            self.delegate?.panelView(self, didRequestPinAt: index)
        }
        // 选中切换的触觉在视图层直接打：方向键连按时这条路径最敏感，
        // 不必绕回控制器再打一次（控制器只负责业务，反馈依赖已注入本视图）
        cardFlow.onSelectionChanged = { [weak self] in
            self?.feedback.haptics.tap(.selection)
        }
        addSubview(cardFlow)
    }

    func symbolImage(named name: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return image.withSymbolConfiguration(configuration) ?? image
    }

    // MARK: 底部件数统计

    /// 更新底部件数统计「N 条 · 收藏 M」（N = 当前匹配项数，M = 其中收藏数）
    ///
    /// 计数常驻提示行左侧、栈进度标签更左；读屏文案另给完整句子。
    func updateCounts(total: Int, pinned: Int) {
        countLabel.isHidden = false
        countLabel.stringValue = ClipboardPanelFooterText.countsLabel(total: total, pinned: pinned)
        countLabel.setAccessibilityLabel(ClipboardPanelFooterText.countsAccessibilityLabel(total: total, pinned: pinned))
        needsLayout = true
    }

    /// 右键菜单指令分发（菜单项 target 置空，沿响应链落到内容视图）
    ///
    /// 只做「取下标 → 转交控制器」，复制 / 粘贴 / 收藏 / 删除全部复用控制器既有动作，
    /// 不在此处实现第二套粘贴逻辑。
    @objc func handleCardMenuCommand(_ sender: NSMenuItem) {
        guard let command = ClipboardCardMenuCommand(rawValue: sender.tag),
              let itemID = sender.representedObject as? UUID else { return }
        delegate?.panelView(self, didRequestMenuCommand: command, itemID: itemID)
    }
}

// MARK: - 页脚文案

/// 底部件数统计文案 — 纯字符串规则，语义与读屏口径各一份
enum ClipboardPanelFooterText {
    /// 可见文案「N 条 · 收藏 M」
    static func countsLabel(total: Int, pinned: Int) -> String {
        "\(total) 条 · 收藏 \(pinned)"
    }

    /// 读屏文案「共 N 条，其中收藏 M 条」
    static func countsAccessibilityLabel(total: Int, pinned: Int) -> String {
        "共 \(total) 条，其中收藏 \(pinned) 条"
    }
}

// MARK: - 快捷键帮助浮层显隐

/// 帮助浮层的开合放在扩展里：面板视图只负责绘制与布局，显隐口径集中一处
extension ClipboardPanelView {

    /// 帮助浮层是否可见
    var isShortcutHelpVisible: Bool { !helpOverlay.isHidden }

    /// 弹出帮助浮层：不 makeFirstResponder，搜索框焦点不丢（面板本就是非激活面板）
    func showShortcutHelp() {
        helpOverlay.isHidden = false
        // 浮层与父视图都要重排：浮层铺满内容区、卡片按当前尺寸居中
        helpOverlay.needsLayout = true
        needsLayout = true
    }

    /// 收起帮助浮层；返回是否真的收起过（供控制器判断 Esc 是否已被消费）
    @discardableResult
    func hideShortcutHelp() -> Bool {
        guard !helpOverlay.isHidden else { return false }
        helpOverlay.isHidden = true
        return true
    }
}
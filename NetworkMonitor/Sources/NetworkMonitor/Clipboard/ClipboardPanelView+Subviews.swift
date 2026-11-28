import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板视图子视图构建（从 ClipboardPanelView 拆出，守住单文件 15 KiB 上限）
//
// 只做「建视图 + 接线回调」，布局与状态更新仍在主文件；条数计数文本与右键菜单
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

    /// 筛选芯片行：点掉一枚芯片 = 删它；点「＋筛选」= 弹候选清单（见 ClipboardFilterMenu）
    ///
    /// 芯片行铺在工具条整宽上（frame 由 layout 给），只在芯片与「＋筛选」按钮处吃鼠标，
    /// 其余位置放行 —— 它是铺满整行的，若不放行就会挡住搜索框与板胶囊的点击。
    func buildChipRow() {
        chipRowView.onRemove = { [weak self] identifier in
            guard let self else { return }
            self.setFilterTokens(self.filterTokens.filter { $0.id != identifier })
        }
        chipRowView.onRequestMenu = { [weak self] anchor in
            self?.showFilterMenu(anchor: anchor)
        }
        addSubview(chipRowView)
    }

    /// 弹「＋筛选」候选清单（锚点用按钮矩形，菜单贴着按钮出）
    func showFilterMenu(anchor: NSRect) {
        let menu = ClipboardFilterMenu.make(tokens: filterTokens,
                                            sources: ClipboardSourceCatalog.topSources(items: filterSourceItems),
                                            target: self, action: #selector(toggleFilterToken(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY + 2), in: self)
    }

    /// 菜单项动作：已选则删、未选则加（同类可叠加，见 ClipboardFilterMatcher）
    @objc func toggleFilterToken(_ sender: NSMenuItem) {
        if let token = ClipboardFilterMenu.token(from: sender) {
            let next = filterTokens.contains(token)
                ? filterTokens.filter { $0.id != token.id }
                : filterTokens + [token]
            setFilterTokens(next)
            return
        }
        // 没有芯片可取 = 「清除全部筛选」那一项
        guard (sender.representedObject as? String) == ClipboardFilterMenu.clearAllID else { return }
        setFilterTokens([])
    }

    /// 「采集当前剪贴板」：工具条右端两枚图标之一（图标 + tooltip，文案仍进读屏）
    func buildCaptureButton() {
        captureButton.isBordered = false
        captureButton.controlSize = .small
        captureButton.refusesFirstResponder = true
        captureButton.image = symbolImage(named: "square.and.arrow.down",
                                          color: .secondaryLabelColor, pointSize: 13)
        captureButton.imagePosition = .imageOnly
        captureButton.toolTip = "采集当前剪贴板"
        captureButton.setAccessibilityLabel("采集当前剪贴板")
        captureButton.target = self
        captureButton.action = #selector(captureNow)
        addSubview(captureButton)
    }

    /// 工具条「?」按钮：键盘快捷键自身没有自述入口，靠它弹出键位浮层
    func buildHelpButton() {
        helpButton.isBordered = false
        helpButton.controlSize = .small
        // 不参与焦点环：点「?」后搜索框仍是第一响应者，弹出浮层不打断输入
        helpButton.refusesFirstResponder = true
        // 图标单独按 13pt 配置：10pt 符号在 24pt 按钮里点击目标过小
        helpButton.image = symbolImage(named: "questionmark.circle",
                                       color: .secondaryLabelColor, pointSize: 13)
        helpButton.imagePosition = .imageOnly
        helpButton.toolTip = "快捷键帮助"
        helpButton.setAccessibilityLabel("快捷键帮助")
        helpButton.target = self
        helpButton.action = #selector(toggleShortcutHelp)
        addSubview(helpButton)
    }

    /// 条数计数（「N 条 · 收藏 M」）：工具条右端的一行状态文本，不是按钮
    func buildCountLabel() {
        countLabel.font = NSFont.systemFont(ofSize: 10.5)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        countLabel.lineBreakMode = .byTruncatingMiddle
        countLabel.stringValue = ClipboardPanelFooterText.countsLabel(total: 0, pinned: 0)
        countLabel.setAccessibilityLabel(ClipboardPanelFooterText.countsAccessibilityLabel(total: 0, pinned: 0))
        addSubview(countLabel)
    }

    /// 底部状态胶囊：暂停 / 权限 / 提示 / 多选 / 栈进度的唯一出口（不占布局高度）
    func buildStatusBand() {
        statusBand.onRequestRestore = { [weak self] in self?.resumeFromPauseBanner() }
        statusBand.onOpenAccessibility = { [weak self] in self?.openAccessibilitySettings() }
        addSubview(statusBand)
    }

    /// 编辑浮层：内容由编辑器在 ⌘E / ⌘N 期间灌入，平时整体隐藏
    func buildDetailStrip() {
        detailStrip.setAccessibilityIdentifier("clipboard.detailStrip")
        detailStrip.isHidden = true
        addSubview(detailStrip)
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

    /// 卡片流：点击 / 双击动作全部转交控制器，视图不持有业务依赖
    func buildCardFlow() {
        cardFlow.onSelect = { [weak self] index, click in
            guard let self else { return }
            self.delegate?.panelView(self, didSelect: index, click: click)
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

    func symbolImage(named name: String, color: NSColor,
                     pointSize: CGFloat = 10) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return image.withSymbolConfiguration(configuration) ?? image
    }

    // MARK: 底部件数统计

    /// 更新条数统计「N 条 · 收藏 M」（N = 当前匹配项数，M = 其中收藏数）
    ///
    /// 计数落在工具条右端、栈进度落在状态胶囊；读屏文案另给完整句子。
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

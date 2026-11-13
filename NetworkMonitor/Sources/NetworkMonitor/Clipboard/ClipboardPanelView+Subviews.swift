import AppKit
import NetworkMonitorCore

// MARK: - 面板视图子视图构建（从 ClipboardPanelView 拆出，守住单文件 15 KiB 上限）
//
// 只做「建视图 + 接线回调」，布局与状态更新仍在主文件；底部件数计数文本与右键菜单
// 响应链分发也在此文件，避免主文件继续膨胀。跨文件访问的成员已在主文件放宽为 internal。

extension ClipboardPanelView {

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
              let card = sender.representedObject as? ClipboardCardView,
              let index = cardFlow.indexOf(card) else { return }
        delegate?.panelView(self, didRequestMenuCommand: command, at: index)
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
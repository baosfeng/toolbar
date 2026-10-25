import AppKit

// MARK: - 剪贴板设置页（忽略应用）

/// 忽略应用列表 — 从主文件拆出：主文件（快捷键 / 面板 / 采集 / 权限）已接近单文件
/// 15 KiB 上限，而「展开 / 重建 / 增删」是一组内聚操作，独立成扩展文件更清晰。
///
/// 跨文件访问：`ignoredCard` / `ignoredListStack` / `ignoredExpanded` /
/// `ignoredToggleButton` / `ignoredInput` / `preferences` / `settingsDelegate`
/// 由 private 放宽为 internal，仅供本扩展使用。
extension SettingsClipboardPane {

    /// 忽略列表卡片 — 展开显示、收起整体隐藏（避免卡片内残留分隔线）
    func buildIgnoredCard() {
        ignoredListStack.orientation = .vertical
        ignoredListStack.alignment = .leading
        ignoredListStack.spacing = 4
        ignoredListStack.translatesAutoresizingMaskIntoConstraints = false

        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(ignoredListStack)
        NSLayoutConstraint.activate([
            ignoredListStack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor,
                                                      constant: SettingsStyle.rowInset),
            ignoredListStack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor,
                                                       constant: -SettingsStyle.rowInset),
            ignoredListStack.topAnchor.constraint(equalTo: listContainer.topAnchor, constant: 8),
            ignoredListStack.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: -8),
            listContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsStyle.rowHeight),
        ])

        let addRow = SettingsRowView(title: "添加忽略应用")
        addRow.trailingStack.addArrangedSubview(ignoredInput)
        addRow.trailingStack.addArrangedSubview(
            SettingsLinkButton.make("添加", target: self, action: #selector(addIgnoredApp)))

        ignoredCard.addRow(listContainer)
        ignoredCard.addRow(addRow)
        ignoredCard.isHidden = true
    }

    /// 重建列表（增删后与每次 refresh 都调用）
    func reloadIgnoredApps() {
        ignoredListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let bundleIDs = preferences.ignoredBundleIDs.sorted()
        if bundleIDs.isEmpty {
            ignoredListStack.addArrangedSubview(
                MenuPanelLabel.text("（无）", font: SettingsStyle.rowSubtitleFont,
                                    color: .tertiaryLabelColor))
        } else {
            bundleIDs.forEach { ignoredListStack.addArrangedSubview(makeIgnoredAppRow(bundleID: $0)) }
        }
        updateIgnoredToggleTitle(count: bundleIDs.count)
        ignoredCard.isHidden = !ignoredExpanded
    }

    private func makeIgnoredAppRow(bundleID: String) -> NSView {
        let label = MenuPanelLabel.text(bundleID,
                                        font: .monospacedSystemFont(ofSize: 11.5, weight: .regular),
                                        color: .labelColor)
        let removeButton = SettingsLinkButton.make("移除", target: self,
                                                    action: #selector(removeIgnoredApp(_:)))
        removeButton.identifier = NSUserInterfaceItemIdentifier(bundleID)
        let row = NSStackView(views: [label, MenuPanelLabel.spacer(), removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 24),
            row.widthAnchor.constraint(equalTo: ignoredListStack.widthAnchor),
        ])
        return row
    }

    /// 行尾「N 个 ›」按钮标题（展开态换成 ⌄）
    func updateIgnoredToggleTitle(count: Int) {
        SettingsLinkButton.setTitle("\(count) 个 \(ignoredExpanded ? "⌄" : "›")",
                                    on: ignoredToggleButton)
    }

    @objc func toggleIgnoredList() {
        ignoredExpanded.toggle()
        ignoredCard.isHidden = !ignoredExpanded
        updateIgnoredToggleTitle(count: preferences.ignoredBundleIDs.count)
    }

    @objc func addIgnoredApp() {
        let bundleID = ignoredInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }
        var ignored = preferences.ignoredBundleIDs
        ignored.insert(bundleID)
        preferences.ignoredBundleIDs = ignored
        ignoredInput.stringValue = ""
        reloadIgnoredApps()
        settingsDelegate?.settingsDidChangeIgnoredApps()
    }

    @objc func removeIgnoredApp(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        var ignored = preferences.ignoredBundleIDs
        ignored.remove(bundleID)
        preferences.ignoredBundleIDs = ignored
        reloadIgnoredApps()
        settingsDelegate?.settingsDidChangeIgnoredApps()
    }
}

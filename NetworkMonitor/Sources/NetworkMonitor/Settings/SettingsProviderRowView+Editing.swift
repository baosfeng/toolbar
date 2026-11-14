import AppKit
import NetworkMonitorCore

// MARK: - provider 行（编辑 / 清除确认 / 控件工厂）

// 拆出原因：单文件 500 行 / 15 KiB 上限；编辑区与确认区只依赖主类的 stored properties，
// 成员由 `private` 放宽为 internal 是跨文件扩展的必然结果（仅本目录使用）。
extension ProviderRowView {

    func buildEditor() {
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorView.wantsLayer = true
        editorView.isHidden = true

        let keyLabel = MenuPanelLabel.text("Key", font: SettingsTheme.rowSubtitleFont,
                                           color: SettingsTheme.textSecondary)
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)

        field.placeholderString = provider.credentialHint
        // 输入框用统一的等宽行值档：凭据是「一串字符」，等宽比比例字好看也更易核对
        field.font = SettingsTheme.rowValueFont
        field.controlSize = .small
        field.bezelStyle = .roundedBezel
        SettingsControlChrome.applyStandardHeight(to: field)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.target = self
        field.action = #selector(saveTapped)
        field.setAccessibilityLabel("\(provider.displayName) \(provider.credentialHint)")

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        let row = NSStackView(views: [keyLabel, field, saveButton, cancelButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        editorMessage.isHidden = true
        editorMessage.maximumNumberOfLines = 2
        editorNote.maximumNumberOfLines = 2
        editorNote.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [row, editorMessage, editorNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        editorView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: editorView.leadingAnchor,
                                           constant: SettingsStyle.rowInset),
            stack.trailingAnchor.constraint(equalTo: editorView.trailingAnchor,
                                            constant: -SettingsStyle.rowInset),
            stack.topAnchor.constraint(equalTo: editorView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: editorView.bottomAnchor, constant: -10),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        editorView.setAccessibilityLabel("\(provider.displayName) 凭据输入")
        updateChromeColors()
    }

    func buildConfirm() {
        confirmView.translatesAutoresizingMaskIntoConstraints = false
        confirmView.wantsLayer = true
        confirmView.isHidden = true

        let message = MenuPanelLabel.text("清除后需要重新填写 Key 才能查询额度。",
                                          font: SettingsTheme.rowSubtitleFont,
                                          color: SettingsTheme.textSecondary)
        message.maximumNumberOfLines = 2
        message.lineBreakMode = .byWordWrapping

        confirmButton.target = self
        confirmButton.action = #selector(confirmClearTapped)
        confirmCancelButton.target = self
        confirmCancelButton.action = #selector(cancelConfirmTapped)

        let row = NSStackView(views: [message, MenuPanelLabel.spacer(),
                                      confirmButton, confirmCancelButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        confirmView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: confirmView.leadingAnchor,
                                         constant: SettingsStyle.rowInset),
            row.trailingAnchor.constraint(equalTo: confirmView.trailingAnchor,
                                          constant: -SettingsStyle.rowInset),
            row.topAnchor.constraint(equalTo: confirmView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: confirmView.bottomAnchor, constant: -10),
        ])
        updateChromeColors()
    }

    /// 编辑区 / 确认区底色（强调色 6% / 破坏性色 7%）
    ///
    /// 两者都从主题令牌取：强调色随主题、破坏性色走 `SettingsTheme.destructive` 单一出口。
    func updateChromeColors() {
        editorView.layer?.backgroundColor = SettingsTheme.accent.withAlphaComponent(0.06).cgColor
        confirmView.layer?.backgroundColor = SettingsTheme.destructive.withAlphaComponent(0.07).cgColor
    }

    // MARK: - 编辑区

    @objc func editTapped() {
        if isEditorExpanded {
            endEditing()
            return
        }
        isConfirmExpanded = false
        confirmView.isHidden = true
        editorView.isHidden = false
        isEditorExpanded = true
        editorMessage.isHidden = true
        field.stringValue = ""
        field.placeholderString = placeholderText()
        updateEditorNote(now: Date())
        onEditingChanged?(true)
        window?.makeFirstResponder(field)
    }

    /// 收起编辑区（保存 / 取消时由外部或内部调用）
    func endEditing() {
        guard isEditorExpanded else { return }
        isEditorExpanded = false
        editorView.isHidden = true
        field.stringValue = ""
        onEditingChanged?(false)
    }

    @objc func saveTapped() {
        onSave?(field.stringValue)
    }

    @objc func cancelTapped() {
        endEditing()
    }

    /// 空输入且未配置时的行内提示（红色小字）
    func showEditorMessage(_ message: String) {
        editorMessage.stringValue = message
        editorMessage.isHidden = false
        window?.makeFirstResponder(field)
    }

    /// 展开 / 收起时统一更新背景（只在颜色变化时重绘）
    func updateEditorChrome() {
        editorView.needsLayout = true
        confirmView.needsLayout = true
    }

    func updateEditorNote(now: Date) {
        let font = SettingsTheme.noteFont
        let secondary = SettingsTheme.textSecondary
        let text = NSMutableAttributedString()
        func append(_ string: String, color: NSColor = secondary) {
            text.append(NSAttributedString(string: string,
                                           attributes: [.font: font, .foregroundColor: color]))
        }
        if !isEnabled {
            append("已停用，暂停刷新")
        } else if !isConfigured {
            append("尚未配置凭据，保存后即可查询")
        } else {
            append("上次查询：")
            if let errorMessage, !errorMessage.isEmpty {
                append(errorMessage, color: SettingsTheme.destructive)
            } else if lastUpdated != nil {
                append("成功")
            } else {
                append("尚无结果")
            }
            append(" · ")
            guard let lastAttempt else {
                append("等待首次查询")
                editorNote.attributedStringValue = text
                return
            }
            let remaining = max(0, interval - now.timeIntervalSince(lastAttempt))
            let seconds = Int(remaining.rounded())
            let countdown = seconds >= 60
                ? "\(seconds / 60) 分 \(String(format: "%02d", seconds % 60)) 秒"
                : "\(seconds) 秒"
            append("下次刷新 剩余 \(countdown)")
        }
        editorNote.attributedStringValue = text
        updateEditorChrome()
    }

    // MARK: - 清除确认

    @objc func clearTapped() {
        if isConfirmExpanded {
            endConfirm()
            return
        }
        if isEditorExpanded { endEditing() }
        isConfirmExpanded = true
        confirmView.isHidden = false
        onEditingChanged?(true)
    }

    func endConfirm() {
        guard isConfirmExpanded else { return }
        isConfirmExpanded = false
        confirmView.isHidden = true
        onEditingChanged?(false)
    }

    @objc func confirmClearTapped() {
        onClearConfirmed?()
    }

    @objc func cancelConfirmTapped() {
        endConfirm()
    }

    // MARK: - 控件工厂

    static func textButton(_ title: String,
                           color: NSColor = SettingsTheme.accent) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.controlSize = .small
        button.font = SettingsTheme.rowTitleFont
        button.contentTintColor = color
        // 文字按钮与右侧开关同在一行：给同一档 22pt 高，横线才对得齐（不改字号与行为）
        SettingsControlChrome.applyStandardHeight(to: button)
        return button
    }

    static func primaryButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.bezelColor = SettingsTheme.accent
        button.contentTintColor = .white
        SettingsControlChrome.applyStandardHeight(to: button)
        return button
    }
}

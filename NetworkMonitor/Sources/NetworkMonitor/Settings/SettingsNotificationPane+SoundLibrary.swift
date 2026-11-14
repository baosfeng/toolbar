import AppKit
import NetworkMonitorCore
import UniformTypeIdentifiers

// MARK: - 通知与音效设置页（音效库）

/// 音效库 — 应用内音量、自定义音效的上传 / 试听 / 重命名 / 删除
///
/// 拆出原因：主文件负责授权、恢复默认与页内说明，
/// 音效库的增删改查自带面板与对话框，合在一处会顶到单文件 15 KiB 上限。
///
/// 能力边界（实测结论，界面里如实写）：
/// - 应用内提示音：任意已支持格式，试听即真实播放；
/// - 系统通知音：系统只按文件名在 App bundle 与 ~/Library/Sounds 里找，
///   因此上传后会把 AIFF 转码副本同步进 ~/Library/Sounds（NetworkMonitor- 前缀），
///   删除音效时副本一并清掉；
/// - 系统通知列表的横幅样式 / 停留时长由系统设置决定，App 只能控制「有没有声音」。
extension SettingsNotificationPane {

    // MARK: - 构建

    /// 音效库卡：音量 + 上传 + 自定义列表
    func buildSoundLibraryCard() {
        let card = SettingsCardView()

        // 应用内音量
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        volumeSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        volumeSlider.setAccessibilityLabel("应用内提示音音量")
        volumeValueLabel.font = SettingsTheme.rowValueFont
        volumeValueLabel.textColor = SettingsTheme.textSecondary
        let volumeRow = SettingsRowView(title: "应用内音量",
                                        subtitle: "只影响应用内提示音；系统通知音量由系统「声音」设置决定")
        volumeRow.trailingStack.addArrangedSubview(volumeSlider)
        volumeRow.trailingStack.addArrangedSubview(volumeValueLabel)
        card.addRow(volumeRow)

        // 上传
        let uploadRow = SettingsRowView(title: "自定义音效",
                                        subtitle: "支持 wav / aiff / caf / mp3 / m4a，≤10 MB、≤30 秒")
        uploadButton.bezelStyle = .rounded
        uploadButton.target = self
        uploadButton.action = #selector(uploadTapped)
        uploadButton.setAccessibilityLabel("上传音效")
        SettingsControlChrome.applyStandardHeight(to: uploadButton)
        uploadRow.trailingStack.addArrangedSubview(uploadButton)
        card.addRow(uploadRow)

        // 自定义列表（每次 refresh 重建内部行）
        customListStack.orientation = .vertical
        customListStack.alignment = .leading
        customListStack.spacing = 0
        customListStack.distribution = .fill
        card.addRow(customListStack)
        customListStack.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -24).isActive = true

        page.addCard(card, sectionTitle: "音效库")
        page.addNote("上传的音频会转成 AIFF 并复制一份到 ~/Library/Sounds"
                     + "（系统通知只从这个目录按文件名取音效）。删除音效时这份副本一并清理；"
                     + "「恢复默认」不会删你的自定义音效。")
    }

    // MARK: - 列表刷新

    /// 重建自定义音效列表（上传 / 重命名 / 删除之后调用）
    func refreshSoundLibrary() {
        volumeSlider.doubleValue = preferences.inAppVolume
        volumeValueLabel.stringValue = "\(Int((preferences.inAppVolume * 100).rounded()))%"
        let files = library.customFiles()
        customListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !files.isEmpty else {
            let empty = MenuPanelLabel.text("还没有自定义音效，点「上传…」选一段音频",
                                            font: SettingsTheme.rowSubtitleFont,
                                            color: SettingsTheme.textTertiary)
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            empty.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 12),
                empty.topAnchor.constraint(equalTo: holder.topAnchor, constant: 10),
                empty.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -10),
            ])
            customListStack.addArrangedSubview(holder)
            holder.widthAnchor.constraint(equalTo: customListStack.widthAnchor).isActive = true
            return
        }
        for file in files {
            let row = makeCustomRow(file)
            customListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: customListStack.widthAnchor).isActive = true
        }
    }

    /// 单个自定义音效行：名字 + 试听 / 重命名 / 删除
    private func makeCustomRow(_ file: String) -> NSView {
        let size = library.store.totalBytes()
        let row = SettingsRowView(title: library.displayTitle(for: file),
                                  subtitle: "自定义音效 · 目录共 \(formatBytes(size))")
        let preview = SettingsLinkButton.make("试听", target: self, action: #selector(previewCustom(_:)))
        preview.identifier = NSUserInterfaceItemIdentifier(file)
        row.trailingStack.addArrangedSubview(preview)
        let rename = SettingsLinkButton.make("重命名", target: self, action: #selector(renameCustom(_:)))
        rename.identifier = NSUserInterfaceItemIdentifier(file)
        row.trailingStack.addArrangedSubview(rename)
        let remove = SettingsLinkButton.make("删除", target: self, action: #selector(deleteCustom(_:)),
                                             color: SettingsTheme.destructive)
        remove.identifier = NSUserInterfaceItemIdentifier(file)
        row.trailingStack.addArrangedSubview(remove)
        return row
    }

    // MARK: - 动作

    @objc func volumeChanged(_ sender: NSSlider) {
        preferences.inAppVolume = sender.doubleValue
        volumeValueLabel.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
        refreshStatusChip()
    }

    @objc func uploadTapped() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .wav, .mp3, .mpeg4Audio, .aiff, .audio]
        panel.message = "选择一段音频作为自定义提示音（≤10 MB、≤30 秒）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileName = try library.importSound(from: url)
            logger.info("自定义音效已导入：\(fileName)")
            afterSoundLibraryChange()
        } catch let rejection as SoundFileRejection {
            presentError(rejection.message)
        } catch {
            presentError("导入失败：\(error.localizedDescription)")
        }
    }

    @objc func previewCustom(_ sender: NSButton) {
        guard let file = sender.identifier?.rawValue else { return }
        // 试听直接用自定义文件本身，不读事件配置：用户点的是这份文件，听到的就该是它
        player.preview(selection: .customFile(file), cue: .copy)
    }

    @objc func renameCustom(_ sender: NSButton) {
        guard let file = sender.identifier?.rawValue else { return }
        let alert = NSAlert()
        alert.messageText = "重命名音效"
        alert.informativeText = "只改显示名，音频内容不变"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = library.displayTitle(for: file)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let newName = try library.rename(file, to: field.stringValue)
            // 事件里引用的还是旧文件名：改名后一并改引用，否则那个事件会静默失声
            rewriteSoundReferences(from: file, to: newName)
            afterSoundLibraryChange()
        } catch {
            presentError("重命名失败：\(error.localizedDescription)")
        }
    }

    @objc func deleteCustom(_ sender: NSButton) {
        guard let file = sender.identifier?.rawValue else { return }
        let alert = NSAlert()
        alert.messageText = "删除自定义音效「\(library.displayTitle(for: file))」？"
        alert.informativeText = "引用它的场景会回到「跟随系统」；已同步到 ~/Library/Sounds 的副本一并清理。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try library.remove(file)
            clearSoundReferences(to: file)
            afterSoundLibraryChange()
        } catch {
            presentError("删除失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 引用维护

    /// 改名后把引用旧文件的事件切到新文件
    func rewriteSoundReferences(from oldName: String, to newName: String) {
        for event in NotificationEvent.allCases
        where preferences.config(for: event).sound == .customFile(oldName) {
            preferences.setSound(.customFile(newName), for: event)
        }
    }

    /// 删除后把引用它的事件回落成「跟随系统」
    func clearSoundReferences(to fileName: String) {
        for event in NotificationEvent.allCases
        where preferences.config(for: event).sound == .customFile(fileName) {
            preferences.setSound(.systemDefault, for: event)
        }
    }

    /// 音效库变化后统一收尾：重画自定义列表、同步通知副本
    ///
    /// 事件行的声音下拉已分散到各功能页，且设置页切走即释放、
    /// 下次进入按当时的音效库重建选项，因此这里不做跨页刷新。
    func afterSoundLibraryChange() {
        refreshSoundLibrary()
        service.syncInstalledSounds()
    }

    // MARK: - 辅助

    /// 报错对话框（导入 / 改名 / 删除失败）
    func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 字节数 → 可读体积（音效目录只有 KB 级，固定 KB/MB 两档即可）
    func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
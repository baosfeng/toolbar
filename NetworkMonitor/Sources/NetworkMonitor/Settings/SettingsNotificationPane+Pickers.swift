import AppKit
import NetworkMonitorCore

// MARK: - 通知与音效设置页（三张选择卡）

/// 提示音 / 提醒方式 / 触控板手感三张卡 — 每个事件一行一个下拉
///
/// 拆出原因：主文件已含授权卡、事件表、音效库与恢复默认，加上三张选择卡会超单文件 15 KiB。
/// 拆法按「一页里的一个维度」走：这里只负责「选什么」，落盘与生效由偏好与播放器负责。
extension SettingsNotificationPane {

    /// 提示音：每个事件一个声音下拉 + 试听
    /// 提示音卡（+Pickers 扩展文件）
    func buildSoundCard() {
        let card = SettingsCardView()
        for event in NotificationEvent.allCases {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.target = self
            popup.action = #selector(soundChanged(_:))
            popup.tag = NotificationEvent.allCases.firstIndex(of: event) ?? 0
            popup.setAccessibilityLabel("\(event.label)提示音")
            popup.widthAnchor.constraint(equalToConstant: 168).isActive = true
            soundPopups[event] = popup

            let row = SettingsRowView(title: "\(event.label)提示音")
            row.trailingStack.addArrangedSubview(popup)
            let preview = SettingsLinkButton.make("试听", target: self, action: #selector(previewTapped(_:)))
            preview.tag = NotificationEvent.allCases.firstIndex(of: event) ?? 0
            row.trailingStack.addArrangedSubview(preview)
            card.addRow(row)
            rebuildSoundPopup(event)
        }
        page.addCard(card, sectionTitle: "提示音")
    }

    /// 提醒方式：只对发系统通知的事件有效
    /// 提醒方式卡（+Pickers）
    func buildPresentationCard() {
        let card = SettingsCardView()
        for event in NotificationEvent.allCases where event.postsSystemNotification {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: NotificationPresentation.allCases.map(\.label))
            popup.target = self
            popup.action = #selector(presentationChanged(_:))
            popup.tag = NotificationEvent.allCases.firstIndex(of: event) ?? 0
            popup.setAccessibilityLabel("\(event.label)提醒方式")
            popup.widthAnchor.constraint(equalToConstant: 168).isActive = true
            presentationPopups[event] = popup
            let row = SettingsRowView(title: "\(event.label)提醒方式")
            row.trailingStack.addArrangedSubview(popup)
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "提醒方式")
    }

    /// 触控板手感
    /// 触控板手感卡（+Pickers）
    func buildHapticCard() {
        let card = SettingsCardView()
        for event in NotificationEvent.allCases {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: NotificationHaptic.allCases.map(\.label))
            popup.target = self
            popup.action = #selector(hapticChanged(_:))
            popup.tag = NotificationEvent.allCases.firstIndex(of: event) ?? 0
            popup.setAccessibilityLabel("\(event.label)触控板手感")
            popup.widthAnchor.constraint(equalToConstant: 120).isActive = true
            hapticPopups[event] = popup
            let row = SettingsRowView(title: "\(event.label)手感")
            row.trailingStack.addArrangedSubview(popup)
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "触控板手感")
    }

    @objc private func soundChanged(_ sender: NSPopUpButton) {
        guard let event = event(for: sender),
              let selection = selectedSound(for: sender) else { return }
        preferences.setSound(selection, for: event)
        service.syncInstalledSounds()
        logger.debug("事件 \(event.rawValue) 提示音改为 \(selection.storageValue)")
    }

    @objc private func presentationChanged(_ sender: NSPopUpButton) {
        guard let event = event(for: sender) else { return }
        let index = sender.indexOfSelectedItem
        guard NotificationPresentation.allCases.indices.contains(index) else { return }
        preferences.setPresentation(NotificationPresentation.allCases[index], for: event)
    }

    @objc private func hapticChanged(_ sender: NSPopUpButton) {
        guard let event = event(for: sender) else { return }
        let index = sender.indexOfSelectedItem
        guard NotificationHaptic.allCases.indices.contains(index) else { return }
        let level = NotificationHaptic.allCases[index]
        preferences.setHaptic(level, for: event)
        // 立刻震一下：手感这种东西只能当场试，选完没反应等于没选
        if level.isEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(HapticFeedback.pattern(for: level),
                                                             performanceTime: .now)
        }
    }

/// 声音下拉的全部选项（跟随系统 / 静音 / 系统音效库 / 自定义）
    func soundOptions() -> [(selection: NotificationSoundSelection, title: String)] {
        var options: [(NotificationSoundSelection, String)] = [
            (.systemDefault, "跟随系统"),
            (.silent, "静音"),
        ]
        for sound in library.systemSounds() {
            options.append((.systemSound(sound.name), "系统 · \(sound.title)"))
        }
        for file in library.customFiles() {
            options.append((.customFile(file), "自定义 · \(library.displayTitle(for: file))"))
        }
        return options
    }

    /// 重建某个事件的声音下拉（选项集合随音效库变化）
    func rebuildSoundPopup(_ event: NotificationEvent) {
        guard let popup = soundPopups[event] else { return }
        let options = soundOptions()
        popup.removeAllItems()
        popup.addItems(withTitles: options.map(\.title))
        let current = preferences.config(for: event).sound
        if let index = options.firstIndex(where: { $0.selection == current }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }
}
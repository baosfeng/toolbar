import AppKit
import Foundation
import NetworkMonitorCore

// MARK: - 通知音效安装

/// 通知音效安装 — 把「要用的音效」放进 ~/Library/Sounds，供系统通知按名字取用
///
/// 为什么必须在 ~/Library/Sounds 放一份（实测结论）：
/// - UNNotificationSound(named:) 只按文件名在「App bundle 的 Resources」与
///   「~/Library/Sounds」两处查找，路径里出现目录名就找不到；
/// - 用户上传的音效存在 App Support 目录里，系统通知 daemon 读不到；
///   因此发送前必须复制到 ~/Library/Sounds，并按文件名引用。
///
/// 命名与清理（有界判据）：
/// - 一律以 NotificationMonitor 前缀 NetworkMonitor- 命名，分 sys-（系统音）与 custom-（自定义）两族；
/// - 每次 sync 只清「本前缀且不在当前引用集」的副本，不扫描、不删除用户自己的其它音效。
@MainActor
final class NotificationSoundInstaller {

    /// 副本文件名前缀（本模块专属命名空间）
    static let fileNamePrefix = "NetworkMonitor-"
    /// 系统音副本前缀
    private static let systemPrefix = "NetworkMonitor-sys-"
    /// 自定义音副本前缀
    private static let customPrefix = "NetworkMonitor-custom-"

    private let store: NotificationSoundFileStore
    private let logger: LoggingService
    private let fileManager: FileManager
    /// ~/Library/Sounds（系统通知音查找目录）
    let soundsDirectory: URL

    init(store: NotificationSoundFileStore,
         logger: LoggingService = AppContext.shared.logger,
         soundsDirectory: URL? = nil,
         fileManager: FileManager = .default) {
        self.store = store
        self.logger = logger
        self.fileManager = fileManager
        self.soundsDirectory = soundsDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Sounds",
                                                                             isDirectory: true)
    }

    // MARK: - 名字映射

    /// 声音选择 → ~/Library/Sounds 里的文件名（不需要文件已存在，名字是确定性的）
    func installedName(for selection: NotificationSoundSelection) -> String? {
        switch selection {
        case .systemDefault, .silent:
            return nil
        case .systemSound(let name):
            guard let safe = SoundFileValidator.sanitizedDisplayName(name) else { return nil }
            return "\(Self.systemPrefix)\(safe).aiff"
        case .customFile(let file):
            guard let safe = SoundFileValidator.sanitizedDisplayName(file) else { return nil }
            return "\(Self.customPrefix)\(safe).aiff"
        }
    }

    // MARK: - 同步

    /// 按当前偏好同步副本，返回「引用集」文件名（供日志与自证）
    @discardableResult
    func sync(preferences: NotificationPreferences) -> [String] {
        var needed: [String: URL] = [:]
        for event in NotificationEvent.allCases {
            let sound = preferences.config(for: event).sound
            guard let target = installedName(for: sound) else { continue }
            if let source = sourceURL(for: sound) { needed[target] = source }
        }
        ensureDirectory()
        for (target, source) in needed {
            let destination = soundsDirectory.appendingPathComponent(target)
            // 内容可能变过（用户重传同名音效）：源文件改动时间更新时覆盖
            if fileManager.fileExists(atPath: destination.path),
               !shouldReplace(source: source, destination: destination) {
                continue
            }
            try? fileManager.removeItem(at: destination)
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                logger.warning("通知音效安装失败：\(target)（\(error.localizedDescription)）")
            }
        }
        sweepOrphans(keeping: Set(needed.keys))
        logger.debug("通知音效已同步：\(needed.keys.sorted().joined(separator: "、"))")
        return needed.keys.sorted()
    }

    /// 删除本模块前缀下不再被引用的副本（只动自己的命名空间）
    private func sweepOrphans(keeping: Set<String>) {
        let names = (try? fileManager.contentsOfDirectory(atPath: soundsDirectory.path)) ?? []
        for name in names where name.hasPrefix(Self.fileNamePrefix) {
            guard !keeping.contains(name) else { continue }
            try? fileManager.removeItem(at: soundsDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - 内部

    /// 声音选择对应的源文件（系统音走 /System/Library/Sounds，自定义走 Store）
    private func sourceURL(for selection: NotificationSoundSelection) -> URL? {
        switch selection {
        case .systemDefault, .silent:
            return nil
        case .systemSound(let name):
            let url = URL(fileURLWithPath: "/System/Library/Sounds")
                .appendingPathComponent("\(name).aiff")
            return fileManager.fileExists(atPath: url.path) ? url : nil
        case .customFile(let file):
            return store.url(for: file)
        }
    }

    /// 源比目标新才覆盖（用户重传同名文件后副本要跟上）
    private func shouldReplace(source: URL, destination: URL) -> Bool {
        let sourceDate = (try? fileManager.attributesOfItem(atPath: source.path)[.modificationDate] as? Date) ?? nil
        let destinationDate = (try? fileManager.attributesOfItem(atPath: destination.path)[.modificationDate] as? Date) ?? nil
        guard let sourceDate, let destinationDate else { return true }
        return sourceDate > destinationDate
    }

    private func ensureDirectory() {
        guard !fileManager.fileExists(atPath: soundsDirectory.path) else { return }
        do {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.warning("无法创建 ~/Library/Sounds：\(error.localizedDescription)")
        }
    }
}

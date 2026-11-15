import Foundation

// MARK: - 内建音的通知副本命名

/// 内建音在 ~/Library/Sounds 里的副本命名 — 纯逻辑，安装器与测试共用同一份判据
///
/// 系统通知只按文件名在「App bundle 的 Resources」与「~/Library/Sounds」里查找，
/// 所以合成音必须复制进后者。命名带本模块前缀 + cue 名，清理就能用
/// 「前缀 + 已知 cue 集合」这个**有界判据**，而不是扫到什么删什么。
public enum CueSoundInstallName {

    /// 本模块内建音副本的文件名前缀
    public static let prefix = "NetworkMonitor-builtin-"

    /// 某个 cue 的通知副本文件名
    public static func fileName(for cue: NotificationCue) -> String {
        "\(prefix)\(CueSoundSynth.fileStem(for: cue)).\(CueSoundFileStore.fileExtension)"
    }

    /// 副本文件名 → cue（不是本模块的内建音副本时返回 nil）
    public static func cue(forFileName name: String) -> NotificationCue? {
        guard name.hasPrefix(prefix), name.hasSuffix(".\(CueSoundFileStore.fileExtension)") else {
            return nil
        }
        let stem = String(name.dropFirst(prefix.count).dropLast(CueSoundFileStore.fileExtension.count + 1))
        return NotificationCue.allCases.first { CueSoundSynth.fileStem(for: $0) == stem }
    }
}

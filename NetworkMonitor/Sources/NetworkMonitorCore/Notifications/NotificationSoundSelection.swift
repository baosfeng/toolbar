import Foundation

// MARK: - 声音选择

/// 声音选择 — 一个事件「响什么」的四种可能
///
/// 存储格式刻意用「kind:value」单字符串（偏好里可读、可回滚、可与旧值共存），
/// 解析失败一律回落到「跟随系统」，避免一条脏数据让整页设置读不出来。
public enum NotificationSoundSelection: Equatable, Sendable {
    /// 跟随系统（应用内按 cue 经典系统音；系统通知用系统默认音）
    case systemDefault
    /// 指定系统音效（/System/Library/Sounds 的文件名，无扩展名）
    case systemSound(String)
    /// 自定义上传的音效（Store 内的文件名）
    case customFile(String)
    /// 静音
    case silent

    /// 存储值：default / system:Glass / custom:foo.aiff / silent
    public var storageValue: String {
        switch self {
        case .systemDefault: return "default"
        case .systemSound(let name): return "system:\(name)"
        case .customFile(let file): return "custom:\(file)"
        case .silent: return "silent"
        }
    }

    /// 从存储值还原（未知格式回落 systemDefault）
    public init(storageValue: String) {
        let trimmed = storageValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "silent" { self = .silent; return }
        if let name = Self.value(of: trimmed, prefix: "system:"), !name.isEmpty {
            self = .systemSound(name); return
        }
        if let file = Self.value(of: trimmed, prefix: "custom:"), !file.isEmpty {
            self = .customFile(file); return
        }
        self = .systemDefault
    }

    private static func value(of raw: String, prefix: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }

    /// 是否「静音」
    public var isSilent: Bool { self == .silent }

    /// 设置页展示文案（文件名类取 Store 的可读名，由调用方传入解析器）
    public func label(customFileTitle: (String) -> String) -> String {
        switch self {
        case .systemDefault: return "跟随系统"
        case .systemSound(let name): return SystemSoundCatalog.menuTitle(for: name)
        case .customFile(let file): return "自定义 · \(customFileTitle(file))"
        case .silent: return "静音"
        }
    }
}

// MARK: - 应用内要播的声音

/// 应用内实际播放目标
public enum NotificationCueSound: Equatable, Sendable {
    /// 系统音效（NSSound(named: 名字)）
    case system(String)
    /// 自定义音效文件（Store 内文件名）
    case customFile(String)
}

// MARK: - 系统通知要用的声音

/// 系统通知声音方案 — 决定 UNNotificationContent.sound 怎么给
public enum NotificationSoundPlan: Equatable, Sendable {
    /// 系统默认通知音（UNNotificationSound.default）
    case systemDefault
    /// 具名音效：必须已安装到 ~/Library/Sounds（见 NotificationSoundInstaller）
    case named(String)
    /// 静音（content.sound = nil）
    case silent
}

// MARK: - 解析

/// 声音解析 — 纯逻辑：事件配置 → 应用内要播什么 / 通知挂什么
///
/// 两条口径写在这里而不是散在播放器与通知服务里：
/// 1. 应用内「跟随系统」用 cue 的经典音（失败仍旧 Basso），不等于通知的系统默认音；
/// 2. 提醒方式里没有「声音」的档位（仅横幅 / 仅通知中心）必须把通知音关掉，
///    否则用户选了「仅横幅」却仍听到声音，就是界面承诺与行为不一致。
public enum NotificationSoundResolver {

    /// 应用内 cue → 播放目标（nil = 不播）
    public static func cueSound(selection: NotificationSoundSelection,
                                cue: NotificationCue) -> NotificationCueSound? {
        switch selection {
        case .silent:
            return nil
        case .systemDefault:
            return .system(cue.defaultSystemSound)
        case .systemSound(let name):
            return .system(name)
        case .customFile(let file):
            return .customFile(file)
        }
    }

    /// 系统通知 → 声音方案
    ///
    /// - Parameters:
    ///   - selection: 该事件的声音选择
    ///   - presentation: 该事件的提醒方式（无声音档位直接静音）
    ///   - installedName: 把「系统音效名 / 自定义文件名」映射成 ~/Library/Sounds 里的文件名；
    ///     返回 nil 表示这份声音装不到通知目录（调用方回落到系统默认音）
    public static func notificationPlan(selection: NotificationSoundSelection,
                                        presentation: NotificationPresentation,
                                        installedName: (NotificationSoundSelection) -> String?) -> NotificationSoundPlan {
        guard presentation.includesSound else { return .silent }
        switch selection {
        case .silent:
            return .silent
        case .systemDefault:
            return .systemDefault
        case .systemSound, .customFile:
            guard let name = installedName(selection) else { return .systemDefault }
            return .named(name)
        }
    }
}

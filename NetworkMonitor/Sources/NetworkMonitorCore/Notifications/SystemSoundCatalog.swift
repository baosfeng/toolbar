import Foundation

// MARK: - 系统音效库

/// 系统音效库 — /System/Library/Sounds 下的固定资产
///
/// 只列 macOS 自带的 14 个音效（不依赖运行时扫描即可给出稳定清单，
/// 运行时扫到更多名字时以扫描结果为准、这里负责中文说明与兜底）。
/// 中文说明用于设置页下拉，避免用户在海量英文名里试听。
public struct SystemSound: Equatable, Sendable, Identifiable {
    /// 音效名（NSSound(named:) 与 /System/Library/Sounds/<name>.aiff 的名字）
    public let name: String
    /// 中文说明（设置页展示）
    public let title: String

    public var id: String { name }

    public init(name: String, title: String) {
        self.name = name
        self.title = title
    }

    /// 下拉里的一行：中文说明 + 英文原名
    public var menuTitle: String { "\(title)（\(name)）" }
}

// MARK: - 内置清单

/// 内置系统音效清单（与 macOS 出厂 14 个音效一致）
public enum SystemSoundCatalog {
    /// 出厂音效（顺序即设置页顺序）
    public static let builtIn: [SystemSound] = [
        SystemSound(name: "Basso", title: "低音提示"),
        SystemSound(name: "Blow", title: "吹气"),
        SystemSound(name: "Bottle", title: "空瓶"),
        SystemSound(name: "Frog", title: "青蛙"),
        SystemSound(name: "Funk", title: "放克"),
        SystemSound(name: "Glass", title: "玻璃"),
        SystemSound(name: "Hero", title: "英雄"),
        SystemSound(name: "Morse", title: "摩斯"),
        SystemSound(name: "Ping", title: "乒"),
        SystemSound(name: "Pop", title: "波普"),
        SystemSound(name: "Purr", title: "猫呼噜"),
        SystemSound(name: "Sosumi", title: "索苏米"),
        SystemSound(name: "Submarine", title: "潜水艇"),
        SystemSound(name: "Tink", title: "叮"),
    ]

    /// 按名字取中文说明（未知名字原样返回，运行时扫到新音效时不丢条目）
    public static func title(for name: String) -> String {
        builtIn.first { $0.name == name }?.title ?? name
    }

    /// 下拉的一行标题
    public static func menuTitle(for name: String) -> String {
        let title = title(for: name)
        return title == name ? name : "\(title)（\(name)）"
    }
}

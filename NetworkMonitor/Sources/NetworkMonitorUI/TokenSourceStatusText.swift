import Foundation

// MARK: - 来源状态分档（设置页来源清单的判据与文案）

/// 单个来源在 Token 设置页里的状态档
///
/// 为什么分四档而不是一句「暂无数据」：未安装（去装工具）、装了没会话（去用一次）、
/// 目录不可读（改权限）、有会话但没有 token 记录（工具版本太老）——四件事的处置完全不同，
/// 合并成一句会让用户在一个「什么都没读到」的界面上反复重扫。
///
/// 放在 NetworkMonitorUI（而不是 App 的 Settings 目录）：判据与文案是纯口径，
/// TestRunner 只依赖 NetworkMonitorUI，放这里才能被直接断言。
public enum TokenSourceStatus: Equatable {
    /// 目录不存在（该工具没装，或路径还没配）
    case notInstalled
    /// 目录存在但读不了（权限 / 卷未挂载）
    case unreadable
    /// 能读，但没有会话文件
    case noSessions
    /// 有会话，但没有 token 记录（老版本工具不写用量）
    case noTelemetry
    /// 有数据
    case ok

    /// 能不能打开来源开关（未安装 / 不可读时打开也没有意义）
    public var canEnable: Bool { self != .notInstalled }

    /// 状态点语气：黄 = 能读但没数据（绿/红/灰由视图映射到主题语义色）
    public var isWarning: Bool { self == .noSessions || self == .noTelemetry }
}

/// 状态推导与文案（纯函数，不碰视图与主题色）
public enum TokenSourceStatusText {

    /// 从「路径在不在 / 能不能读 / 有多少会话 / 有没有用量」推出状态档
    ///
    /// 判据只看来源的落地位置（是否存在、是否可读）：文件型来源是会话目录，
    /// SQLite 型来源（Copilot / OpenCode / Zed）是 **db 文件本身** —— 两类的四档语义完全一致，
    /// 调用方填 `directoryExists` / `readable` 时按来源类型去探路径即可。
    /// `isSQLite` 只影响文案，不改变分档。
    public static func status(directoryExists: Bool,
                              readable: Bool,
                              sessionCount: Int,
                              hasUsage: Bool,
                              isSQLite: Bool = false) -> TokenSourceStatus {
        _ = isSQLite
        guard directoryExists else { return .notInstalled }
        guard readable else { return .unreadable }
        guard sessionCount > 0 else { return .noSessions }
        return hasUsage ? .ok : .noTelemetry
    }

    /// 行副标题：路径 + 一句状态人话（+ 已知规模）
    ///
    /// 只写路径会让黄点行看起来「已经在监控了」，所以每种状态都配一句人话；
    /// 路径不可达但库里已有该源数据时，点仍按路径判为灰（判据只看路径），
    /// 文案写「已有索引数据保留」——判据与历史数据不矛盾，说清即可。
    /// SQLite 源的路径是 db 文件，文案一律说「数据库」，不说「目录」。
    public static func subtitle(path: String,
                                status: TokenSourceStatus,
                                counts: String?,
                                isSQLite: Bool = false) -> String {
        let head = path.isEmpty ? (isSQLite ? "未配置数据库文件" : "未配置目录") : path
        return head + " · " + state(status: status, counts: counts, isSQLite: isSQLite)
    }

    /// 状态说明（只在非 ok 时出现；ok 时返回 nil，不占位置）
    public static func note(for status: TokenSourceStatus, isSQLite: Bool = false) -> String? {
        switch status {
        case .notInstalled:
            return isSQLite ? "未检测到，点「选择数据库文件…」指定可读的库文件"
                            : "未检测到，点「选择目录…」指定可读的目录"
        case .unreadable:
            return isSQLite ? "数据库文件存在但读不了，检查权限或卷是否已挂载"
                            : "目录存在但读不了，检查权限或卷是否已挂载"
        case .noSessions:
            return isSQLite ? "数据库可读，但还没有可统计的用量记录"
                            : "目录可读，但还没有可统计的会话"
        case .noTelemetry:
            return isSQLite ? "记录里没有 token 用量（该工具版本可能不写用量）"
                            : "会话里没有 token 记录（该工具版本可能不写用量）"
        case .ok: return nil
        }
    }

    // MARK: - 内部

    /// 副标题里那句状态人话（文件型沿用原始文案，SQLite 型换成「数据库」措辞）
    private static func state(status: TokenSourceStatus, counts: String?, isSQLite: Bool) -> String {
        switch status {
        case .notInstalled:
            let kept = isSQLite ? "数据库文件不可达，已有索引数据保留" : "目录不可达，已有索引数据保留"
            return counts.map { kept + "（" + $0 + "）" }
                ?? (isSQLite ? "未安装（数据库文件不存在）" : "未安装（目录不存在）")
        case .unreadable:
            return isSQLite ? "数据库文件存在但不可读（检查权限或卷）"
                            : "目录存在但不可读（检查权限或卷）"
        case .noSessions:
            return isSQLite ? "数据库可读 · 未检测到用量记录" : "目录存在 · 未检测到会话数据"
        case .noTelemetry:
            return isSQLite ? "数据库可读 · 记录里没有 token 用量（版本可能不写用量）"
                            : "目录存在 · 会话里没有 token 记录（版本可能不写用量）"
        case .ok:
            let head = isSQLite ? "数据库可读 · 已索引 " : "目录可读 · 已索引 "
            return counts.map { head + $0 } ?? (isSQLite ? "数据库可读 · 有数据" : "目录可读 · 有数据")
        }
    }
}

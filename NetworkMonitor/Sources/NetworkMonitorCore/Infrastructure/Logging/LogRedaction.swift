import Foundation

// MARK: - 日志脱敏

/// 日志脱敏 — 所有进入 OSLog 的用户相关内容必须先过这里
///
/// 背景：`OSLogLogger` 一律用 `%{public}@` 输出（`Loggers.swift`），
/// 而 public 字段**不需要特权**——任何本机进程执行
/// `log show --predicate 'subsystem == "com.networkmonitor"'` 都能读到全文。
/// 因此凡是用户目录路径、配对 PIN、凭据这类内容，写日志前必须脱敏。
///
/// 原则：日志要能定位问题，但不能让读到日志的人因此获得权限或隐私。
public enum LogRedaction {
    /// 把用户主目录前缀替换为 `~`，保留相对结构
    ///
    /// `/Users/alice/Library/...` → `~/Library/...`：路径结构（判断是哪个目录、
    /// 有没有写错层级）全部保留，只隐去用户名。
    public static func path(_ raw: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty, raw.hasPrefix(home) else { return raw }
        return "~" + raw.dropFirst(home.count)
    }

    /// 遮蔽敏感短码（配对 PIN 等）：保留位数，不保留任何一位数字
    ///
    /// PIN 只有 4 位，留前 2 位等于泄露一半搜索空间，所以只报长度。
    public static func pin(_ value: String) -> String {
        "<\(value.count) 位已隐藏>"
    }

    /// 遮蔽长凭据（API Key / session cookie 等）：保留末 4 位便于核对是哪一条
    public static func secret(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "<已隐藏>" }
        return "***" + trimmed.suffix(4)
    }
}

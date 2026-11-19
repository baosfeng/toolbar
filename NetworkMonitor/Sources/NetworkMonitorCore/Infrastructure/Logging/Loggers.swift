import Foundation
import OSLog

// MARK: - OSLog 日志实现

/// 基于 os_log 的日志服务实现
///
/// 使用统一的 OSLog subsystem，支持日志级别过滤。
/// 生产环境默认只记录 info 及以上级别。
public final class OSLogLogger: LoggingService {
    private let osLog: OSLog
    private let minLevel: LogLevel

    /// 默认子系统
    public static let defaultSubsystem = "com.networkmonitor"

    /// 初始化
    /// - Parameters:
    ///   - subsystem: OSLog subsystem 标识
    ///   - category: 日志分类
    ///   - minLevel: 最低记录级别（默认 `.info`，与类文档一致）
    ///
    /// 默认值一度是 `.debug`，与「生产只记 info 及以上」的注释相反：
    /// 剪贴板采集、采样轮询这类高频 debug 日志会全部落盘，既放大日志体积，
    /// 也放大 public 字段的内容暴露面。需要 debug 时在组合根显式传 `.debug`。
    public init(subsystem: String = defaultSubsystem, category: String = "General",
                minLevel: LogLevel = .info) {
        self.osLog = OSLog(subsystem: subsystem, category: category)
        self.minLevel = minLevel
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard shouldLog(level) else { return }

        let osLogType: OSLogType
        switch level {
        case .debug:   osLogType = .debug
        case .info:    osLogType = .info
        case .warning: osLogType = .default
        case .error:   osLogType = .error
        }

        // %{public}：让 `log show` 无需特权即可读到全文（调试需要），
        // 代价是任何本机进程也能读——用户路径 / PIN / 凭据一律先过 LogRedaction
        os_log(osLogType, log: osLog, "%{public}@", message)
    }

    /// 判断当前级别是否需要记录
    private func shouldLog(_ level: LogLevel) -> Bool {
        let order: [LogLevel: Int] = [.debug: 0, .info: 1, .warning: 2, .error: 3]
        return (order[level] ?? 0) >= (order[minLevel] ?? 0)
    }
}

// MARK: - 控制台日志实现（测试用）

/// 控制台日志实现 — 直接 `print` 输出，适合开发/测试环境
///
/// 用途分两档，避免「stdout 只有失败信息」导致现场无法三态判读：
/// - error / warning 走 stderr（原有的 `2>` 分流不变）；
/// - info 走 stdout（诊断时 `2>/dev/null` 即可只留「成功 / 不可得」）；
/// - debug 仍然丢弃（高频采样日志不该落盘）。
///
/// 另设字符预算：CLI 跑全量套件时 stdout 会被探针快照淹没，超预算后截断并只提示一次，
/// 保证「额度行」仍可被 grep 到。按**字符数**计量：UTF-8 下中文 3 字节，
/// 按字节算会低估真实占用。
public final class ConsoleLogger: LoggingService, @unchecked Sendable {
    private let minLevel: LogLevel
    private let dateFormatter: DateFormatter
    /// 控制台输出字符上限（0 = 不限）
    private let characterLimit: Int
    /// 预算与截断标记只在锁内读写（`@unchecked Sendable` 的来由）
    private let budgetLock = NSLock()
    private var characterCount = 0
    private var isTruncated = false

    public init(minLevel: LogLevel = .debug, characterLimit: Int = 400_000) {
        self.minLevel = minLevel
        self.characterLimit = characterLimit
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    public func log(_ level: LogLevel, _ message: String) {
        let order: [LogLevel: Int] = [.debug: 0, .info: 1, .warning: 2, .error: 3]
        guard (order[level] ?? 0) >= (order[minLevel] ?? 0) else { return }

        let timestamp = dateFormatter.string(from: Date())
        let prefix: String
        switch level {
        case .debug:   prefix = "🔍"
        case .info:    prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error:   prefix = "❌"
        }
        let line = "[\(timestamp)] \(prefix) [\(level.rawValue)] \(message)"

        // error / warning 必须落盘（三态判读的最后一道），只让 info 吃预算
        if level == .info {
            budgetLock.lock()
            let exhausted = isTruncated || (characterLimit > 0 && characterCount + line.count > characterLimit)
            if exhausted, !isTruncated {
                isTruncated = true
                FileHandle.standardError.write(Data("[…] 控制台日志已达 \(characterLimit) 字符上限，后续 info 日志丢弃\n".utf8))
            } else if !exhausted {
                characterCount += line.count
            }
            budgetLock.unlock()
            if exhausted { return }
        }

        if level == .warning || level == .error {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        } else if level == .info {
            print(line)
        }
    }
}

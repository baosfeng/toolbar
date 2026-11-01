import AppKit
import QuartzCore

// MARK: - 面板打开耗时探针（仅 DEBUG）

#if DEBUG

/// 面板打开分阶段计时 — **仅 DEBUG**；--measure-panel-open 时启用，其余时刻两个打点函数
/// 首行判空即返回，对正常路径几乎零开销。
///
/// 两种打点口径：
/// - mark(_:)：**顺序**打点。某阶段耗时 = 与下一点的时间差（名字取该段起点），
///   用于 show() / refreshAll() 这种线性执行的阶段。
/// - bucket(_:_:)：**独立累计**。允许被嵌套重入（如 updateContentSize 会被多个阶段回调），
///   记总耗时与次数，互不干扰。
@MainActor
enum PanelOpenProbe {

    /// 触发开关（命令行参数）
    static let argumentName = "--measure-panel-open"
    /// 触发开关（环境变量，便于脚本调用）
    static let envKey = "NM_MEASURE_PANEL_OPEN"

    /// 单轮记录（一轮 = 一次面板打开）
    struct Round {
        var marks: [(name: String, time: Double)] = []
        var buckets: [String: (total: Double, count: Int)] = [:]
    }

    /// 是否正在计时
    private(set) static var isRunning = false
    /// 当前轮
    private static var current = Round()
    /// 已完成轮次
    private(set) static var rounds: [Round] = []

    /// 命令行 / 环境变量是否要求测量
    static var requested: Bool {
        CommandLine.arguments.contains(argumentName)
            || ProcessInfo.processInfo.environment[envKey]?.isEmpty == false
    }

    static func begin() {
        isRunning = true
        rounds.removeAll()
        current = Round()
    }

    static func beginRound() { current = Round() }

    /// 结束本轮；keep = false 时丢弃（该轮面板没有真正打开，数据无效）
    static func endRound(keep: Bool = true) {
        if keep { rounds.append(current) }
        current = Round()
    }

    static func finish() { isRunning = false }

    /// 顺序打点
    @inline(__always)
    static func mark(_ name: String) {
        guard isRunning else { return }
        current.marks.append((name, CACurrentMediaTime()))
    }

    /// 独立累计：闭包形式（release 构建里探针为空实现，生产代码无需 #if）
    @inline(__always)
    static func bucket<T>(_ name: String, _ body: () -> T) -> T {
        guard isRunning else { return body() }
        let start = CACurrentMediaTime()
        let value = body()
        addBucket(name, CACurrentMediaTime() - start)
        return value
    }

    private static func addBucket(_ name: String, _ seconds: Double) {
        var entry = current.buckets[name] ?? (0, 0)
        entry.total += seconds
        entry.count += 1
        current.buckets[name] = entry
    }
}

#else

/// release：探针编译为空操作 — 面板打开路径零额外开销
@MainActor
enum PanelOpenProbe {
    /// release 构建不提供测量入口
    @inline(__always) static var requested: Bool { false }
    @inline(__always) static func mark(_ name: String) {}
    @inline(__always) static func bucket<T>(_ name: String, _ body: () -> T) -> T { body() }
}

#endif

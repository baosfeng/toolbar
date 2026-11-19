import Foundation

// MARK: - 断言失败累计器

/// 断言失败累计器 —— 一次运行看到全部红，而不是第一个就退出
///
/// 为什么改：`assertEqual` 原先失败即 `exit(1)`，一个套件里有多处不合格时
/// 只能「修一条 → 跑一次全量 → 再看下一条」，而全量跑一次要几十秒。
/// 改成累计后，一次运行打印全部 ❌ 行，套件跑完在 `finish()` 统一收口。
///
/// 不变的部分：
/// - **退出码语义**：0 = 全绿，非 0 = 有失败；`finish()` 是全绿时 `exit(0)`，
///   有失败时 `exit(1)`（与改造前一致）。
/// - **前置条件失败仍然即停**：各套件里 `guard ... else { exit(1) }` 这类
///   「后续断言没有意义」的失败不走累计器，保持立即退出。
///
/// 并发：TestRunner 是单线程顺序执行的命令行程序，这里的可变全局状态只在
/// 主线程读写，故用 `nonisolated(unsafe)` 显式声明。
enum TestAssertions {

    /// 明细上限 —— 超过只计数不打印，避免一处错误的批量断言把日志刷爆
    private static let maxRecordedFailures = 200

    /// 累计失败条数
    nonisolated(unsafe) private(set) static var failureCount = 0

    /// 失败明细（最多 `maxRecordedFailures` 条）
    nonisolated(unsafe) private(set) static var recordedFailures: [String] = []

    /// 记录一条失败（断言辅助内部调用，不直接对外）
    static func recordFailure(_ detail: String) {
        failureCount += 1
        guard recordedFailures.count < maxRecordedFailures else { return }
        recordedFailures.append(detail)
    }

    /// 统一出口 —— 程序最后一步调用，打印汇总并按退出码退出
    ///
    /// 全绿时的收尾语与改造前逐字一致（`🎉 所有测试通过！`）：CI 与
    /// `Scripts/release.sh` 都按这条串判绿，不能改文案。
    static func finish() {
        guard failureCount > 0 else {
            print("\n🎉 所有测试通过！")
            exit(0)
        }

        print("\n❌ 失败 \(failureCount) 条（全部明细见上方 ❌ 行）")
        let hidden = failureCount - recordedFailures.count
        if hidden > 0 {
            print("   以下列出前 \(recordedFailures.count) 条，其余 \(hidden) 条只计数未打印：")
        }
        for detail in recordedFailures {
            print("   · \(detail)")
        }
        exit(1)
    }
}

import Foundation
import NetworkMonitorCore

// MARK: - 主线程看门狗口径（阈值 / 日志字段 / 脱敏）

func runMainThreadWatchdogPolicyTests() {
    print("🧪 Testing 主线程看门狗口径...")
    assertEqual(MainThreadWatchdogPolicy.tickSeconds, 0.5, "看护节拍 0.5 s")
    assertEqual(MainThreadWatchdogPolicy.stallThresholdSeconds, 2, "停顿阈值 2 s")
    assertEqual(MainThreadWatchdogPolicy.isStalled(gapSeconds: 0.5), false, "0.5 s 不算停顿")
    assertEqual(MainThreadWatchdogPolicy.isStalled(gapSeconds: 2), false, "刚好 2 s 不算停顿（严格大于阈值）")
    assertEqual(MainThreadWatchdogPolicy.isStalled(gapSeconds: 2.01), true, "2.01 s 算停顿")

    // 日志字段：停顿时长 + 当前分页 + 面板展开 + 索引状态，且索引状态里的路径必须脱敏
    let home = NSHomeDirectory()
    let message = MainThreadWatchdogPolicy.message(
        gapSeconds: 2.65, tab: "token", panelShown: true,
        indexingState: "failed: 未找到 DSH 会话目录: " + home + "/.dsh/sessions")
    assertContains(message, "2.6 s", "含停顿时长")
    assertContains(message, "分页=token", "含当前分页")
    assertContains(message, "面板展开=是", "含面板展开态")
    assertContains(message, "failed", "含索引失败状态")
    assertContains(message, "~/.dsh/sessions", "用户主目录脱敏成 ~")
    assertNotContains(message, home, "不得出现真实主目录")

    let closed = MainThreadWatchdogPolicy.message(gapSeconds: 2.1, tab: "network", panelShown: false,
                                                 indexingState: HarnessIndexingState.idle.logLabel)
    assertContains(closed, "面板展开=否", "收起态写成否")
    assertContains(closed, "Token索引=idle", "索引状态用短标签")

    // 短标签：进度带分数、ready / idle 直出
    assertEqual(HarnessIndexingState.ready.logLabel, "ready", "ready 短标签")
    let progress = HarnessIndexProgress(completedFiles: 3, totalFiles: 10, currentFile: "s", parsedSessions: 3)
    assertEqual(HarnessIndexingState.indexing(progress).logLabel, "indexing 3/10", "进度短标签")
}

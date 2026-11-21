import Foundation
import NetworkMonitorCore
import NetworkMonitorFeatureDiagnostics
import NetworkMonitorFeatureFeedback

// MARK: - 反馈层 / 诊断层（独立 target）边界测试

/// 跨 target 断言：剪贴板反馈的 cue 转发与触觉映射住在新拆出的 `NetworkMonitorFeatureFeedback`，
/// 主线程看门狗的心跳现场住在新拆出的 `NetworkMonitorFeatureDiagnostics`；
/// TestRunner 直接 import 两个模块、走真实入口（端口转发 / 档位映射 / 停顿判定）。
///
/// 改造前这两条都测不到：两类逻辑在可执行 target `NetworkMonitor` 里够不着，
/// 测试只能断言 Core 的判据（MainThreadWatchdogPolicyTests），
/// 无法证明「看门狗真的按判据判停、且把上下文带进日志」。
@MainActor
func runFeatureBoundaryTests() {
    print("\n🧪 Testing 反馈层 / 诊断层跨 target 边界（cue 转发 / 触觉映射 / 心跳现场）...")
    testSoundFeedbackForwardsCue()
    testHapticKindMapping()
    testWatchdogHeartbeatContext()
    testWatchdogReportsEachStallOnce()
    print("✅ 反馈层 / 诊断层跨 target 边界 works")
}

// MARK: - 音效转发

/// 记录被要求播放的 cue（替代真实 NSSound 播放器，不碰 AppKit 与音效库）
@MainActor
private final class RecordingCuePlayer: FeedbackSoundPlaying {
    private(set) var played: [NotificationCue] = []

    func play(_ cue: NotificationCue) {
        played.append(cue)
    }
}

@MainActor
private func testSoundFeedbackForwardsCue() {
    let player = RecordingCuePlayer()
    // 经公共协议持有：这行能编译即证明 ClipboardSoundPerforming 一致性在新 target 里
    let sound: any ClipboardSoundPerforming = SoundFeedback(player: player)
    sound.play(.copy)
    sound.play(.error)

    assertEqual(player.played, [NotificationCue.copy, NotificationCue.error],
                "SoundFeedback 把 cue 原样转给端口，顺序不丢")
    assertEqual(SoundFeedback.Cue.copy, NotificationCue.copy,
                "Cue 就是 Core 的 NotificationCue（反馈层不另抄一份 cue 表）")
    assertEqual(SoundFeedback.Cue.allCases.count, NotificationCue.allCases.count,
                "cue 全集与 Core 一致")

    // 无反馈装配的静默占位：调用不崩、不转发（面板在快照 / 设置窗场景用它）
    ClipboardFeedback.silent.sound.play(.delete)
    ClipboardFeedback.silent.haptics.tap(.selection)
    assertEqual(player.played.count, 2, "静默实现不落到真实播放器")
}

// MARK: - 触觉映射

@MainActor
private func testHapticKindMapping() {
    assertEqual(HapticFeedback.Kind.allCases, [.selection, .levelChange, .generic],
                "触发时机仍是三分（rawValue 进偏好 / 快照，不可改名）")
    for kind in HapticFeedback.Kind.allCases {
        assertEqual(kind.event, NotificationEvent.clipboardAction,
                    "\(kind.rawValue) 归属剪贴板动作事件（统一到设置页同一行）")
    }
}

// MARK: - 心跳现场

@MainActor
private func testWatchdogHeartbeatContext() {
    let start: UInt64 = 1_000_000_000
    assertEqual(MainThreadHeartbeat(now: start).tab, "-", "未打点过的分页是占位符")

    var heartbeat = MainThreadHeartbeat(now: start)
    heartbeat.beat(at: start, tab: "token", panelShown: true, indexingState: "indexing")
    let stall = heartbeat.takeStall(at: start + 3_000_000_000)

    assertNotNil(stall, "3 s 间隔判为停顿")
    assertEqual(stall?.gapSeconds, 3.0, "间隔按秒计（纳秒换算不走样）")
    assertEqual(stall?.tab, "token", "停顿现场带出分页")
    assertEqual(stall?.panelShown, true, "停顿现场带出展开态")
    assertEqual(stall?.indexingState, "indexing", "停顿现场带出索引状态")

    // 现场喂给 Core 的日志模板：看门狗与判据共用同一份文案口径
    let message = MainThreadWatchdogPolicy.message(gapSeconds: stall?.gapSeconds ?? 0,
                                                   tab: stall?.tab ?? "",
                                                   panelShown: stall?.panelShown ?? false,
                                                   indexingState: stall?.indexingState ?? "")
    assertEqual(message.contains("token"), true, "停顿日志带上分页上下文")
    assertEqual(message.contains("indexing"), true, "停顿日志带上索引状态")
}

@MainActor
private func testWatchdogReportsEachStallOnce() {
    var heartbeat = MainThreadHeartbeat(now: 0)
    heartbeat.beat(at: 0, tab: "network", panelShown: false, indexingState: "-")

    assertEqual(heartbeat.takeStall(at: 2_000_000_000) == nil, true,
                "刚好 2 s 不算停顿（严格大于阈值）")
    assertNotNil(heartbeat.takeStall(at: 3_000_000_000), "3 s 停顿上报")
    assertEqual(heartbeat.takeStall(at: 9_000_000_000) == nil, true,
                "同一次停顿只报一条（间隔继续增长不刷屏）")

    heartbeat.beat(at: 9_000_000_000)
    assertEqual(heartbeat.lastBeatNanoseconds, 9_000_000_000, "心跳时刻被记录")
    assertEqual(heartbeat.takeStall(at: 9_000_000_000) == nil, true, "心跳恢复即清位")
    assertEqual(heartbeat.takeStall(at: 12_000_000_000)?.gapSeconds, 3.0,
                "下一段停顿重新上报")
}

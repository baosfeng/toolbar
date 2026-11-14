import Foundation
import NetworkMonitorCore

// MARK: - 发现层心跳退避（UDP 公告空转治理）

func runDiscoveryHeartbeatPolicyTests() {
    print("🧪 Testing DiscoveryHeartbeatPolicy...")

    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var policy = DiscoveryHeartbeatPolicy()
    assertEqual(policy.shouldAnnounce(now: t0), true, "初始立即可发公告")

    // 阈值内不降频：偶发丢包仍按 5 秒心跳重试
    policy.noteAnnounce(success: false, now: t0)
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(5)), true,
                "连续失败 1 次仍按 5 秒心跳发送")
    policy.noteAnnounce(success: false, now: t0.addingTimeInterval(5))
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(10)), true,
                "连续失败 2 次仍按 5 秒心跳发送")

    // 第 3 次失败进入 30 秒退避
    policy.noteAnnounce(success: false, now: t0.addingTimeInterval(10))
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(15)), false,
                "第 3 次失败后退避到 30 秒")
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(39)), false,
                "退避窗口内不发（39 秒仍早于 40 秒）")
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(40)), true,
                "30 秒到点重试一次")

    // 重试仍失败则升到 60 秒档
    policy.noteAnnounce(success: false, now: t0.addingTimeInterval(40))
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(60)), false,
                "第 4 次失败退避到 60 秒")
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(100)), true,
                "60 秒到点重试一次")

    // 任意一次成功立刻解除退避
    policy.noteAnnounce(success: true, now: t0.addingTimeInterval(100))
    assertEqual(policy.nextAnnounceAt == nil, true, "发送成功后清空退避时刻")
    assertEqual(policy.failureStreak, 0, "发送成功后失败计数归零")
    assertEqual(policy.shouldAnnounce(now: t0.addingTimeInterval(105)), true,
                "成功后恢复每拍发送")
}

import Foundation
import NetworkMonitorCore

// MARK: - 性能热点修复：心跳退避策略 / 状态带签名

// MARK: - 传送页状态带签名（每秒重建治理）

func runTransferBandSignatureTests() {
    print("\n🧪 Testing TransferBandSignature...")

    let base = TransferBandSignature.make(statusText: "端口 53317",
                                          deviceCount: 2,
                                          sessionCount: 1,
                                          activeCount: 1,
                                          autoAcceptText: "04:59")
    let same = TransferBandSignature.make(statusText: "端口 53317",
                                          deviceCount: 2,
                                          sessionCount: 1,
                                          activeCount: 1,
                                          autoAcceptText: "04:59")
    assertEqual(base, same, "同一份数据签名必须相等（否则每秒都会重建状态带）")

    let cases: [(String, String)] = [
        (TransferBandSignature.make(statusText: "端口 53317", deviceCount: 3,
                                    sessionCount: 1, activeCount: 1, autoAcceptText: "04:59"), "设备数变化"),
        (TransferBandSignature.make(statusText: "端口 53317", deviceCount: 2,
                                    sessionCount: 2, activeCount: 1, autoAcceptText: "04:59"), "任务数变化"),
        (TransferBandSignature.make(statusText: "端口 53317", deviceCount: 2,
                                    sessionCount: 1, activeCount: 0, autoAcceptText: "04:59"), "进行中数量变化"),
        (TransferBandSignature.make(statusText: "端口 53317", deviceCount: 2,
                                    sessionCount: 1, activeCount: 1, autoAcceptText: "04:58"), "免配对倒计时变化（秒级必须刷新）"),
        (TransferBandSignature.make(statusText: "未启动", deviceCount: 2,
                                    sessionCount: 1, activeCount: 1, autoAcceptText: "04:59"), "发现状态变化"),
    ]
    for (signature, message) in cases {
        assertEqual(signature == base, false, message + " 必须改变签名")
    }

    // 分隔符不可伪造：字段拼接不能被值里的字符冒充成另一组取值
    let a = TransferBandSignature.make(statusText: "1", deviceCount: 2,
                                       sessionCount: 3, activeCount: 4, autoAcceptText: "5")
    let b = TransferBandSignature.make(statusText: "1", deviceCount: 2,
                                       sessionCount: 3, activeCount: 4, autoAcceptText: "5 ")
    assertEqual(a == b, false, "尾部空格也是内容变化")
}
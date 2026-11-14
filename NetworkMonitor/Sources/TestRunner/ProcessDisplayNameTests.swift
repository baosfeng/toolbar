import Foundation
import NetworkMonitorCore

// MARK: - 进程显示名映射（本应用那行显示「一览」，不做通配替换）

func runProcessDisplayNameTests() {
    print("\n🧪 Testing ProcessDisplayName...")

    let selfPID: Int32 = 4321
    let selfName = "NetworkMonitor"

    // 判据 1（主判据）：pid 相同 → 显示名；原始名是历史英文名也照换
    assertEqual(ProcessDisplayName.displayName(for: "NetworkMonitor", pid: selfPID,
                                               currentPID: selfPID,
                                               currentProcessName: selfName),
                AppIdentity.displayName, "pid 相同 → 显示「一览」")
    assertEqual(AppIdentity.displayName, "一览", "显示名真源是「一览」")

    // 可执行名已是中文：映射结果与原名相同，不做二次处理
    assertEqual(ProcessDisplayName.displayName(for: "一览", pid: selfPID,
                                               currentPID: selfPID,
                                               currentProcessName: "一览"),
                "一览", "原名已是显示名时原样返回")

    // 判据 2（无 pid 时退化）：名字精确相等才映射
    assertEqual(ProcessDisplayName.displayName(for: "NetworkMonitor", pid: 0,
                                               currentPID: selfPID,
                                               currentProcessName: selfName),
                "一览", "无 pid 时按本进程名精确匹配")
    assertEqual(ProcessDisplayName.displayName(for: "NetworkMonitor", pid: selfPID,
                                               currentPID: 0,
                                               currentProcessName: selfName),
                "一览", "本进程 pid 不可得时退化为名字判据")

    // 不误伤：近似串一律原样（白名单只认「确实是本进程」，不做通配替换）
    let nearMisses = ["NetworkMonitorX", "NetworkMonitor Helper", "NetworkMonitor2",
                      "XNetworkMonitor", "networkmonitor", "NETWORKMONITOR",
                      "Nettop", "一览表"]
    for raw in nearMisses {
        assertEqual(ProcessDisplayName.displayName(for: raw, pid: 0,
                                                   currentPID: selfPID,
                                                   currentProcessName: selfName),
                    raw, "近似名 \(raw)（无 pid）原样返回")
        assertEqual(ProcessDisplayName.displayName(for: raw, pid: 999,
                                                   currentPID: selfPID,
                                                   currentProcessName: selfName),
                    raw, "近似名 \(raw)（别人 pid）原样返回")
    }

    // 有 pid 时 pid 说了算：同名但 pid 不是本进程 → 原样（不按名字抢判）
    assertEqual(ProcessDisplayName.displayName(for: "NetworkMonitor", pid: 999,
                                               currentPID: selfPID,
                                               currentProcessName: selfName),
                "NetworkMonitor", "有 pid 时以 pid 为准，同名不同 pid 不映射")

    // 其它进程名（含长名 / 带空格）原样：映射不做长度处理，截断交给标签的 lineBreakMode
    let longName = "com.apple.WebKit.WebContent.Development.Worker"
    assertEqual(ProcessDisplayName.displayName(for: longName, pid: 77,
                                               currentPID: selfPID,
                                               currentProcessName: selfName),
                longName, "长进程名原样返回（截断由标签负责）")
    assertEqual(ProcessDisplayName.displayName(for: "Google Chrome Helper", pid: 78,
                                               currentPID: selfPID,
                                               currentProcessName: selfName),
                "Google Chrome Helper", "带空格的其它进程名原样返回")

    // 空名（采样失败）：原样返回，不伪造「一览」
    assertEqual(ProcessDisplayName.displayName(for: "", pid: selfPID,
                                               currentPID: selfPID,
                                               currentProcessName: selfName),
                "", "空进程名原样返回")

    // 本进程自证：真实 ProcessInfo 下 pid 判据命中
    let runtimePID = Int32(ProcessInfo.processInfo.processIdentifier)
    assertEqual(ProcessDisplayName.displayName(for: "NetworkMonitor", pid: runtimePID,
                                               currentPID: runtimePID,
                                               currentProcessName: ProcessInfo.processInfo.processName),
                AppIdentity.displayName, "TestRunner 本进程自证：pid 判据命中")
    assertEqual(ProcessDisplayName.displayName(for: "NetworkMonitor", pid: runtimePID - 1,
                                               currentPID: runtimePID,
                                               currentProcessName: "一个不存在的进程名"),
                "NetworkMonitor", "TestRunner 本进程自证：别的 pid 原样返回")

    print("✅ ProcessDisplayName 显示名映射 works")
}

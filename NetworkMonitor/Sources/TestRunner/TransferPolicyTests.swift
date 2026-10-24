import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · 接收放行策略与设置

// 测试函数放宽为 internal：由 TransferTests.swift 的 runTransferTests() 跨文件调度。

// MARK: - 接收放行策略与设置

/// 策略与设置测试入口
func runTransferPolicyTests() {
    testAcceptancePolicy()
    testReceiveDirectoryStats()
    testTransferPreferencesWindow()
    runPolicyServiceTests()
}

func testAcceptancePolicy() {
    print("\n🧪 Testing AcceptancePolicy 放行策略...")

    // 已配对优先
    let paired = AcceptancePolicy.decide(paired: true, windowActive: true,
                                         sizeThresholdMB: 10, totalBytes: 0)
    assertEqual(paired.accepted, true, "已配对直接放行")
    assertEqual(paired.reason, .paired, "原因：已配对")

    // 免配对窗口
    let window = AcceptancePolicy.decide(paired: false, windowActive: true,
                                         sizeThresholdMB: 0, totalBytes: 999_999_999)
    assertEqual(window.accepted, true, "窗口生效放行")
    assertEqual(window.reason, .autoAcceptWindow, "原因：免配对窗口")

    // 体积阈值：恰好等于阈值命中，超 1 字节不命中
    let oneMB: Int64 = 1024 * 1024
    let atLimit = AcceptancePolicy.decide(paired: false, windowActive: false,
                                          sizeThresholdMB: 1, totalBytes: oneMB)
    assertEqual(atLimit.accepted, true, "恰好 1 MB 命中阈值")
    assertEqual(atLimit.reason, .sizeThreshold, "原因：体积阈值")
    let overLimit = AcceptancePolicy.decide(paired: false, windowActive: false,
                                            sizeThresholdMB: 1, totalBytes: oneMB + 1)
    assertEqual(overLimit.accepted, false, "超阈值 1 字节不命中")
    assertEqual(overLimit.reason, .requiresPIN, "原因：需要 PIN")

    // 阈值 0 = 关闭（即使空文件也需要 PIN）
    let disabled = AcceptancePolicy.decide(paired: false, windowActive: false,
                                           sizeThresholdMB: 0, totalBytes: 0)
    assertEqual(disabled.accepted, false, "阈值关闭时 0 字节仍需 PIN")

    // 三条 OR：窗口关、阈值未命中、未配对 → PIN
    let fallback = AcceptancePolicy.decide(paired: false, windowActive: false,
                                           sizeThresholdMB: 5, totalBytes: Int64.max)
    assertEqual(fallback.accepted, false, "大文件回落 PIN")
}

func testReceiveDirectoryStats() {
    print("\n🧪 Testing ReceiveDirectoryStats 目录统计...")

    let summary = ReceiveDirectoryStats.summarize(sizes: [100, 200, -5])
    assertEqual(summary.fileCount, 3, "文件数含非法项")
    assertEqual(summary.totalBytes, 300, "负值按 0 计")
    assertEqual(ReceiveDirectoryStats.summarize(sizes: []), .empty, "空目录")
    assertEqual(ReceiveDirectoryStats.summarize(sizes: [0]), ReceiveDirectoryStats.Summary(fileCount: 1, totalBytes: 0),
                "0 字节文件计入个数")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("transfer-stats-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    assertEqual(ReceiveDirectoryStats.scan(directory: directory).fileCount, 0, "空目录扫描")
    try? Data(repeating: 0x41, count: 1024).write(to: directory.appendingPathComponent("a.bin"))
    try? Data(repeating: 0x42, count: 2048).write(to: directory.appendingPathComponent("b.bin"))
    try? FileManager.default.createDirectory(at: directory.appendingPathComponent("sub"),
                                             withIntermediateDirectories: true)
    let scanned = ReceiveDirectoryStats.scan(directory: directory)
    assertEqual(scanned.fileCount, 2, "只统计普通文件")
    assertEqual(scanned.totalBytes, 3072, "总字节汇总")
    assertEqual(ReceiveDirectoryStats.files(in: directory).count, 2, "文件列表不含子目录")
}

func testTransferPreferencesWindow() {
    print("\n🧪 Testing TransferPreferences 窗口与阈值...")

    let storage = InMemoryStorage()
    let preferences = TransferPreferences(storage: storage)
    assertEqual(preferences.autoAcceptMinutes, 10, "默认 10 分钟")
    assertEqual(preferences.sizeThresholdMB, 0, "默认关闭体积阈值")
    assertEqual(preferences.isWindowActive(), false, "默认无窗口")
    assertEqual(preferences.soundEnabled(.receive), true, "接收完成音默认开")
    assertEqual(preferences.soundEnabled(.send), true, "发送完成音默认开")
    assertEqual(preferences.soundEnabled(.failure), false, "失败音默认关")
    assertEqual(preferences.soundEnabled(.deviceAppeared), false, "新设备音默认关")

    let base = Date(timeIntervalSince1970: 1_700_000_000)
    preferences.autoAcceptEnabled = true
    preferences.autoAcceptMinutes = 5
    preferences.startWindow(now: base)
    assertEqual(preferences.isWindowActive(now: base.addingTimeInterval(299)), true, "窗口内 299s 有效")
    assertEqual(preferences.isWindowActive(now: base.addingTimeInterval(300)), false, "5 分钟边界到期")
    assertEqual(preferences.windowRemainingText(now: base.addingTimeInterval(60)), "04:00", "剩余时间文案")

    preferences.stopWindow()
    assertEqual(preferences.isWindowActive(now: base), false, "停止窗口后失效")

    preferences.startWindow(now: base)
    preferences.autoAcceptEnabled = false
    assertEqual(preferences.isWindowActive(now: base), false, "开关关闭时窗口不生效")

    // 时长非选项值收敛到 10
    preferences.autoAcceptMinutes = 7
    assertEqual(preferences.autoAcceptMinutes, 10, "非法时长收敛到 10 分钟")

    // 体积阈值
    preferences.sizeThresholdMB = 2
    assertEqual(preferences.allowsSize(2 * 1024 * 1024), true, "恰好 2 MB 命中")
    assertEqual(preferences.allowsSize(2 * 1024 * 1024 + 1), false, "超 1 字节不命中")
    preferences.sizeThresholdMB = 0
    assertEqual(preferences.allowsSize(0), false, "0 = 关闭")

    // 提示音开关持久化
    preferences.setSoundEnabled(true, for: .failure)
    assertEqual(preferences.soundEnabled(.failure), true, "失败音可开启")
    preferences.setSoundEnabled(false, for: .receive)
    assertEqual(TransferPreferences(storage: storage).soundEnabled(.receive), false, "开关持久化")
}

/// 服务层策略集成（直接调用 handleOffer，不起 HTTP）
func runPolicyServiceTests() {
    print("\n🧪 Testing 接收端放行策略（服务层）...")
    let semaphore = DispatchSemaphore(value: 0)
    let box = ScenarioFailureBox()
    Task.detached(priority: .userInitiated) {
        do {
            try await PolicyScenario.run()
        } catch {
            box.message = "\(error)"
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let message = box.message {
        print("❌ 接收端放行策略失败：\(message)")
        exit(1)
    }
    print("✅ 接收端放行策略 works")
}

private enum PolicyScenario {

    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = ConsoleLogger(minLevel: .error)
        let preferences = TransferPreferences(storage: InMemoryStorage())
        let registry = DeviceRegistry(callbackQueue: DispatchQueue(label: "transfer.test.policy"))
        let identity = LocalIdentity(deviceId: "mac-policy", alias: "策略机", port: 0, appVersion: "1.0.0")
        let configuration = TransferService.Configuration(receiveDirectory: directory,
                                                          appVersion: "1.0.0")
        let service = TransferService(identity: identity, registry: registry,
                                      configuration: configuration,
                                      pairing: PairingStore(storage: InMemoryStorage()),
                                      preferences: preferences,
                                      logger: logger)

        func makeOffer(sender: String, name: String, size: Int64) -> OfferRequest {
            OfferRequest(senderDeviceId: sender, senderAlias: sender,
                         files: [OfferFile(fileId: "f1", name: name, size: size,
                                           sha256: "sha-\(name)", mime: "application/octet-stream")])
        }

        // 1) 窗口内：直接 approved，不生成 PIN、不签发 pairingKey
        preferences.autoAcceptEnabled = true
        preferences.autoAcceptMinutes = 5
        preferences.startWindow()
        let windowResult = try await service.handleOffer(makeOffer(sender: "and-window", name: "w.txt", size: 1024),
                                                         pairKey: nil)
        guard case .success(let windowOutcome) = windowResult else {
            throw ScenarioError.failed("窗口内 offer 返回失败")
        }
        assertEqual(windowOutcome.result.state, .approved, "窗口内 offer 直接 approved")
        assertEqual(windowOutcome.result.pairingKey == nil, true, "免确认不签发 pairingKey")
        let pendingInWindow = await service.pendingOffers()
        assertEqual(pendingInWindow.isEmpty, true, "窗口内不产生待确认会话")

        // 2) 窗口过期：回到 pending + PIN
        preferences.startWindow(now: Date().addingTimeInterval(-3_600))
        let expiredResult = try await service.handleOffer(makeOffer(sender: "and-expired", name: "e.bin", size: 2048),
                                                         pairKey: nil)
        guard case .success(let expiredOutcome) = expiredResult else {
            throw ScenarioError.failed("过期后 offer 返回失败")
        }
        assertEqual(expiredOutcome.result.state, .pending, "窗口过期回到 pending")
        let pendingAfterExpiry = await service.pendingOffers()
        assertEqual(pendingAfterExpiry.isEmpty, false, "过期后产生待确认会话")
        assertEqual(pendingAfterExpiry.first?.pin.count, 4, "生成 4 位 PIN")

        // 3) 体积阈值：1 MB 内 approved，超出仍 pending
        preferences.autoAcceptEnabled = false
        preferences.stopWindow()
        preferences.sizeThresholdMB = 1
        let smallResult = try await service.handleOffer(makeOffer(sender: "and-small", name: "s.txt", size: 512 * 1024),
                                                       pairKey: nil)
        guard case .success(let smallOutcome) = smallResult else {
            throw ScenarioError.failed("阈值内 offer 返回失败")
        }
        assertEqual(smallOutcome.result.state, .approved, "阈值内 offer 直接 approved")
        let largeResult = try await service.handleOffer(makeOffer(sender: "and-large", name: "l.bin", size: 2 * 1024 * 1024),
                                                        pairKey: nil)
        guard case .success(let largeOutcome) = largeResult else {
            throw ScenarioError.failed("超阈值 offer 返回失败")
        }
        assertEqual(largeOutcome.result.state, .pending, "超阈值 offer 仍需 PIN")

        // 4) 清理接收目录
        try Data("recv".utf8).write(to: directory.appendingPathComponent("recv.txt"))
        let before = service.receiveDirectorySummary()
        assertEqual(before.fileCount, 1, "清理前 1 个文件")
        let cleared = await service.clearReceivedFiles()
        assertEqual(cleared.removedFiles, 1, "清理移除 1 个文件")
        assertEqual(service.receiveDirectorySummary().fileCount, 0, "清理后目录为空")
    }
}

import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · 断网重试续传（集成）

/// 集成测试入口 — 起真实接收端，模拟「第一次上传中断 → 重试确认偏移 → 续传成功」
func runTransferIntegrationTests() {
    print("\n🧪 Testing 断网重试续传（集成，真实 HTTP + 落盘）...")
    let semaphore = DispatchSemaphore(value: 0)
    let box = ScenarioFailureBox()
    Task.detached(priority: .userInitiated) {
        do {
            try await TransferRetryScenario.run()
        } catch {
            box.message = "\(error)"
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let message = box.message {
        print("❌ 断网重试续传失败：\(message)")
        exit(1)
    }
    print("✅ 断网重试续传 works")
}

/// 复现缺陷场景：服务端 `.part` 已有字节时，重试必须从服务端已收字节续传
private enum TransferRetryScenario {

    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 双方已配对：接收端保存发送端 key，发送端请求带 X-Pair-Key
        let storage = InMemoryStorage()
        let pairingKey = PairingStore.generateKey()
        PairingStore(storage: storage).save(key: pairingKey, for: "mac-sender")

        let logger = ConsoleLogger(minLevel: .error)
        let registry = DeviceRegistry(callbackQueue: DispatchQueue(label: "transfer.test.integration"))
        let identity = LocalIdentity(deviceId: "mac-recv", alias: "接收端", port: 0, appVersion: "1.0.0")
        let configuration = TransferService.Configuration(receiveDirectory: directory,
                                                          appVersion: "1.0.0")
        let receiver = TransferService(identity: identity, registry: registry,
                                       configuration: configuration,
                                       pairing: PairingStore(storage: storage),
                                       logger: logger)
        let port = try await receiver.start(portCandidates: [54_101, 54_102, 54_103],
                                            startDiscovery: false)
        do {
            try await exercise(receiverPort: Int(port), directory: directory,
                               pairingKey: pairingKey, logger: logger)
        } catch {
            await receiver.stop()
            throw error
        }
        await receiver.stop()
    }

    private static func exercise(receiverPort: Int, directory: URL,
                                 pairingKey: String, logger: LoggingService) async throws {
        let content = Data("hello world".utf8)  // 11 字节
        let sourceURL = directory.appendingPathComponent("source.bin")
        try content.write(to: sourceURL)
        let digest = try FileStreamReader.sha256(of: sourceURL)

        let client = TransferHTTPClient(logger: logger)
        let files = [OfferFile(fileId: "f1", name: "retry.txt",
                               size: Int64(content.count), sha256: digest, mime: "text/plain")]
        let firstOffer = OfferRequest(senderDeviceId: "mac-sender", senderAlias: "发送端", files: files)
        let (firstResult, _) = try await client.offer(firstOffer, ip: "127.0.0.1",
                                                      port: receiverPort, pairKey: pairingKey)
        guard firstResult.state == .approved else {
            throw ScenarioError.failed("首次 offer 未被批准（state=\(firstResult.state.rawValue)）")
        }
        assertEqual(firstResult.accepted.first?.offset, 0, "首次 offer 续传起点为 0")

        // 第一次上传：只发前 5 字节（模拟断网）
        let partialURL = directory.appendingPathComponent("partial.bin")
        try Data(content.prefix(5)).write(to: partialURL)
        do {
            _ = try await client.upload(fileURL: partialURL, fileId: "f1", offset: 0,
                                        sessionId: firstResult.sessionId, token: firstResult.token,
                                        ip: "127.0.0.1", port: receiverPort)
            throw ScenarioError.failed("不完整上传不应成功")
        } catch let error as TransferError {
            assertEqual(error.code, 4003, "不完整上传返回 4003")
        }
        let partURL = directory.appendingPathComponent("retry.txt.part")
        assertEqual(FileStreamReader.size(of: partURL) ?? -1, 5, "服务端保留 5 字节 .part")

        // 重试前：带 sessionId 重新 offer，向接收端确认已收字节
        let retryOffer = OfferRequest(senderDeviceId: "mac-sender", senderAlias: "发送端",
                                      files: files, sessionId: firstResult.sessionId)
        let (retryResult, _) = try await client.offer(retryOffer, ip: "127.0.0.1",
                                                      port: receiverPort, pairKey: pairingKey)
        guard retryResult.state == .approved else {
            throw ScenarioError.failed("重试 offer 未被批准（state=\(retryResult.state.rawValue)）")
        }
        guard retryResult.sessionId == firstResult.sessionId else {
            throw ScenarioError.failed("重试复用了错误会话：\(retryResult.sessionId)")
        }
        let serverOffset = retryResult.accepted.first?.offset ?? -1
        assertEqual(serverOffset, 5, "重试前确认服务端已收 5 字节")
        let resumedOffset = UploadPlanner.retryOffset(serverReported: serverOffset, fallback: 0)
        assertEqual(resumedOffset > 0, true, "第二次请求的 offset > 0（\(resumedOffset)）")

        // 第二次上传：用完整源文件 + 服务端已收偏移（客户端内部只发送剩余字节）
        let uploaded = try await client.upload(fileURL: sourceURL, fileId: "f1",
                                               offset: resumedOffset,
                                               sessionId: retryResult.sessionId,
                                               token: retryResult.token,
                                               ip: "127.0.0.1", port: receiverPort)
        assertEqual(uploaded.received, Int64(content.count), "续传后接收完整")
        assertEqual(uploaded.sha256, digest, "服务端摘要与源文件一致")

        let finalURL = directory.appendingPathComponent("retry.txt")
        let finalDigest = (try? FileStreamReader.sha256(of: finalURL)) ?? ""
        assertEqual(finalDigest, digest, "落盘文件 sha256 与源文件一致")
        assertEqual(FileManager.default.fileExists(atPath: partURL.path), false, "完成后 .part 已清理")
    }
}

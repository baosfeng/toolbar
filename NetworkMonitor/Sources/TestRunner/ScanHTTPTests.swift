import Foundation
import NetworkMonitorCore

// MARK: - 真实 HTTP 回环

func runScanHTTPIntegration() {
    print("\n🧪 Testing 扫码真实 HTTP 回环...")
    let semaphore = DispatchSemaphore(value: 0)
    let box = ScanFailureBox()
    Task.detached(priority: .userInitiated) {
        do {
            try await ScanHTTPScenario.run()
        } catch {
            box.message = "\(error)"
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let message = box.message {
        print("❌ 扫码真实 HTTP 回环失败：\(message)")
        exit(1)
    }
    print("✅ 扫码真实 HTTP 回环 works")
}

enum ScanHTTPScenario {

    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-http-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = ScanClock(Date())
        let store = ScanTokenStore(now: { clock.now })
        let registry = DeviceRegistry(callbackQueue: DispatchQueue(label: "scan.test.registry"))
        let identity = LocalIdentity(deviceId: "mac-scan", alias: "扫码接收端", port: 0,
                                     appVersion: "1.0.0")
        let configuration = TransferService.Configuration(receiveDirectory: directory,
                                                          appVersion: "1.0.0")
        let service = TransferService(identity: identity, registry: registry,
                                      configuration: configuration,
                                      scanTokens: store,
                                      logger: ConsoleLogger(minLevel: .error))
        let port = try await service.start(portCandidates: [54_201, 54_202, 54_203],
                                           startDiscovery: false)
        do {
            try await exercise(service: service, store: store, clock: clock,
                               port: Int(port), directory: directory)
        } catch {
            await service.stop()
            throw error
        }
        await service.stop()
    }

    private static func exercise(service: TransferService, store: ScanTokenStore,
                                 clock: ScanClock, port: Int, directory: URL) async throws {
        let token = store.issue().token

        // 1) 上传页 200 + HTML
        let pageURL = URL(string: "http://127.0.0.1:\(port)/scan?t=\(token)")!
        let (pageData, pageResponse) = try await URLSession.shared.data(from: pageURL)
        let pageStatus = (pageResponse as? HTTPURLResponse)?.statusCode ?? 0
        assertEqual(pageStatus, 200, "GET /scan 返回 200")
        let pageHTML = String(data: pageData, encoding: .utf8) ?? ""
        assertEqual(pageHTML.contains("局域网互传"), true, "上传页内容")

        // 2) 伪造 token → 4001
        let fakeURL = URL(string: "http://127.0.0.1:\(port)/scan?t=\(String(repeating: "f", count: 32))")!
        let (fakeData, fakeResponse) = try await URLSession.shared.data(from: fakeURL)
        let fakeStatus = (fakeResponse as? HTTPURLResponse)?.statusCode ?? 0
        assertEqual(fakeStatus, 400, "伪造 token 返回 HTTP 400")
        assertEqual(String(data: fakeData, encoding: .utf8)?.contains("\"code\":4001") ?? false,
                    true, "伪造 token 业务码 4001")

        // 3) 流式上传裸二进制 → 落盘
        let payload = Data("hello scan transfer".utf8)
        let result = try await upload(payload: payload, name: "test.txt", token: token, port: port)
        assertEqual(result.status, 200, "POST /scan/upload 返回 200")
        assertEqual(result.code, 0, "上传业务码 0")
        assertEqual(result.savedAs, "test.txt", "savedAs 为清洗后的文件名")
        let savedURL = directory.appendingPathComponent("test.txt")
        assertEqual(FileManager.default.fileExists(atPath: savedURL.path), true, "文件出现在收件目录")
        assertEqual(try Data(contentsOf: savedURL), payload, "文件内容与上传一致")
        assertEqual(FileManager.default.fileExists(atPath: savedURL.path + ".part"), false,
                    "不留 .part 临时文件")

        // 4) 重名复用 FileNameResolver
        let duplicate = try await upload(payload: Data("second".utf8), name: "test.txt",
                                         token: token, port: port)
        assertEqual(duplicate.savedAs, "test (1).txt", "重名自动去重")

        // 5) 文件名穿越被清洗
        let traversal = try await upload(payload: Data("evil".utf8), name: "../evil.txt",
                                         token: token, port: port)
        assertEqual(traversal.savedAs, "evil.txt", "路径穿越名被清洗为 basename")
        assertEqual(FileManager.default.fileExists(
            atPath: directory.deletingLastPathComponent().appendingPathComponent("evil.txt").path),
                    false, "文件没有写到上级目录")

        // 6) token 过期 → 4001
        clock.advance(601)
        let expired = try await upload(payload: Data("late".utf8), name: "late.txt",
                                       token: token, port: port)
        assertEqual(expired.status, 400, "过期 token 返回 HTTP 400")
        assertEqual(expired.code, 4001, "过期 token 业务码 4001")

        // 7) 超过 2 GiB 的 Content-Length 在进入业务层前被 413 挡下
        let freshToken = store.issue().token
        let oversized = try runNC(port: port, request: rawHeaders(
            token: freshToken, name: "huge.bin", contentLength: 2_147_483_649))
        assertEqual(oversized.contains("413"), true, "超限请求返回 413")
        assertEqual(oversized.contains("\"code\":4008"), true, "超限业务码 4008")

        // 8) 服务停止后 token 全部作废
        await service.stop()
        assertEqual(store.activeCount(), 0, "停止后 token 清空")
    }

    // MARK: - 上传辅助

    private struct UploadOutcome {
        var status: Int
        var code: Int
        var savedAs: String
    }

    private static func upload(payload: Data, name: String, token: String,
                               port: Int) async throws -> UploadOutcome {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let url = URL(string: "http://127.0.0.1:\(port)/scan/upload?t=\(token)&name=\(encodedName)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (json?["code"] as? NSNumber)?.intValue ?? -1
        let savedAs = ((json?["data"] as? [String: Any])?["savedAs"] as? String) ?? ""
        return UploadOutcome(status: status, code: code, savedAs: savedAs)
    }

    private static func rawHeaders(token: String, name: String, contentLength: Int64) -> String {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return "POST /scan/upload?t=\(token)&name=\(encodedName) HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Type: application/octet-stream\r\n"
            + "Content-Length: \(contentLength)\r\n"
            + "\r\n"
    }

    /// 用 `nc` 发原始请求头并读回响应（只发头，不发 body）
    private static func runNC(port: Int, request: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-w", "2", "127.0.0.1", String(port)]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()
        stdinPipe.fileHandleForWriting.write(Data(request.utf8))
        try? stdinPipe.fileHandleForWriting.close()
        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: output, encoding: .utf8) ?? ""
    }
}

// MARK: - 发现层 socket 清理

func testDiscoverySocketCleanup() {
    print("\n🧪 Testing 发现层 socket 清理...")

    let registry = DeviceRegistry(callbackQueue: DispatchQueue(label: "scan.test.discovery"))
    let identity = LocalIdentity(deviceId: "mac-discovery-test", alias: "发现层测试", port: 0,
                                 appVersion: "1.0.0")
    let discovery = UdpDiscoveryService(identity: identity,
                                        registry: registry,
                                        logger: ConsoleLogger(minLevel: .error))
    discovery.start()
    _ = waitForSocketCount(discovery, expected: 0, timeout: 2.0)

    discovery.stop()
    let released = waitForSocketCount(discovery, expected: 0, timeout: 2.0)
    assertEqual(released, true, "stop() 后收发 socket 全部关闭（含 receiveFD）")
    print("✅ 发现层 socket 清理 works")
}

/// 轮询等待 socket 数量（stop/start 走内部串行队列，需要等一拍）
func waitForSocketCount(_ discovery: UdpDiscoveryService,
                                expected: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if discovery.openSocketCount == expected { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return discovery.openSocketCount == expected
}

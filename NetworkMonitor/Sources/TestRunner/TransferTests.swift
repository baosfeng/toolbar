import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传测试组

/// 局域网互传测试入口 — 由 main.swift 顶层调用
///
/// 覆盖设计文档 §9 要求的纯逻辑用例：发现消息编解码与版本兼容、设备离线判定、
/// `/24` 扫描地址生成、状态机非法迁移、文件名去重、offset 校验。
func runTransferTests() {
    testDiscoveryMessageCodec()
    testDiscoveryVersionCompat()
    testDeviceLiveness()
    testSubnetScan()
    testDeviceRegistry()
    testHttpRequestParser()
    testHttpResponseWriter()
    testOfferRequestDecode()
    testFileNameResolver()
    testUploadPlanner()
    testFileStream()
    testSessionMachine()
    testPairingStore()
    testOfferSignature()
    testErrorCodesAndEnvelope()
    runTransferIntegrationTests()
    runTransferPolicyTests()
    print("✅ 局域网互传测试组完成")
}

// MARK: - 断言辅助

/// 断言抛出指定业务错误码的传输域异常
private func assertThrows(_ message: String, code expected: Int, _ body: () throws -> Void) {
    do {
        try body()
        print("❌ \(message) — 未抛出异常")
        exit(1)
    } catch let error as TransferError {
        assertEqual(error.code, expected, message)
    } catch {
        print("❌ \(message) — 抛出了非 TransferError：\(error)")
        exit(1)
    }
}

// MARK: - HTTP 请求解析

private func testHttpRequestParser() {
    print("\n🧪 Testing HttpRequestParser...")

    let upload = "PUT /api/v1/upload?session=abc&file=f1&offset=1024 HTTP/1.1\r\n"
        + "X-Transfer-Token: tok-123\r\n"
        + "Content-Length: 5\r\n"
        + "\r\n"
    guard let head = try? HttpRequestParser.parseHead(Data(upload.utf8)) else {
        print("❌ upload 请求头解析失败")
        exit(1)
    }
    assertEqual(head.method, "PUT", "方法 PUT")
    assertEqual(head.path, "/api/v1/upload", "路径不含查询串")
    assertEqual(head.query["session"], "abc", "查询参数 session")
    assertEqual(head.query["file"], "f1", "查询参数 file")
    assertEqual(head.query["offset"], "1024", "查询参数 offset")
    assertEqual(head.contentLength, 5, "Content-Length")
    assertEqual(head.header("x-transfer-token"), "tok-123", "头部大小写不敏感")

    // 查询参数百分号解码
    let encodedTarget = "/api/v1/info?name=%E7%85%A7%E7%89%87.jpg&q=a+b"
    guard let target = HttpRequestParser.parseTarget(encodedTarget) else {
        print("❌ 百分号解码解析失败")
        exit(1)
    }
    assertEqual(target.query["name"], "照片.jpg", "百分号解码")
    assertEqual(target.query["q"], "a b", "加号解码为空格")

    // GET 无 body
    let info = "GET /api/v1/info HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    let infoHead = try? HttpRequestParser.parseHead(Data(info.utf8))
    assertEqual(infoHead?.contentLength, 0, "GET 默认 Content-Length 为 0")
    assertEqual(infoHead?.method, "GET")

    // 非法请求
    assertThrows("不支持的方法", code: 4000) {
        _ = try HttpRequestParser.parseHead(Data("DELETE /api/v1/info HTTP/1.1\r\n\r\n".utf8))
    }
    assertThrows("请求行缺段", code: 4000) {
        _ = try HttpRequestParser.parseHead(Data("GET /api/v1/info\r\n\r\n".utf8))
    }
    assertThrows("Content-Length 非数字", code: 4000) {
        _ = try HttpRequestParser.parseHead(Data("POST /api/v1/offer HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8))
    }
    assertThrows("头部行缺冒号", code: 4000) {
        _ = try HttpRequestParser.parseHead(Data("GET /api/v1/info HTTP/1.1\r\nBadHeader\r\n\r\n".utf8))
    }

    // Range 解析
    assertEqual(HttpByteRange.parse("bytes=0-1023")?.start, 0, "Range 起点")
    assertEqual(HttpByteRange.parse("bytes=0-1023")?.end, 1023, "Range 终点")
    assertEqual(HttpByteRange.parse("bytes=512-")?.end, nil, "Range 开区间")
    assertEqual(HttpByteRange.parse("bytes=abc"), nil, "Range 非法返回 nil")
    assertEqual(HttpByteRange.parse("bytes=100-50"), nil, "Range 终点小于起点返回 nil")
    assertEqual(HttpByteRange.parse(nil), nil, "Range 缺失返回 nil")
}

// MARK: - HTTP 响应编码

private func testHttpResponseWriter() {
    print("\n🧪 Testing HttpResponseWriter...")

    let response = HttpResponseWriter.ok(OfferStatusResult(state: .pending))
    let bytes = HttpResponseWriter.encode(response)
    guard let text = String(data: bytes, encoding: .utf8) else {
        print("❌ 响应不是 UTF-8")
        exit(1)
    }
    assertEqual(text.hasPrefix("HTTP/1.1 200 OK\r\n"), true, "状态行")
    assertEqual(text.contains("Connection: close\r\n"), true, "每连接一请求")
    assertEqual(text.contains("Content-Type: application/json; charset=utf-8\r\n"), true, "JSON 内容类型")
    assertEqual(text.contains("Content-Length: \(response.body.count)\r\n"), true, "Content-Length 与 body 一致")
    assertEqual(text.contains(#""state":"pending""#), true, "响应体含 state")

    // 失败响应：HTTP 400 + 业务码
    let failure = HttpResponse.failure(.offsetMismatch(expected: 10, received: 5))
    let failureText = String(data: HttpResponseWriter.encode(failure), encoding: .utf8) ?? ""
    assertEqual(failureText.hasPrefix("HTTP/1.1 400 Bad Request\r\n"), true, "失败响应状态行")
    assertEqual(failureText.contains(#""code":4003"#), true, "失败响应业务码")
    assertEqual(failureText.contains(#""data":null"#), true, "失败响应 data 为 null")

    // 路由不存在 → 404
    let notFound = HttpResponse.failure(.routeNotFound("/x"))
    assertEqual(String(data: HttpResponseWriter.encode(notFound), encoding: .utf8)?.hasPrefix("HTTP/1.1 404") ?? false,
                true, "未知路由返回 404")
}

// MARK: - /offer 请求体

private func testOfferRequestDecode() {
    print("\n🧪 Testing OfferRequest 解码...")

    let json = """
    {"senderDeviceId":"mac-3b1e","senderAlias":"bsfeng 的 MacBook Pro",
     "files":[{"fileId":"f1","name":"照片.jpg","size":4123456,"sha256":"abc","mime":"image/jpeg"}]}
    """
    guard let request = try? OfferRequest.decode(Data(json.utf8)) else {
        print("❌ 合法清单解析失败")
        exit(1)
    }
    assertEqual(request.senderDeviceId, "mac-3b1e", "senderDeviceId")
    assertEqual(request.files.count, 1, "文件数")
    assertEqual(request.files[0].name, "照片.jpg", "文件名")
    assertEqual(request.files[0].size, 4_123_456, "文件大小")
    assertEqual(request.pin, nil, "未带 pin")

    assertThrows("非 JSON 清单", code: 4000) {
        _ = try OfferRequest.decode(Data("{}".utf8))
    }
    assertThrows("空 files", code: 4000) {
        _ = try OfferRequest.decode(Data(#"{"senderDeviceId":"a","senderAlias":"b","files":[]}"#.utf8))
    }
    assertThrows("缺少 senderDeviceId", code: 4000) {
        _ = try OfferRequest.decode(Data(#"{"senderAlias":"b","files":[{"fileId":"f1","name":"a","size":1,"sha256":"x","mime":"y"}]}"#.utf8))
    }
    assertThrows("size 为负", code: 4000) {
        _ = try OfferRequest.decode(Data(#"{"senderDeviceId":"a","senderAlias":"b","files":[{"fileId":"f1","name":"a","size":-1,"sha256":"x","mime":"y"}]}"#.utf8))
    }

    // 带 pin 的重新提交
    let withPin = """
    {"senderDeviceId":"mac-3b1e","senderAlias":"Mac","pin":"1234",
     "files":[{"fileId":"f1","name":"a.txt","size":1,"sha256":"x","mime":"text/plain"}]}
    """
    assertEqual((try? OfferRequest.decode(Data(withPin.utf8)))?.pin, "1234", "pin 字段")
}

// MARK: - 文件名去重

private func testFileNameResolver() {
    print("\n🧪 Testing FileNameResolver...")

    assertEqual(FileNameResolver.sanitize("照片.jpg"), "照片.jpg", "普通文件名保持不变")
    assertEqual(FileNameResolver.sanitize(""), "未命名", "空名回落")
    assertEqual(FileNameResolver.sanitize("   "), "未命名", "空白名回落")
    assertEqual(FileNameResolver.sanitize("../../etc/passwd"), "passwd", "路径穿越只取末段")
    assertEqual(FileNameResolver.sanitize("dir/照片.jpg"), "照片.jpg", "子目录只取文件名")
    assertEqual(FileNameResolver.sanitize("a\u{0}b.txt"), "ab.txt", "控制字符被剔除")

    assertEqual(FileNameResolver.uniqueName(for: "照片.jpg", in: []), "照片.jpg", "无冲突保留原名")
    assertEqual(FileNameResolver.uniqueName(for: "照片.jpg", in: ["照片.jpg"]), "照片 (1).jpg", "第一次冲突追加 (1)")
    assertEqual(FileNameResolver.uniqueName(for: "照片.jpg", in: ["照片.jpg", "照片 (1).jpg"]),
                "照片 (2).jpg", "第二次冲突追加 (2)")
    assertEqual(FileNameResolver.uniqueName(for: "README", in: ["README"]), "README (1)", "无扩展名直接追加")
    assertEqual(FileNameResolver.uniqueName(for: "a.tar.gz", in: ["a.tar.gz"]), "a.tar (1).gz", "只保留最后一段扩展名")
}

// MARK: - offset 校验

private func testUploadPlanner() {
    print("\n🧪 Testing UploadPlanner offset 校验...")

    // 正常：offset 等于已收字节
    do {
        try UploadPlanner.validateOffset(requested: 1024, received: 1024)
        print("✅ offset 相等通过")
    } catch {
        print("❌ offset 相等不应抛错：\(error)")
        exit(1)
    }
    // 从头重传允许
    do {
        try UploadPlanner.validateOffset(requested: 0, received: 1024)
        print("✅ offset=0 重传通过")
    } catch {
        print("❌ offset=0 不应抛错：\(error)")
        exit(1)
    }
    // 中间偏移错位 → 4003
    assertThrows("offset 小于已收", code: 4003) {
        try UploadPlanner.validateOffset(requested: 512, received: 1024)
    }
    assertThrows("offset 大于已收", code: 4003) {
        try UploadPlanner.validateOffset(requested: 2048, received: 1024)
    }
    assertThrows("offset 为负", code: 4003) {
        try UploadPlanner.validateOffset(requested: -1, received: 1024)
    }

    // 续传起点：0 / 落在范围内 / 超过预期大小
    assertEqual(UploadPlanner.resumableOffset(partSize: 0, expectedSize: 100), 0, "无 .part 从头开始")
    assertEqual(UploadPlanner.resumableOffset(partSize: 50, expectedSize: 100), 50, ".part 合法可续传")
    assertEqual(UploadPlanner.resumableOffset(partSize: 100, expectedSize: 100), 100, ".part 已完整返回全长")
    assertEqual(UploadPlanner.resumableOffset(partSize: 101, expectedSize: 100), 0, ".part 超预期大小从头开始")
    assertEqual(UploadPlanner.resumableOffset(partSize: -5, expectedSize: 100), 0, "负大小从头开始")

    // 重试偏移：接收端严格校验，必须用服务端已收字节（协议 §6）
    assertEqual(UploadPlanner.retryOffset(serverReported: 5, fallback: 0), 5, "重试取服务端已收字节")
    assertEqual(UploadPlanner.retryOffset(serverReported: 5, fallback: 8), 5, "服务端值优先于本地")
    assertEqual(UploadPlanner.retryOffset(serverReported: nil, fallback: 7), 7, "拿不到服务端值时回落本地")
    assertEqual(UploadPlanner.retryOffset(serverReported: -1, fallback: 7), 7, "服务端非法值回落本地")
    assertEqual(UploadPlanner.retryOffset(serverReported: nil, fallback: -3), 0, "本地非法值收敛为 0")
}

// MARK: - 流式落盘

private func testFileStream() {
    print("\n🧪 Testing FileStreamWriter / FileStreamReader...")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("transfer-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let finalURL = directory.appendingPathComponent("hello.txt")
    let expectedDigest = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"  // "hello world"

    // 第一次：写前 5 字节后中断
    do {
        let writer = try FileStreamWriter(finalURL: finalURL)
        try writer.write(Data("hello".utf8))
        assertEqual(writer.totalWritten, 5, "首次写入 5 字节")
        _ = try writer.finish()
    } catch {
        print("❌ 第一次写失败：\(error)")
        exit(1)
    }
    let partURL = UploadPlanner.partURL(for: finalURL)
    assertEqual(FileManager.default.fileExists(atPath: partURL.path), true, ".part 已生成")
    assertEqual(FileStreamReader.size(of: partURL), 5, ".part 大小为 5")

    // 第二次：从 offset 5 续传
    do {
        let writer = try FileStreamWriter(finalURL: finalURL, resumeOffset: 5)
        try writer.write(Data(" world".utf8))
        let digest = try writer.finish()
        assertEqual(digest, expectedDigest, "续传后整文件 sha256 正确")
        assertEqual(writer.totalWritten, 11, "续传后总长 11")
    } catch {
        print("❌ 续传失败：\(error)")
        exit(1)
    }

    // 摘要与独立读取实现一致
    assertEqual(try? FileStreamReader.sha256(of: partURL), expectedDigest, "FileStreamReader 摘要一致")
    assertEqual(FileStreamReader.size(of: partURL), 11, ".part 累计 11 字节")

    // 分块读取
    var collected = Data()
    try? FileStreamReader.readChunks(url: partURL, from: 0, chunkSize: 4) { collected.append($0) }
    assertEqual(String(data: collected, encoding: .utf8), "hello world", "分块读取内容正确")
    assertEqual(FileStreamReader.mimeType(for: URL(fileURLWithPath: "/tmp/a.jpg")), "image/jpeg", "MIME 推断")
    assertEqual(FileStreamReader.mimeType(for: URL(fileURLWithPath: "/tmp/a.unknown")),
                "application/octet-stream", "未知扩展名回落")

    // discard 清理 .part
    do {
        let writer = try FileStreamWriter(finalURL: directory.appendingPathComponent("tmp.bin"))
        try writer.write(Data([1, 2, 3]))
        writer.discard()
    } catch {
        print("❌ discard 测试失败：\(error)")
        exit(1)
    }
    assertEqual(FileManager.default.fileExists(
        atPath: UploadPlanner.partURL(for: directory.appendingPathComponent("tmp.bin")).path),
                false, "discard 删除 .part")
}

// MARK: - 发现消息编解码

private func testDiscoveryMessageCodec() {
    print("\n🧪 Testing DiscoveryMessage 编解码...")

    let original = DiscoveryMessage(type: .announce,
                                    deviceId: "and-7f3a9c",
                                    alias: "小米14",
                                    deviceType: "android",
                                    port: 53319,
                                    proto: "http",
                                    caps: ["send", "recv"],
                                    appVersion: "1.0.0",
                                    ts: 1_760_000_000)
    guard let encoded = original.encoded(), let decoded = DiscoveryMessage.decode(encoded) else {
        print("❌ DiscoveryMessage announce 编解码失败")
        exit(1)
    }
    // 每个协议字段一条断言
    assertEqual(decoded.v, 1, "字段 v")
    assertEqual(decoded.type, .announce, "字段 type")
    assertEqual(decoded.deviceId, "and-7f3a9c", "字段 deviceId")
    assertEqual(decoded.alias, "小米14", "字段 alias")
    assertEqual(decoded.deviceType, "android", "字段 deviceType")
    assertEqual(decoded.port, 53319, "字段 port")
    assertEqual(decoded.proto, "http", "字段 proto")
    assertEqual(decoded.caps, ["send", "recv"], "字段 caps")
    assertEqual(decoded.appVersion, "1.0.0", "字段 appVersion")
    assertEqual(decoded.ts, 1_760_000_000, "字段 ts")

    // discover 只带 v/type：编码时不输出空字段
    let discover = DiscoveryMessage.discover(ts: Date(timeIntervalSince1970: 0))
    guard let discoverData = discover.encoded(),
          let json = try? JSONSerialization.jsonObject(with: discoverData) as? [String: Any] else {
        print("❌ discover 编码失败")
        exit(1)
    }
    assertEqual(json.count, 2, "discover 仅含 v/type 两个字段")
    assertEqual(json["type"] as? String, "discover")
    if let roundTrip = DiscoveryMessage.decode(discoverData) {
        assertEqual(roundTrip.type, .discover, "discover 往返")
        assertEqual(roundTrip.deviceId, "", "discover 缺省字段为空")
    } else {
        print("❌ discover 往返失败")
        exit(1)
    }

    // 未知字段忽略（向前兼容）
    let extra = #"{"v":1,"type":"announce","deviceId":"and-1","port":53319,"futureField":{"a":1}}"#
    let extraMessage = DiscoveryMessage.decode(Data(extra.utf8))
    assertEqual(extraMessage?.deviceId, "and-1", "未知字段不影响解码")
    assertEqual(extraMessage?.port, 53319, "未知字段后仍能读到 port")

    // 非法报文
    assertEqual(DiscoveryMessage.decode(Data("not json".utf8)), nil, "非 JSON 返回 nil")
    assertEqual(DiscoveryMessage.decode(Data("[]".utf8)), nil, "非对象返回 nil")
    assertEqual(DiscoveryMessage.decode(Data(#"{"v":1}"#.utf8)), nil, "缺 type 返回 nil")
    assertEqual(DiscoveryMessage.decode(Data(#"{"type":"announce"}"#.utf8)), nil, "缺 v 返回 nil")
    assertEqual(DiscoveryMessage.decode(Data(#"{"v":1,"type":"bogus"}"#.utf8)), nil, "未知 type 返回 nil")
}

// MARK: - 版本兼容

private func testDiscoveryVersionCompat() {
    print("\n🧪 Testing DiscoveryMessage 版本兼容...")

    let v0 = #"{"v":0,"type":"announce","deviceId":"and-1","port":53319}"#
    assertEqual(DiscoveryMessage.decode(Data(v0.utf8)), nil, "v=0 不兼容")

    let v2 = #"{"v":2,"type":"announce","deviceId":"and-1","port":53319}"#
    assertEqual(DiscoveryMessage.decode(Data(v2.utf8)), nil, "v=2 高于当前版本不兼容")

    let v1 = #"{"v":1,"type":"offer","deviceId":"and-1","port":53319}"#
    let decoded = DiscoveryMessage.decode(Data(v1.utf8))
    assertNotNil(decoded, "v=1 兼容")
    assertEqual(decoded?.isSupportedVersion, true, "isSupportedVersion")

    // 身份消息判据：缺 deviceId 或端口非法不算可入库消息
    let noIdentity = DiscoveryMessage(type: .announce, port: 53319)
    assertEqual(noIdentity.carriesIdentity, false, "缺 deviceId 不算身份消息")
    let noPort = DiscoveryMessage(type: .announce, deviceId: "and-1")
    assertEqual(noPort.carriesIdentity, false, "缺 port 不算身份消息")
    let complete = DiscoveryMessage(type: .announce, deviceId: "and-1", port: 53319)
    assertEqual(complete.carriesIdentity, true, "完整消息可入库")
}

// MARK: - 离线判定

private func testDeviceLiveness() {
    print("\n🧪 Testing DeviceLiveness 离线判定...")

    let base = Date(timeIntervalSince1970: 1_760_000_000)
    assertEqual(DeviceLiveness.evaluate(now: base, lastSeenAt: base), .online, "0s 在线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(14.9), lastSeenAt: base), .online, "14.9s 仍在线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(15), lastSeenAt: base), .offline, "15s 转离线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(59.9), lastSeenAt: base), .offline, "59.9s 离线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(60), lastSeenAt: base), .removed, "60s 移除")
}

// MARK: - /24 扫描地址生成

private func testSubnetScan() {
    print("\n🧪 Testing SubnetScan /24 地址生成...")

    let hosts = SubnetScan.hosts(inSubnetOf: "192.168.1.23")
    assertEqual(hosts.count, 253, "排除网络/广播地址后 253 个")
    assertEqual(hosts.first, "192.168.1.1", "首个地址 .1")
    assertEqual(hosts.last, "192.168.1.254", "末个地址 .254")
    assertEqual(hosts.contains("192.168.1.23"), false, "排除本机地址")
    assertEqual(hosts.contains("192.168.1.0"), false, "排除网络地址")
    assertEqual(hosts.contains("192.168.1.255"), false, "排除广播地址")

    assertEqual(SubnetScan.hosts(inSubnetOf: "10.0.0.1").contains("10.0.0.1"), false, "10.x 段排除本机")
    assertEqual(SubnetScan.hosts(inSubnetOf: "192.168.1").isEmpty, true, "段数不足返回空")
    assertEqual(SubnetScan.hosts(inSubnetOf: "192.168.1.256").isEmpty, true, "越界段返回空")
    assertEqual(SubnetScan.hosts(inSubnetOf: "").isEmpty, true, "空串返回空")
    assertEqual(SubnetScan.hosts(inSubnetOf: "::1").isEmpty, true, "IPv6 返回空")

    let batches = SubnetScan.batches(hosts)
    assertEqual(batches.map(\.count), [128, 125], "按 128 并发切批")
    assertEqual(SubnetScan.batches([], size: 128).isEmpty, true, "空地址不切批")
}

// MARK: - 设备表

private func testDeviceRegistry() {
    print("\n🧪 Testing DeviceRegistry 设备表...")

    let registry = DeviceRegistry(callbackQueue: DispatchQueue(label: "transfer.test.registry"))
    let base = Date(timeIntervalSince1970: 1_760_000_000)
    let announce = DiscoveryMessage(type: .announce, deviceId: "and-1", alias: "小米14",
                                    deviceType: "android", port: 53319, appVersion: "1.0.0")

    let stored = registry.upsert(message: announce, ip: "192.168.1.8", now: base)
    assertNotNil(stored, "announce 可入库")
    assertEqual(registry.count, 1, "设备数 1")
    assertEqual(registry.snapshot().first?.ip, "192.168.1.8", "记录来源 IP")
    assertEqual(registry.snapshot().first?.isOnline, true, "默认在线")

    // discover 缺身份字段：不写入设备表
    let ignored = registry.upsert(message: DiscoveryMessage.discover(), ip: "192.168.1.9", now: base)
    assertEqual(ignored, nil, "discover 不入库")
    assertEqual(registry.count, 1, "设备数不变")

    // 同一设备再次公告：更新 IP 与端口，不新增条目
    let moved = DiscoveryMessage(type: .announce, deviceId: "and-1", alias: "小米14",
                                 deviceType: "android", port: 53320)
    registry.upsert(message: moved, ip: "192.168.1.18", now: base.addingTimeInterval(5))
    assertEqual(registry.count, 1, "同设备只保留一条")
    assertEqual(registry.snapshot().first?.port, 53320, "端口随公告更新")
    assertEqual(registry.snapshot().first?.ip, "192.168.1.18", "IP 随公告更新")

    // 在线优先排序
    registry.upsert(message: DiscoveryMessage(type: .announce, deviceId: "and-2", alias: "AAA 手机",
                                              deviceType: "android", port: 53319),
                    ip: "192.168.1.9", now: base.addingTimeInterval(12))
    _ = registry.applyLiveness(now: base.addingTimeInterval(20))
    let ordered = registry.snapshot()
    assertEqual(ordered.count, 2, "两台设备")
    assertEqual(ordered.first?.deviceId, "and-2", "在线设备排在前面")
    assertEqual(ordered.first?.isOnline, true, "在线设备标记在线")

    // 15s 离线、60s 移除
    assertEqual(registry.applyLiveness(now: base.addingTimeInterval(30)), true, "首次推进存活有变化")
    assertEqual(registry.applyLiveness(now: base.addingTimeInterval(31)), false, "状态未变时不重复通知")

    // 配对标记
    registry.setPaired(true, deviceId: "and-1")
    assertEqual(registry.device(deviceId: "and-1")?.isPaired, true, "配对标记写入")

    registry.remove(deviceId: "and-2")
    assertEqual(registry.count, 1, "移除生效")

    // baseURL 供发现层异常时手动探测
    let device = registry.device(deviceId: "and-1")
    assertEqual(device?.baseURL?.absoluteString, "http://192.168.1.18:53320/api/v1", "baseURL 拼接")
}

// MARK: - 状态机

private func testSessionMachine() {
    print("\n🧪 Testing TransferSessionMachine 迁移...")

    let legal: [(TransferState, TransferState)] = [
        (.pending, .offering), (.pending, .failed), (.pending, .cancelled),
        (.offering, .awaitingConfirm), (.offering, .transferring),
        (.offering, .failed), (.offering, .cancelled),
        (.awaitingConfirm, .transferring), (.awaitingConfirm, .failed), (.awaitingConfirm, .cancelled),
        (.transferring, .verifying), (.transferring, .failed), (.transferring, .cancelled),
        (.verifying, .completed), (.verifying, .failed), (.verifying, .cancelled),
    ]
    var illegalCount = 0
    for pair in TransferSessionMachine.allTransitions {
        let expected = legal.contains { $0.0 == pair.from && $0.1 == pair.to }
        assertEqual(TransferSessionMachine.canTransition(from: pair.from, to: pair.to), expected,
                    "\(pair.from.rawValue) → \(pair.to.rawValue)")
        if !expected { illegalCount += 1 }
    }
    assertEqual(illegalCount, 64 - legal.count, "穷举 64 种状态对有 \(64 - legal.count) 种非法")

    // 非法迁移抛 4000（illegalTransition），且不改变状态
    assertThrows("completed → transferring", code: 4000) {
        _ = try TransferSessionMachine.transition(.completed, to: .transferring)
    }
    assertThrows("pending → completed", code: 4000) {
        _ = try TransferSessionMachine.transition(.pending, to: .completed)
    }
    assertThrows("failed → completed", code: 4000) {
        _ = try TransferSessionMachine.transition(.failed, to: .completed)
    }
    assertEqual(TransferSessionMachine.allowedTargets(from: .completed).isEmpty, true, "终结态无出口")

    // 会话推进器：正常链路
    let file = TransferFile(fileId: "f1", name: "a.bin", size: 100, sha256: "x")
    var runner = TransferSessionRunner(session: TransferSession(
        id: "s1", direction: .send, peerDeviceId: "and-1", token: "t",
        files: [file], state: .pending, createdAt: Date(timeIntervalSince1970: 0)))
    try? runner.advance(to: .offering)
    try? runner.advance(to: .transferring)
    try? runner.advance(to: .verifying)
    try? runner.advance(to: .completed)
    assertEqual(runner.session.state, .completed, "状态机可推进到完成")
    runner.updateFileProgress(fileId: "f1", transferred: 150)
    assertEqual(runner.session.files[0].transferred, 100, "进度按文件大小收敛")
    runner.updateFileProgress(fileId: "f1", transferred: -5)
    assertEqual(runner.session.files[0].transferred, 0, "负进度收敛为 0")
    assertEqual(runner.allFilesCompleted, false, "归零后未完成")

    // 非法迁移不改状态
    var pendingRunner = TransferSessionRunner(session: TransferSession(
        id: "s2", direction: .recv, peerDeviceId: "and-1", token: "t",
        files: [file], state: .pending, createdAt: Date()))
    do {
        try pendingRunner.advance(to: .completed)
        print("❌ 非法迁移未抛错")
        exit(1)
    } catch let error as TransferError {
        assertEqual(error.code, 4000, "非法迁移错误码")
        assertEqual(pendingRunner.session.state, .pending, "非法迁移后状态不变")
    } catch {
        print("❌ 抛出了非 TransferError")
        exit(1)
    }
}

// MARK: - 配对记忆

/// 内存键值存储（隔离 UserDefaults，不污染本机偏好）
private final class InMemoryStorage: KeyValueStorage, @unchecked Sendable {
    private var values: [String: Any] = [:]

    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func string(forKey key: String) -> String? { values[key] as? String }
    func object(forKey key: String) -> Any? { values[key] }
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }

    func set(_ value: Int, forKey key: String) { values[key] = value }
    func set(_ value: Double, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private func testPairingStore() {
    print("\n🧪 Testing PairingStore 配对记忆...")

    let storage = InMemoryStorage()
    let store = PairingStore(storage: storage)
    assertEqual(store.isPaired("and-1"), false, "初始未配对")

    let key = PairingStore.generateKey()
    assertEqual(key.count, 64, "配对 key 为 64 位 hex")
    assertEqual(key.allSatisfy { $0.isHexDigit }, true, "配对 key 仅含 hex 字符")

    store.save(key: key, for: "and-1")
    assertEqual(store.key(for: "and-1"), key, "保存后可读")
    assertEqual(store.isPaired("and-1"), true, "配对标记")

    // 持久化：新实例读同一份存储
    let second = PairingStore(storage: storage)
    assertEqual(second.key(for: "and-1"), key, "跨实例持久化")

    assertEqual(store.pairedDeviceIds(), ["and-1"], "设备 id 列表")

    store.remove(deviceId: "and-1")
    assertEqual(store.key(for: "and-1") == nil, true, "移除后回到未配对")
    assertEqual(PairingStore(storage: storage).key(for: "and-1") == nil, true, "移除已持久化")

    // PIN 格式
    let pin = PairingStore.generatePIN()
    assertEqual(pin.count, 4, "PIN 4 位")
    assertEqual(PairingStore.isValidPIN(pin), true, "生成的 PIN 合法")
    assertEqual(PairingStore.isValidPIN("1234"), true, "1234 合法")
    assertEqual(PairingStore.isValidPIN("123"), false, "3 位非法")
    assertEqual(PairingStore.isValidPIN("12a4"), false, "含字母非法")
}

// MARK: - offer 签名

private func testOfferSignature() {
    print("\n🧪 Testing offer 清单签名...")

    let files = [
        OfferFile(fileId: "f1", name: "照片.jpg", size: 10, sha256: "BBB"),
        OfferFile(fileId: "f2", name: "文档.pdf", size: 20, sha256: "AAA"),
    ]
    let request = OfferRequest(senderDeviceId: "and-1", senderAlias: "小米14", files: files)
    assertEqual(TransferService.offerSignature(request), "and-1|aaa|bbb",
                "签名 = 设备 id + 排序后的 sha256 集合")

    // 重命名 / 顺序变化不影响复用判定
    let renamed = OfferRequest(senderDeviceId: "and-1", senderAlias: "小米14",
                               files: [OfferFile(fileId: "f9", name: "重命名.jpg", size: 10, sha256: "AAA")])
    let renamedAgain = OfferRequest(senderDeviceId: "and-1", senderAlias: "小米14",
                                    files: [OfferFile(fileId: "f9", name: "重命名.jpg", size: 10, sha256: "aaa")])
    assertEqual(TransferService.offerSignature(renamed), TransferService.offerSignature(renamedAgain),
                "sha256 大小写不敏感")

    let otherSender = OfferRequest(senderDeviceId: "and-2", senderAlias: "x", files: files)
    assertEqual(TransferService.offerSignature(otherSender).hasPrefix("and-2|"), true,
                "不同设备签名不同")

    // 重提 PIN 请求体字段
    let pinJSON = """
    {"senderDeviceId":"and-1","senderAlias":"小米14","sessionId":"s-1","pin":"1234",
     "files":[{"fileId":"f1","name":"a.jpg","size":10,"sha256":"BBB","mime":"image/jpeg"}]}
    """
    let decoded = try? OfferRequest.decode(Data(pinJSON.utf8))
    assertEqual(decoded?.sessionId, "s-1", "sessionId 字段")
    assertEqual(decoded?.pin, "1234", "pin 字段")
}

// MARK: - 错误码与信封

private func testErrorCodesAndEnvelope() {
    print("\n🧪 Testing 错误码与响应信封...")

    assertEqual(TransferError.tokenMismatch.code, 4001, "4001 token")
    assertEqual(TransferError.sessionNotFound.code, 4002, "4002 会话")
    assertEqual(TransferError.offsetMismatch(expected: 1, received: 2).code, 4003, "4003 offset")
    assertEqual(TransferError.diskFull(required: 2, available: 1).code, 4004, "4004 磁盘")
    assertEqual(TransferError.checksumMismatch(expected: "a", actual: "b").code, 4005, "4005 校验")
    assertEqual(TransferError.denied.code, 4006, "4006 拒绝")
    assertEqual(TransferError.confirmTimeout.code, 4007, "4007 超时")
    assertEqual(TransferError.tokenMismatch.httpStatus, 400, "token 错误映射 400")
    assertEqual(TransferError.routeNotFound("/x").httpStatus, 404, "未知路由 404")
    assertEqual(TransferError.ioFailed("x").httpStatus, 500, "IO 错误 500")

    // pairingKey 只在存在时出现在 data 中（可选字段）
    let withKey = OfferResult(sessionId: "s", token: "t", state: .approved,
                              accepted: [], pairingKey: "abcdef")
    let withKeyText = String(data: ApiResponse<OfferResult>.success(withKey).encoded(), encoding: .utf8) ?? ""
    assertEqual(withKeyText.contains("\"pairingKey\":\"abcdef\""), true, "新配对返回 pairingKey")

    let withoutKey = OfferResult(sessionId: "s", token: "t", state: .approved, accepted: [])
    let withoutKeyText = String(data: ApiResponse<OfferResult>.success(withoutKey).encoded(), encoding: .utf8) ?? ""
    assertEqual(withoutKeyText.contains("pairingKey"), false, "已配对不返回 pairingKey")

    // 解码既有端响应（pending 分支 accepted 为空）
    let pendingJSON = #"{"code":0,"message":"ok","data":{"sessionId":"s","token":"t","state":"pending","accepted":[]}}"#
    let envelope = try? JSONDecoder().decode(ApiResponse<OfferResult>.self, from: Data(pendingJSON.utf8))
    assertEqual(envelope?.data?.state, .pending, "pending 响应可解码")
    assertEqual(envelope?.data?.pairingKey == nil, true, "pending 无 pairingKey")

    // 失败信封 data 为 null
    let failureText = String(data: ApiResponse<EmptyPayload>.failure(.denied).encoded(), encoding: .utf8) ?? ""
    assertEqual(failureText.contains(#""code":4006"#), true, "失败信封业务码")
    assertEqual(failureText.contains(#""data":null"#), true, "失败信封 data 为 null")
}

// MARK: - 断网重试续传（集成）

/// 后台场景失败信息（跨线程传递）
private final class ScenarioFailureBox: @unchecked Sendable {
    var message: String?
}

private enum ScenarioError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

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

// MARK: - 接收放行策略与设置

/// 策略与设置测试入口
func runTransferPolicyTests() {
    testAcceptancePolicy()
    testReceiveDirectoryStats()
    testTransferPreferencesWindow()
    runPolicyServiceTests()
}

private func testAcceptancePolicy() {
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

private func testReceiveDirectoryStats() {
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

private func testTransferPreferencesWindow() {
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
private func runPolicyServiceTests() {
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

import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · HTTP 请求 / 响应与文件名规划

// 测试函数放宽为 internal：由 TransferTests.swift 的 runTransferTests() 跨文件调度。

// MARK: - HTTP 请求解析

func testHttpRequestParser() {
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

func testHttpResponseWriter() {
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

func testOfferRequestDecode() {
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

func testFileNameResolver() {
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

func testUploadPlanner() {
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

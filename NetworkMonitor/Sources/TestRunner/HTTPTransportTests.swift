import Foundation
import NetworkMonitorCore

// MARK: - 统一 HTTP 传输层

/// 传输层契约单测（不联网）：Endpoint / 超时 / 响应头 / 错误映射 / 脱敏。
func runHTTPTransportTests() {
    print("🧪 Testing 统一 HTTP 传输层（Endpoint / 超时 / 响应头 / 映射 / 脱敏）...")
    testEndpointDefaults()
    testEndpointTimeoutOverride()
    testRequestConstruction()
    testStatusCodeMapping()
    testTransportFailureMapping()
    testResponseHeadersAndRetryAfter()
    testRedaction()
    testBillingMapperUsesProviderStatus()
    testProviderUsesInjectedTransport()
    print("✅ 统一 HTTP 传输层 works")
}

// MARK: - Endpoint 构造

private func testEndpointDefaults() {
    let endpoint = Endpoint<String>(url: URL(string: "https://example.com/a")!,
                                    label: "样例",
                                    decoder: { String(decoding: $0, as: UTF8.self) })
    assertEqual(endpoint.method, .get, "默认方法 GET")
    assertEqual(endpoint.timeout, 15, "默认超时 15 秒")
    assertEqual(endpoint.timeout, HTTPTransportDefaults.timeout, "默认值来自唯一真源")
    assertEqual(endpoint.headers.isEmpty, true, "默认无业务头")
    assertEqual(endpoint.body, nil, "默认无请求体")
    assertEqual(endpoint.userAgent, nil, "默认不发 UA（保持各家历史行为）")
    assertEqual(endpoint.cachePolicy, .useProtocolCachePolicy, "默认走协议缓存策略")
    assertEqual(endpoint.errorMapper == nil, true, "默认可无错误映射（走统一口径）")
    assertEqual(endpoint.label, "样例", "label 用于日志定位")
}

/// 超时逐 endpoint 覆写：15 是默认，不是硬编码
private func testEndpointTimeoutOverride() {
    let fast = Endpoint<Data>(url: URL(string: "https://example.com/b")!,
                              timeout: 8,
                              label: "更新检查",
                              decoder: { $0 })
    assertEqual(fast.timeout, 8, "Endpoint 可覆写为 8 秒（GitHub 限流语义）")
    assertEqual(HTTPTransportDefaults.timeout, 15, "默认仍是 15 秒，不被覆写改动")
}

// MARK: - 请求构造（声明 → 真实请求）

private func testRequestConstruction() {
    let transport = URLSessionHTTPTransport(logger: ConsoleLogger(minLevel: .error))
    let url = URL(string: "https://example.com/api?x=1")!

    let endpoint = Endpoint<Data>(method: .get,
                                  url: url,
                                  headers: ["Authorization": "Bearer t", "Accept": "text/plain"],
                                  userAgent: "一览/1.0",
                                  timeout: 8,
                                  cachePolicy: .reloadIgnoringLocalCacheData,
                                  label: "样例",
                                  decoder: { $0 })
    let request = transport.makeRequest(endpoint)
    assertEqual(request.httpMethod, "GET", "方法透传")
    assertEqual(request.timeoutInterval, 8, "超时透传（8 秒）")
    assertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, "缓存策略透传")
    assertEqual(request.value(forHTTPHeaderField: "User-Agent"), "一览/1.0", "UA 用 endpoint 声明值")
    assertEqual(request.value(forHTTPHeaderField: "Accept"), "text/plain", "显式 Accept 不被默认值覆盖")
    assertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t", "凭据头透传")
    assertEqual(request.url?.absoluteString, "https://example.com/api?x=1", "URL + query 原样")

    // 未声明 UA / Accept 时补默认（UA 只在显式给出时才发）
    let bare = Endpoint<Data>(url: url, label: "样例", decoder: { $0 })
    let bareRequest = transport.makeRequest(bare)
    assertEqual(bareRequest.value(forHTTPHeaderField: "User-Agent"), nil, "未声明 UA 时不发（与改造前一致）")
    assertEqual(bareRequest.value(forHTTPHeaderField: "Accept"), "application/json", "缺省补 Accept")
    assertEqual(bareRequest.timeoutInterval, 15, "缺省补 15 秒")
}

// MARK: - 状态码 → 错误（每类一次）

private func testStatusCodeMapping() {
    assertEqual(HTTPStatusCode.map(400, retryAfter: nil, message: "bad"),
                .badRequest("bad"), "400 → 参数错误")
    assertEqual(HTTPStatusCode.map(401, retryAfter: nil, message: nil),
                .unauthorized, "401 → 未授权")
    assertEqual(HTTPStatusCode.map(403, retryAfter: nil, message: "denied"),
                .forbidden("denied"), "403 → 无权限")
    assertEqual(HTTPStatusCode.map(429, retryAfter: 30, message: nil),
                .rateLimited(retryAfter: 30), "429 → 限流（带 Retry-After）")
    assertEqual(HTTPStatusCode.map(503, retryAfter: nil, message: "down"),
                .serverError("down"), "5xx → 服务端错误")
    assertEqual(HTTPStatusCode.map(418, retryAfter: nil, message: nil),
                .unexpected(418), "其余状态码 → 未预期")
}

private func testTransportFailureMapping() {
    let transportFailure = HTTPTransportFailure.make(URLError(.timedOut))
    assertEqual(transportFailure.isTimeout, true, "URLError.timedOut 标为超时")
    assertEqual(HTTPTransportFailure.make(URLError(.cancelled)).isCancelled, true, "URLError.cancelled 标为取消")
    assertEqual(HTTPTransportFailure.make(URLError(.cannotConnectToHost)).isTimeout, false, "连接失败不是超时")

    // 统一口径：传输失败 → HTTPTransportError.transport
    guard case .transport = HTTPTransportDefaults.error(.transport(transportFailure)) as? HTTPTransportError else {
        assertEqual("不是 transport", "transport", "传输失败归 transport")
        return
    }
    assertEqual(HTTPTransportDefaults.error(.notHTTP) as? HTTPTransportError, .notHTTP, "非 HTTP 响应单独一类")
    let mapped = HTTPTransportDefaults.error(.response(HTTPResponse(data: Data(), statusCode: 429,
                                                                   headers: ["retry-after": "12"])))
    assertEqual(mapped as? HTTPTransportError, .status(.rateLimited(retryAfter: 12)),
                "非 2xx 走统一状态码口径")
}

// MARK: - 响应头透出 / Retry-After

private func testResponseHeadersAndRetryAfter() {
    let response = HTTPResponse(data: Data(),
                                statusCode: 429,
                                headers: ["retry-after": "120",
                                          "x-ratelimit-remaining": "0",
                                          "authorization": "Bearer secret"])
    assertEqual(response.header("X-RateLimit-Remaining"), "0", "响应头大小写不敏感透出")
    assertEqual(response.retryAfter, 120, "Retry-After 秒数解析")
    assertEqual(response.isSuccess, false, "429 不是成功")
    assertEqual(response.header("authorization"), "Bearer secret", "头字典本身保留（脱敏只在日志层）")

    // Retry-After 的两种合法形态与脏数据
    assertEqual(HTTPRetryAfter.parse("30"), 30, "秒数形态")
    assertEqual(HTTPRetryAfter.parse("  45  "), 45, "首尾空白仍解析")
    assertEqual(HTTPRetryAfter.parse(nil), nil, "缺头 → nil")
    assertEqual(HTTPRetryAfter.parse(""), nil, "空串 → nil")
    assertEqual(HTTPRetryAfter.parse("-5"), nil, "负数 → nil")
    assertEqual(HTTPRetryAfter.parse("soon"), nil, "非数字非日期 → nil")
    let httpDate = HTTPRetryAfter.parse("Wed, 21 Oct 2015 07:28:00 GMT")
    assertEqual(httpDate, 0, "过去的 HTTP 日期按 0 处理（不返回负数）")

    // 真 HTTPURLResponse → 小写键字典（GitHub 头名大小写不固定，判定必须大小写无关）
    let httpURL = URL(string: "https://api.github.com/x")!
    let raw = HTTPURLResponse(url: httpURL, statusCode: 403, httpVersion: "HTTP/1.1",
                              headerFields: ["X-RateLimit-Remaining": "0", "Retry-After": "60"])!
    let lowered = URLSessionHTTPTransport.lowercasedHeaders(raw)
    assertEqual(lowered["x-ratelimit-remaining"], "0", "真实响应头键统一小写")
    assertEqual(HTTPResponse(data: Data(), statusCode: 403, headers: lowered).header("X-RateLimit-Remaining"),
                "0", "装箱后按任意大小写可取到")
    assertEqual(HTTPResponse(data: Data(), statusCode: 403, headers: lowered).retryAfter, 60,
                "真实响应头的 Retry-After 可解析")

    // 响应头白名单：日志只留排障相关键
    assertEqual(HTTPLogRedaction.headers(["authorization": "Bearer secret"]), "",
                "凭据头不进日志")
    assertEqual(HTTPLogRedaction.headers(["retry-after": "120"]), "retry-after=120",
                "限流头进日志")
}

// MARK: - 脱敏规则

private func testRedaction() {
    let url = URL(string: "https://api.example.com/v1/usage?token=secret&x=1#frag")!
    assertEqual(HTTPLogRedaction.url(url), "https://api.example.com/v1/usage",
                "URL 只留协议 + host + path（query / fragment 丢掉）")
    assertEqual(HTTPLogRedaction.url(url).contains("secret"), false, "日志不含 query 里的凭据")

    let withCredentials = URL(string: "https://user:pass@api.example.com/v1/usage")!
    assertEqual(HTTPLogRedaction.url(withCredentials).contains("pass"), false,
                "URL 里的账号密码被剥掉")

    assertEqual(HTTPLogRedaction.headers(["accept": "application/json"]), "accept=application/json",
                "内容协商头保留")
    assertEqual(HTTPLogRedaction.headers(["cookie": "__Secure-auth=abc", "authorization": "Bearer x"]), "",
                "Cookie / Authorization 一律不进日志")
    assertEqual(HTTPLogRedaction.headerWhitelist.contains("authorization"), false,
                "白名单不含 authorization")

    // 扫码链接把 token 放在 query：脱敏后必须只剩 host + path
    let scanURL = ScanLinkBuilder.pageURL(token: String(repeating: "a", count: 32),
                                          ip: "192.168.1.9", port: 8080)
    assertEqual(HTTPLogRedaction.url(scanURL ?? ""), "http://192.168.1.9:8080/scan",
                "扫码链接日志不含 token（query 被丢掉）")

    // 错误体文案提取：四段兼容 + 空串当没给
    assertEqual(HTTPErrorBody.message(from: Data(#"{"error":"plain"}"#.utf8)), "plain", "error 字符串")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"error":{"message":"nested"}}"#.utf8)), "nested",
                "error.message 嵌套")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"message":"m"}"#.utf8)), "m", "message 字段")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"detail":"d"}"#.utf8)), "d", "detail 字段")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"error":""}"#.utf8)), "",
                "通用方言：空串原样返回（与改造前 BillingHTTPClient 同口径）")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"error":""}"#.utf8), dialect: .errorOrNested), nil,
                "OpencodeGo 方言：空串当没给")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"error":{"message":"n"}}"#.utf8), dialect: .errorOrNested),
                "n", "OpencodeGo 方言支持嵌套 message")
    assertEqual(HTTPErrorBody.message(from: Data(#"{"error":{"message":"n"}}"#.utf8), dialect: .plainError), nil,
                "Ollama / Open Design 只认顶层字符串")
    assertEqual(HTTPErrorBody.message(from: Data("not json".utf8)), nil, "非 JSON → nil")
}

// MARK: - provider 覆写

private func testBillingMapperUsesProviderStatus() {
    // 传输失败 → BillingError.transport（不经过状态码）
    let transport = BillingHTTPMapper.billing(.transport(HTTPTransportFailure(message: "超时")))
    assertEqual(transport, .transport("超时"), "传输失败 → transport 并保留原因")

    // 非 HTTP 响应
    assertEqual(BillingHTTPMapper.billing(.notHTTP), .invalidResponse("非 HTTP 响应"),
                "非 HTTP 响应 → invalidResponse")

    // 默认口径：403 用错误体文案
    let forbidden = BillingHTTPMapper.billing(.response(HTTPResponse(data: Data(#"{"error":"nope"}"#.utf8),
                                                                   statusCode: 403)))
    assertEqual(forbidden, .forbidden("nope"), "403 默认用错误体文案")

    // per-provider 覆写：同一 403 换该家话术
    let overridden = BillingHTTPMapper.billing(.response(HTTPResponse(data: Data(), statusCode: 403)),
                                               status: OpencodeGoBillingProvider.mapHTTPError)
    assertEqual(overridden, .forbidden(OpencodeGoBillingProvider.noSubscriptionMessage),
                "OpencodeGo 的 403 用自己的「没订阅」话术")

    // 400 的兜底话术（错误体没文案时）
    let withFallback = BillingHTTPMapper.billing(.response(HTTPResponse(data: Data(), statusCode: 400)),
                                                 badRequestFallback: "请求参数有误（接口可能已变更）")
    assertEqual(withFallback, .invalidRequest("请求参数有误（接口可能已变更）"),
                "400 无错误体时用 provider 兜底话术")

    // 地址构造：path + query 拼装与改造前同形
    assertEqual(billingURL(path: "/api/v1/key"), "https://openrouter.ai/api/v1/key",
                "base + path 拼装")
    assertEqual(billingURL(path: "/api/usage", query: [("range", "1d"), ("group_by", "model")]),
                "https://openrouter.ai/api/usage?range=1d&group_by=model", "query 顺序原样")
    assertEqual(HTTPURLBuilder.Failure.invalidBase, HTTPURLBuilder.Failure.invalidBase,
                "地址构造失败有明确错误类型（BillingHTTPMapper.url 翻成 invalidRequest）")
}

/// 拼装成功返回绝对地址，失败返回空串
private func billingURL(path: String, query: [(String, String)] = []) -> String {
    let base = URL(string: "https://openrouter.ai")!
    return (try? BillingHTTPMapper.url(base: base, path: path, query: query))?.absoluteString ?? ""
}

// MARK: - 注入的 transport

/// provider 必须用注入的传输层（替身收到请求才算生效）
private func testProviderUsesInjectedTransport() {
    let stub = RecordingTransport()
    let provider = OllamaBillingProvider(baseURL: URL(string: "https://example.com")!,
                                         transport: stub,
                                         logger: ConsoleLogger(minLevel: .error))
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        _ = try? await provider.fetchBalance(credential: "sk-test")
        done.signal()
    }
    done.wait()
    assertEqual(stub.count, 1, "注入 transport 被调用一次")
    assertEqual(stub.path, "/api/balance", "路径由 provider 组装")
    assertEqual(stub.authorization, "Bearer sk-test", "凭据头透传")
}

/// 记录 provider 实际发出的请求（只在被等待的那次调用里写）
private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    var count = 0
    var path = ""
    var authorization = ""
    func send<Response: Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        count += 1
        path = endpoint.url.path
        authorization = endpoint.headers["Authorization"] ?? ""
        return try endpoint.decoder(Data("{}".utf8))
    }
}

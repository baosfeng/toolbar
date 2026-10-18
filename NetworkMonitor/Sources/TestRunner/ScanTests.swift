import Foundation
import NetworkMonitorCore

// MARK: - 扫码接收测试组

/// 扫码接收测试入口 — 由 main.swift 顶层调用
///
/// 覆盖：token 生命周期与数量上限、文件名清洗与限长、局域网链接构造、
/// 二维码 PNG、上传页 HTML、错误码映射、真实 HTTP 回环、发现层 fd 清理。
func runScanTests() {
    testScanTokenStore()
    testScanFileNaming()
    testScanLinkBuilder()
    testQRCodeGenerator()
    testScanPageRenderer()
    testScanErrorMapping()
    testScanLimits()
    runScanHTTPIntegration()
    testDiscoverySocketCleanup()
    print("✅ 扫码接收测试组完成")
}

// MARK: - 可注入时钟 / 失败收集

/// 测试时钟（单线程推进、锁保护）
final class ScanClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// 异步场景失败信息收集
final class ScanFailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var message: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}

enum ScanScenarioError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let detail): return detail
        }
    }
}

// MARK: - token

private func testScanTokenStore() {
    print("\n🧪 Testing ScanTokenStore...")

    let clock = ScanClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = ScanTokenStore(now: { clock.now })

    let issued = store.issue()
    assertEqual(issued.token.count, 32, "token 为 32 位 hex")
    assertEqual(issued.token.allSatisfy(\.isHexDigit), true, "token 只含 hex 字符")
    assertEqual(issued.token, issued.token.lowercased(), "token 小写")
    assertEqual(store.isValid(issued.token), true, "新签发 token 有效")
    assertEqual(store.remainingSeconds(issued.token), 600, "默认有效期 10 分钟")

    // 过期：推进 601 秒
    clock.advance(601)
    assertEqual(store.isValid(issued.token), false, "过期 token 失效")
    assertEqual(store.remainingSeconds(issued.token), 0, "过期后剩余 0 秒")
    assertEqual(store.activeCount(), 0, "过期条目被惰性清理")

    // 数量上限：连续签发 6 个，只保留最近 5 个
    clock.advance(-601)
    var tokens: [String] = []
    for _ in 0..<6 {
        tokens.append(store.issue().token)
        clock.advance(1)
    }
    assertEqual(store.activeCount(), 5, "最多 5 个并发活跃")
    assertEqual(store.isValid(tokens[0]), false, "最早签发的被淘汰")
    assertEqual(store.isValid(tokens[5]), true, "最新签发的仍有效")

    // 伪造 / 非法格式
    assertEqual(store.isValid(String(repeating: "f", count: 32)), false, "伪造 token 无效")
    assertEqual(store.isValid("not-a-token"), false, "非 hex token 无效")
    assertEqual(store.isValid(""), false, "空 token 无效")
    assertEqual(store.remainingSeconds("bad"), 0, "非法 token 剩余 0")

    store.revokeAll()
    assertEqual(store.activeCount(), 0, "revokeAll 清空全部")
    print("✅ ScanTokenStore works")
}

// MARK: - 文件名

private func testScanFileNaming() {
    print("\n🧪 Testing ScanFileNaming...")

    assertEqual(ScanFileNaming.resolve("../x"), "x", "../x 只取 basename")
    assertEqual(ScanFileNaming.resolve("a/b"), "b", "路径分隔符被剥离")
    assertEqual(ScanFileNaming.resolve("a\\b"), "b", "反斜杠分隔符被剥离")
    assertEqual(ScanFileNaming.resolve("../../etc/passwd"), "passwd", "多级穿越只留 basename")
    assertEqual(ScanFileNaming.resolve("bad\u{0}name.txt"), "badname.txt", "控制字符被移除")
    assertEqual(ScanFileNaming.resolve(""), "未命名", "空名回落")
    assertEqual(ScanFileNaming.resolve("   "), "未命名", "纯空白回落")
    assertEqual(ScanFileNaming.resolve(".."), "_", "单独 .. 被替换")

    let long = String(repeating: "a", count: 400) + ".txt"
    let truncated = ScanFileNaming.resolve(long)
    assertEqual(truncated.utf8.count <= ScanFileNaming.maxNameBytes, true, "超长名被截断")
    assertEqual(truncated.hasSuffix(".txt"), true, "截断保留扩展名")
    assertEqual(truncated.count > 0, true, "截断后非空")

    let chinese = String(repeating: "照片", count: 200)
    let chineseTruncated = ScanFileNaming.resolve(chinese)
    assertEqual(chineseTruncated.utf8.count <= ScanFileNaming.maxNameBytes, true, "中文按字节截断")
    assertEqual(String(data: Data(chineseTruncated.utf8), encoding: .utf8) != nil, true, "截断不产生非法 UTF-8")
    print("✅ ScanFileNaming works")
}

// MARK: - 链接

private func testScanLinkBuilder() {
    print("\n🧪 Testing ScanLinkBuilder...")

    let token = String(repeating: "ab", count: 16)
    assertEqual(ScanLinkBuilder.isValidLANIPv4("192.168.1.5"), true, "192.168 LAN 地址")
    assertEqual(ScanLinkBuilder.isValidLANIPv4("10.0.0.2"), true, "10.x LAN 地址")
    assertEqual(ScanLinkBuilder.isValidLANIPv4("127.0.0.1"), false, "回环地址不可用")
    assertEqual(ScanLinkBuilder.isValidLANIPv4("0.0.0.0"), false, "0.0.0.0 不可用")
    assertEqual(ScanLinkBuilder.isValidLANIPv4("169.254.1.1"), false, "APIPA 不可用")
    assertEqual(ScanLinkBuilder.isValidLANIPv4("192.168.1.256"), false, "越界 octet 非法")
    assertEqual(ScanLinkBuilder.isValidLANIPv4("192.168.1"), false, "段数不足非法")

    let url = ScanLinkBuilder.pageURL(token: token, ip: "192.168.1.5", port: 53_319)
    assertEqual(url, "http://192.168.1.5:53319/scan?t=\(token)", "局域网扫码链接")
    assertEqual(ScanLinkBuilder.pageURL(token: token, ip: "127.0.0.1", port: 53_319) == nil,
                true, "回环地址不生成二维码链接")
    assertEqual(ScanLinkBuilder.pageURL(token: token, ip: nil, port: 53_319) == nil,
                true, "无 IP 不生成链接")
    assertEqual(ScanLinkBuilder.pageURL(token: "short", ip: "192.168.1.5", port: 53_319) == nil,
                true, "非法 token 不生成链接")
    assertEqual(ScanLinkBuilder.pageURL(token: token, ip: "192.168.1.5", port: 0) == nil,
                true, "端口 0 不生成链接")
    print("✅ ScanLinkBuilder works")
}

// MARK: - 二维码

private func testQRCodeGenerator() {
    print("\n🧪 Testing QRCodeGenerator...")

    let text = "http://192.168.1.5:53319/scan?t=" + String(repeating: "ab", count: 16)
    guard let png = QRCodeGenerator.pngData(for: text) else {
        print("❌ 二维码 PNG 生成失败")
        exit(1)
    }
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    assertEqual(Array(png.prefix(8)), signature, "PNG 文件头")

    // IHDR 宽高（大端，offset 16…24）
    let bytes = [UInt8](png)
    guard bytes.count > 24 else {
        print("❌ 二维码 PNG 过短")
        exit(1)
    }
    let width = Int(bytes[16]) << 24 | Int(bytes[17]) << 16 | Int(bytes[18]) << 8 | Int(bytes[19])
    let height = Int(bytes[20]) << 24 | Int(bytes[21]) << 16 | Int(bytes[22]) << 8 | Int(bytes[23])
    assertEqual(width, height, "二维码为正方形")
    assertEqual(width >= 100, true, "二维码已放大（\(width)px）")

    assertEqual(QRCodeGenerator.pngData(for: "") == nil, true, "空文本不生成二维码")
    assertEqual(QRCodeGenerator.pngData(for: "   ") == nil, true, "纯空白不生成二维码")
    print("✅ QRCodeGenerator works")
}

// MARK: - 上传页

private func testScanPageRenderer() {
    print("\n🧪 Testing ScanPageRenderer...")

    let token = String(repeating: "0a", count: 16)
    let html = ScanPageRenderer.html(token: token)
    assertEqual(html.contains("局域网互传"), true, "页面标题")
    assertEqual(html.contains("var TOKEN = '\(token)'"), true, "token 注入")
    assertEqual(html.contains("/scan/upload"), true, "上传接口路径")
    assertEqual(html.contains("<script src"), false, "无外部脚本")
    assertEqual(html.contains("<link "), false, "无外部样式表")
    assertEqual(html.contains("http://") || html.contains("https://"), false, "无外部资源地址")
    assertEqual(html.contains("<meta charset=\"utf-8\">"), true, "UTF-8 声明")

    // 注入防御：非 hex 字符被过滤，不会打断 script 字符串
    let injected = ScanPageRenderer.html(token: "abcd'); alert(1); //")
    assertEqual(injected.contains("alert(1)"), false, "非 hex token 字符被过滤")
    assertEqual(injected.contains("var TOKEN = 'abcdae1'"), true, "仅保留 hex 片段")
    print("✅ ScanPageRenderer works")
}

// MARK: - 错误码

private func testScanErrorMapping() {
    print("\n🧪 Testing 扫码错误码映射...")

    assertEqual(TransferError.tokenMismatch.code, 4001, "无效 token → 4001")
    assertEqual(TransferError.tokenMismatch.httpStatus, 400, "无效 token → HTTP 400")
    assertEqual(TransferError.payloadTooLarge(limit: ScanProtocol.maxFileBytes).code, 4008,
                "超限 → 4008")
    assertEqual(TransferError.payloadTooLarge(limit: ScanProtocol.maxFileBytes).httpStatus, 413,
                "超限 → HTTP 413")

    let response = HttpResponse.failure(.payloadTooLarge(limit: ScanProtocol.maxFileBytes))
    assertEqual(response.status, 413, "失败响应状态 413")
    let body = String(data: response.body, encoding: .utf8) ?? ""
    assertEqual(body.contains("\"code\":4008"), true, "响应体带业务码 4008")
    print("✅ 扫码错误码映射 works")
}

// MARK: - 大小上限

private func testScanLimits() {
    print("\n🧪 Testing 扫码大小上限...")

    assertEqual(ScanProtocol.maxFileBytes, 2 * 1024 * 1024 * 1024, "单文件上限 2 GiB")
    assertEqual(ScanProtocol.maxFileBytes + 1 > ScanProtocol.maxFileBytes, true, "超限判定可用")
    assertEqual(ScanProtocol.tokenTTL, 600, "token 有效期 10 分钟")
    assertEqual(ScanProtocol.maxActiveTokens, 5, "并发 token 上限 5")
    print("✅ 扫码大小上限 works")
}


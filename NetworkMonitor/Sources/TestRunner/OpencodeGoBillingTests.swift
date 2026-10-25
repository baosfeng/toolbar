import Foundation
import NetworkMonitorCore

// MARK: - OpenCode Go 计费 provider 测试

/// OpenCode Go 额度 provider 测试：三窗口解码、已用→剩余换算、已限流置零、新旧字段兼容、
/// 缺窗口降级、百分比钳制、HTTP 错误映射、fetchUsage 不发请求
///
/// 全部为纯函数解码 + 错误映射测试，不依赖外网与真实 Key；其中
/// `testOpencodeGoRealSample` 用的是 2026-10-25 实测的真实 200 响应体（去掉鉴权信息），
/// 用来锁住「服务端实际形态」与解析口径，避免只按调研推测回归。
func runOpencodeGoBillingTests() {
    print("\n🧪 Testing OpenCode Go 三窗口解码...")
    testOpencodeGoWindowDecoding()

    print("\n🧪 Testing OpenCode Go 已限流与脏值钳制...")
    testOpencodeGoRateLimitedAndClamping()

    print("\n🧪 Testing OpenCode Go 旧字段名兼容...")
    testOpencodeGoLegacyFields()

    print("\n🧪 Testing OpenCode Go 缺窗口降级...")
    testOpencodeGoMissingWindows()

    print("\n🧪 Testing OpenCode Go HTTP 错误映射...")
    testOpencodeGoHTTPErrorMapping()

    print("\n🧪 Testing OpenCode Go fetchUsage 不发请求...")
    testOpencodeGoFetchUsageDoesNotRequest()

    print("\n🧪 Testing OpenCode Go 真实响应样本...")
    testOpencodeGoRealSample()

    print("\n🧪 Testing OpenCode Go 能力声明...")
    testOpencodeGoCapabilities()

    print("✅ OpenCode Go 额度 provider works")
}

// MARK: - 三窗口解码

/// 新形态：三窗口包在 usage 里，percent 是已用比例，映射成剩余
///
/// 用 25 / 12.5 / 100 这类二进制可精确表示的百分比，避免浮点尾差让断言变脆。
private func testOpencodeGoWindowDecoding() {
    let json = """
    { "usage": {
        "rolling": { "percent": 25, "resetsAt": "2026-10-25T12:00:00Z", "status": "ok" },
        "weekly": { "percent": 12.5, "resetsAt": "2026-10-31T00:00:00Z", "status": "ok" },
        "monthly": { "percent": 100, "resetsAt": "2026-11-24T00:00:00Z", "status": "ok" } } }
    """
    guard let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8)) else {
        assertEqual("decode failed", "", "三窗口解码不应失败")
        return
    }

    assertEqual(balance.percentLimits.count, 3, "三个窗口各一条限额")
    assertEqual(balance.percentLimits.map(\.id),
                ["window:rolling", "window:weekly", "window:monthly"], "稳定 id 与展示顺序")
    assertEqual(balance.percentLimits.map(\.title), ["5 小时", "每周", "每月"], "窗口标题")
    assertEqual(balance.percentLimits[0].remainingFraction, 0.75, "已用 25% → 剩余 75%")
    assertEqual(balance.percentLimits[1].remainingFraction, 0.875, "已用 12.5% → 剩余 87.5%")
    assertEqual(balance.percentLimits[2].remainingFraction, 0, "已用 100% → 剩余 0")
    assertEqual(balance.percentLimits[0].resetsAt, isoDate("2026-10-25T12:00:00Z"),
                "重置时刻按 RFC3339 解析")
    assertEqual(balance.percentLimits[0].badge == nil, true, "正常窗口无角标")
    assertEqual(balance.percentLimits[0].hasAmountDetail, false, "接口不给绝对值明细")
    assertEqual(balance.included == nil, true, "无内含美元额度")
    assertEqual(balance.purchasedUSD == nil, true, "无已购额度")
    assertEqual(balance.totalAvailableUSD == nil, true, "只有百分比时可用总额为 nil")
    assertEqual(balance.isEmpty, false, "有限额不为空")
}

// MARK: - 已限流 / 脏值

/// rate-limited 表示窗口耗尽：剩余强制 0（让阈值提醒生效）并带角标；
/// 百分比越界（负数 / 超过 100）先钳制再换算。
private func testOpencodeGoRateLimitedAndClamping() {
    let json = """
    { "usage": {
        "rolling": { "percent": 100, "status": "rate-limited" },
        "weekly": { "percent": 120, "status": "ok" },
        "monthly": { "percent": -5, "status": " RATE-LIMITED " } } }
    """
    guard let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8)) else {
        assertEqual("decode failed", "", "限流响应解码不应失败")
        return
    }

    assertEqual(balance.percentLimits.count, 3, "限流响应仍出三窗口")
    assertEqual(balance.percentLimits[0].remainingFraction, 0, "已限流窗口剩余置 0")
    assertEqual(balance.percentLimits[0].badge ?? "", "已限流", "已限流窗口带角标")
    assertEqual(balance.percentLimits[1].remainingFraction, 0, "已用 120% 钳制到剩余 0")
    assertEqual(balance.percentLimits[1].badge == nil, true, "状态 ok 的窗口无角标")
    assertEqual(balance.percentLimits[2].remainingFraction, 0, "已限流窗口即使脏值也归零")
    assertEqual(balance.percentLimits[2].badge ?? "", "已限流", "状态值大小写与首尾空白不敏感")

    // 负已用比例（脏数据）→ 剩余钳制到 100%
    let dirty = #"{ "usage": { "rolling": { "percent": -5, "status": "ok" } } }"#
    let clamped = try? OpencodeGoBillingProvider.decodeBalance(from: Data(dirty.utf8))
    assertEqual(clamped?.percentLimits.first?.remainingFraction ?? -1, 1,
                "负已用比例钳制到剩余 100%")
    assertEqual(clamped?.percentLimits.first?.badge == nil, true, "未限流不加角标")
}

// MARK: - 旧字段名兼容

/// 旧形态（2026-08 前后）：窗口键 rollingUsage / weeklyUsage / monthlyUsage + usagePercent + resetInSec
private func testOpencodeGoLegacyFields() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let json = """
    { "rollingUsage": { "usagePercent": 25, "resetInSec": 3600 },
      "weeklyUsage": { "usagePercent": 50 },
      "monthlyUsage": { "usagePercent": 100, "resetInSec": 60 } }
    """
    guard let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8), now: now) else {
        assertEqual("decode failed", "", "旧字段名解码不应失败")
        return
    }

    assertEqual(balance.percentLimits.count, 3, "旧形态仍出三窗口")
    assertEqual(balance.percentLimits.map(\.id),
                ["window:rolling", "window:weekly", "window:monthly"], "旧形态窗口 id 与顺序")
    assertEqual(balance.percentLimits[0].remainingFraction, 0.75, "旧形态已用 25% → 剩余 75%")
    assertEqual(balance.percentLimits[0].resetsAt, now.addingTimeInterval(3600),
                "resetInSec 按注入的基准时刻换算成绝对时刻")
    assertEqual(balance.percentLimits[1].remainingFraction, 0.5, "旧形态已用 50% → 剩余 50%")
    assertEqual(balance.percentLimits[1].resetsAt == nil, true, "缺重置字段时为 nil")
    assertEqual(balance.percentLimits[2].resetsAt, now.addingTimeInterval(60), "月末窗口重置时刻")
}

// MARK: - 缺窗口降级

/// 缺哪个窗口就少一条，三条全缺才报解析失败（不整块报错）
private func testOpencodeGoMissingWindows() {
    let partial = #"{ "usage": { "weekly": { "percent": 50 } } }"#
    let one = try? OpencodeGoBillingProvider.decodeBalance(from: Data(partial.utf8))
    assertEqual(one?.percentLimits.count ?? -1, 1, "缺窗口只出存在的窗口")
    assertEqual(one?.percentLimits.first?.id ?? "", "window:weekly", "保留存在窗口的稳定 id")
    assertEqual(one?.percentLimits.first?.title ?? "", "每周", "保留存在窗口的标题")
    assertEqual(one?.percentLimits.first?.remainingFraction ?? -1, 0.5, "保留窗口照常换算")

    // 窗口在但缺比例：按缺窗口处理
    assertInvalidResponse(#"{ "usage": { "rolling": { "status": "ok" } } }"#, "窗口缺比例按缺窗口处理")
    // 三窗口全缺 / 空对象 / 非法 JSON：一律 invalidResponse
    assertInvalidResponse(#"{ "usage": {} }"#, "usage 为空对象")
    assertInvalidResponse("{}", "空对象没有任何窗口")
    assertInvalidResponse("not json", "非法 JSON")
    assertInvalidResponse(#"{ "usage": [] }"#, "usage 类型不符")
}

// MARK: - HTTP 错误映射

/// 状态码 → BillingError：401 凭据无效、403 订阅缺失中文话术、429 带 Retry-After、5xx 暂时不可用
private func testOpencodeGoHTTPErrorMapping() {
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 401, retryAfter: nil,
                                                       message: "Unauthorized"),
                .unauthorized, "401 → unauthorized")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 403, retryAfter: nil,
                                                       message: "OpenCode Go subscription required."),
                .forbidden("该 Key 没有 OpenCode Go 订阅"), "403 → 订阅缺失话术")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 429, retryAfter: 30, message: nil),
                .rateLimited(retryAfter: 30), "429 → rateLimited 带 Retry-After")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 429, retryAfter: nil, message: nil),
                .rateLimited(retryAfter: nil), "429 缺 Retry-After 时为 nil")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 503, retryAfter: nil,
                                                       message: "unavailable"),
                .serviceUnavailable("unavailable"), "5xx → serviceUnavailable")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 400, retryAfter: nil, message: "bad key"),
                .invalidRequest("bad key"), "400 → invalidRequest")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 418, retryAfter: nil, message: nil),
                .invalidResponse("HTTP 418"), "其它状态码 → invalidResponse")

    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 401, retryAfter: nil,
                                                       message: nil).userMessage,
                "凭据无效或已过期，请重新填写", "401 用户文案")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 403, retryAfter: nil,
                                                       message: nil).userMessage,
                "该 Key 没有 OpenCode Go 订阅", "403 用户文案可直接照做")
}

// MARK: - fetchUsage 不发请求

/// 该 provider 不提供用量明细：fetchUsage 必须直接抛 invalidRequest，且一个请求都不发。
///
/// 反证手法：baseURL 指向必然拒绝连接的本地端口 —— 若真发了请求，错误会变成 transport，
/// 断言 invalidRequest 失败，从而暴露「没有短路」。
private func testOpencodeGoFetchUsageDoesNotRequest() {
    let provider = OpencodeGoBillingProvider(baseURL: URL(string: "http://127.0.0.1:9")!,
                                             logger: ConsoleLogger(minLevel: .error))
    let semaphore = DispatchSemaphore(value: 0)
    let box = OpencodeGoFailureBox()
    Task.detached(priority: .userInitiated) {
        do {
            _ = try await provider.fetchUsage(range: .last24Hours, credential: "sk-test")
            box.message = "fetchUsage 没有抛错"
        } catch let error as BillingError {
            box.error = error
        } catch {
            box.message = "抛出了非 BillingError：\(error)"
        }
        semaphore.signal()
    }
    semaphore.wait()

    if let message = box.message {
        assertEqual(message, "invalidRequest", "fetchUsage 应直接抛 invalidRequest")
    }
    assertEqual(box.error, BillingError.invalidRequest("OpenCode Go 不提供用量明细"),
                "fetchUsage 恒抛 invalidRequest")
}

// MARK: - 真实响应样本

/// 真实 200 响应（2026-10-25 实测，已去掉鉴权信息）
///
/// 三点必须成立：`usage` 包壳、`percent` 为整数、`resetsAt` 带毫秒（漏解析会让重置时间整块丢）。
private func testOpencodeGoRealSample() {
    let json = """
    {"usage":{"rolling":{"status":"ok","percent":2,"resetsAt":"2026-10-25T18:40:47.000Z"},\
    "weekly":{"status":"ok","percent":1,"resetsAt":"2026-10-26T00:00:00.000Z"},\
    "monthly":{"status":"ok","percent":52,"resetsAt":"2026-11-02T11:35:06.000Z"}}}
    """
    guard let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8)) else {
        assertEqual("decode failed", "", "真实响应不应解码失败")
        return
    }
    assertEqual(balance.percentLimits.count, 3, "真实响应三个窗口齐全")
    assertEqual(balance.percentLimits.map(\.title), ["5 小时", "每周", "每月"], "真实响应窗口标题")
    // 已用 2% / 1% / 52% → 剩余 98% / 99% / 48%（按展示口径断言，规避浮点尾差）
    assertEqual(formatPercent(balance.percentLimits[0].remainingFraction), "98%", "5 小时窗口剩余")
    assertEqual(formatPercent(balance.percentLimits[1].remainingFraction), "99%", "每周窗口剩余")
    assertEqual(formatPercent(balance.percentLimits[2].remainingFraction), "48%", "每月窗口剩余")
    assertEqual(balance.percentLimits[0].resetsAt != nil, true, "带毫秒的 RFC3339 可解析")
    assertEqual(balance.percentLimits.allSatisfy { $0.badge == nil }, true, "正常窗口无角标")
}

// MARK: - 能力声明

/// 能力位决定 UI 分支与刷新节流：只查额度、无时间序列、5 分钟起刷
private func testOpencodeGoCapabilities() {
    let provider = OpencodeGoBillingProvider()
    assertEqual(provider.id, "opencode-go", "provider id 稳定")
    assertEqual(provider.displayName, "OpenCode Go", "展示名称")
    assertEqual(provider.symbolName, "terminal", "SF Symbol 图标")
    assertEqual(provider.supportsModelBreakdown, false, "无按模型明细")
    assertEqual(provider.supportsTimeSeries, false, "无服务端分桶")
    assertEqual(provider.supportsUsage, false, "无用量明细（调用方跳过用量请求）")
    assertEqual(provider.minimumRefreshInterval, 300, "官方未公布限流：5 分钟起刷")
    assertEqual(provider.credentialHint, "OpenCode Go API Key", "凭据占位文案")
    assertEqual(provider.credentialPageURL?.absoluteString, "https://opencode.ai/", "凭据页地址")
    assertEqual(BillingRefreshScheduler.interval(providerMinimum: provider.minimumRefreshInterval), 300,
                "有效刷新间隔取 provider 建议值")
}

// MARK: - 测试辅助

/// 断言解码抛 invalidResponse（只比错误类型，避免依赖底层错误描述文案）
private func assertInvalidResponse(_ json: String, _ message: String) {
    do {
        _ = try OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8))
        assertEqual("没有抛错", "invalidResponse", message)
    } catch let error as BillingError {
        if case .invalidResponse = error {
            print("✅ \(message)")
        } else {
            assertEqual("\(error)", "invalidResponse", message)
        }
    } catch {
        assertEqual("\(error)", "invalidResponse", message)
    }
}

/// ISO8601 时间串解析（与 provider 内部实现同口径，用于断言重置时刻）
private func isoDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}

/// 异步结果收集箱（跨并发域传值）
private final class OpencodeGoFailureBox: @unchecked Sendable {
    var error: BillingError?
    var message: String?
}
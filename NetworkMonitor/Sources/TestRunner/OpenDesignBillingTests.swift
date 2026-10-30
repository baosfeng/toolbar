import Foundation
import NetworkMonitorCore

// MARK: - Open Design 计费 provider 测试

/// Open Design 额度 provider 测试：凭据归一化、工作区发现、额度窗口映射、
/// 用量聚合、时间窗口推导、错误映射
///
/// 全部为纯函数 / 解码测试，不依赖外网与真实 Cookie。
func runOpenDesignBillingTests() {
    print("\n🧪 Testing OpenDesign credential normalization...")
    testOpenDesignTokenNormalization()

    print("\n🧪 Testing OpenDesign workspace decoding...")
    testOpenDesignWorkspaceDecoding()

    print("\n🧪 Testing OpenDesign balance decoding...")
    testOpenDesignBalanceDecoding()


    print("✅ Open Design 额度 provider works")
}

// MARK: - 凭据归一化

private func testOpenDesignTokenNormalization() {
    let pureToken = "abc123.signature%2Fpart"

    // 纯 token 直接使用
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(pureToken), pureToken, "纯 token 原样")

    // 整条 Cookie 串：抽取目标键
    let fullCookie = "__Secure-better-auth.session_token=\(pureToken); other=1"
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(fullCookie), pureToken,
                "从 Cookie 串抽取 session token")

    // 带 Cookie: 前缀
    let withPrefix = "Cookie: __Secure-better-auth.session_token=\(pureToken)"
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(withPrefix), pureToken,
                "剥离 Cookie: 前缀")

    // 其他 Cookie 在前的顺序
    let reordered = "od_attr=xyz; __Secure-better-auth.session_token=\(pureToken); tail=2"
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(reordered), pureToken,
                "目标键不在首位也能抽取")

    // 首尾空白与换行
    assertEqual(try? OpenDesignBillingProvider.normalizedToken("  \(pureToken)  "), pureToken,
                "裁剪首尾空白")

    // 空凭据：抛 missingCredential
    var emptyError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.normalizedToken("   ")
    } catch let error as BillingError {
        emptyError = error
    } catch {}
    assertEqual(emptyError, .missingCredential, "空凭据抛 missingCredential")
}

// MARK: - 工作区发现

private func testOpenDesignWorkspaceDecoding() {
    let json = """
    { "items": [ { "workspaceId": "fbpzndory1pwn0jgb6r68ed8", "workspaceName": "个人工作区",
                   "workspaceType": "personal", "role": "owner" },
                 { "workspaceId": "second-workspace", "workspaceName": "团队", "role": "member" } ] }
    """
    assertEqual(try? OpenDesignBillingProvider.decodeWorkspaceID(from: Data(json.utf8)),
                "fbpzndory1pwn0jgb6r68ed8", "取首个 workspaceId")

    // 空列表：invalidResponse
    var emptyListError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeWorkspaceID(from: Data(#"{ "items": [] }"#.utf8))
    } catch let error as BillingError {
        emptyListError = error
    } catch {}
    if case .invalidResponse = emptyListError {} else {
        assertEqual("\(String(describing: emptyListError))", "invalidResponse", "空工作区抛 invalidResponse")
    }

    // 结构不符：invalidResponse
    var malformedError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeWorkspaceID(from: Data(#"{ "unexpected": 1 }"#.utf8))
    } catch let error as BillingError {
        malformedError = error
    } catch {}
    if case .invalidResponse = malformedError {} else {
        assertEqual("\(String(describing: malformedError))", "invalidResponse", "结构不符抛 invalidResponse")
    }
}

// MARK: - 额度解码

private func testOpenDesignBalanceDecoding() {
    let json = """
    { "workspaceId": "fbpzndory1pwn0jgb6r68ed8", "generatedAt": "2026-10-23T15:20:38.939Z",
      "eligible": true, "tier": "go",
      "windows": [
        { "policyId": "model_limit_policy_yfhv1kw691dx46efu0lgxvnf",
          "durationSeconds": 18000, "resetMode": "anchored_recurring",
          "usedCredits": "123", "limitCredits": "50000", "remainingCredits": "49877",
          "windowStart": "2026-10-23T15:02:22.830Z", "resetsAt": "2026-10-23T20:02:22.830Z" },
        { "policyId": "model_limit_policy_ois3y3aw7jmck720x5bobizq",
          "durationSeconds": 604800, "resetMode": "anchored_recurring",
          "usedCredits": "76378", "limitCredits": "150000", "remainingCredits": "73622",
          "windowStart": "2026-10-20T12:02:22.830Z", "resetsAt": "2026-10-27T12:02:22.830Z" }
      ] }
    """
    guard let balance = try? OpenDesignBillingProvider.decodeBalance(from: Data(json.utf8)) else {
        assertEqual("decode failed", "", "额度解码不应失败")
        return
    }

    // 无金额维度：走「遗留计划」渲染分支
    assertEqual(balance.included == nil, true, "无内含额度")
    assertEqual(balance.purchasedUSD == nil, true, "无已购额度")
    assertEqual(balance.percentLimits.count, 2, "两个窗口")
    assertEqual(balance.isEmpty, false, "有百分比限额不为空")

    let fiveHour = balance.percentLimits[0]
    assertEqual(fiveHour.id, "model_limit_policy_yfhv1kw691dx46efu0lgxvnf", "id 取 policyId")
    assertEqual(fiveHour.title, "5 小时", "18000 秒 → 5 小时")
    assertEqual(fiveHour.usedAmount ?? -1, 123, "已用 credits")
    assertEqual(fiveHour.limitAmount ?? -1, 50_000, "限额 credits")
    assertEqual(fiveHour.unitLabel ?? "", "credits", "单位为 credits")
    assertEqual(fiveHour.hasAmountDetail, true, "有绝对值明细")
    assertEqual((fiveHour.remainingFraction * 100).rounded(), 100, "剩余 99.75% 四舍五入 100%")
    assertNotNil(fiveHour.resetsAt, "重置时间可解析")

    let weekly = balance.percentLimits[1]
    assertEqual(weekly.title, "每周", "604800 秒 → 每周")
    assertEqual((weekly.remainingFraction * 1_000).rounded() / 1_000, 0.491, "每周剩余比例 73622/150000")
    assertEqual(formatLimitUsage(used: weekly.usedAmount, limit: weekly.limitAmount,
                                 unit: weekly.unitLabel) ?? "",
                "已用 76,378 / 150,000 credits", "credits 明细文案")

    // 未开通编码计划：forbidden
    let ineligible = #"{ "eligible": false, "tier": "free", "windows": [] }"#
    var ineligibleError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeBalance(from: Data(ineligible.utf8))
    } catch let error as BillingError {
        ineligibleError = error
    } catch {}
    if case .forbidden = ineligibleError {} else {
        assertEqual("\(String(describing: ineligibleError))", "forbidden", "未开通抛 forbidden")
    }

    // 限额为 0：比例为 0 不崩
    let zeroLimit = """
    { "eligible": true, "windows": [ { "policyId": "p0", "durationSeconds": 3600,
      "usedCredits": "0", "limitCredits": "0", "remainingCredits": "0" } ] }
    """
    let zeroBalance = try? OpenDesignBillingProvider.decodeBalance(from: Data(zeroLimit.utf8))
    assertEqual(zeroBalance?.percentLimits.first?.remainingFraction ?? -1, 0, "限额 0 比例归零")
    assertEqual(zeroBalance?.percentLimits.first?.title ?? "", "1 小时", "3600 秒 → 1 小时")
    assertEqual(zeroBalance?.percentLimits.first?.resetsAt == nil, true, "缺 resetsAt 为 nil")
}

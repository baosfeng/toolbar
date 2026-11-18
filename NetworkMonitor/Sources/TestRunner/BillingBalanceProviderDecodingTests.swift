import Foundation
import NetworkMonitorCore

// MARK: - 三家余额型 provider 的解码

/// 覆盖 DeepSeek / Moonshot / OpenRouter 的响应结构与失败姿态。
///
/// 三家都是「纯余额」provider（`supportsUsage = false`），额度判定全靠这一次解码，
/// 因此断言分三档：正常响应（金额 + 币种）、边界（余额 0 与无上限 Key）、
/// 异常（字段缺失 / 空 body 必须给明确 BillingError，不静默成 0）。
/// 接口字段见各 DTO 文件头部的官方文档链接。
func runBillingBalanceProviderDecodingTests() {
    print("\n🧪 Testing DeepSeek 余额解码...")
    testDeepSeekBalanceDecoding()

    print("\n🧪 Testing Moonshot 余额解码...")
    testMoonshotBalanceDecoding()

    print("\n🧪 Testing OpenRouter 余额解码...")
    testOpenRouterBalanceDecoding()

    print("✅ Billing 三家余额型 provider 解码 works")
}

// MARK: - DeepSeek

/// 官方 `/user/balance` 形态：金额是**字符串**，按 `balance_infos` 分币种列条
private func testDeepSeekBalanceDecoding() {
    let sample = """
    {
      "is_available": true,
      "balance_infos": [
        {"currency": "CNY", "total_balance": "110.00",
         "granted_balance": "10.00", "topped_up_balance": "100.00"}
      ]
    }
    """.data(using: .utf8)!
    do {
        let balance = try DeepSeekBillingDecoding.decodeBalance(from: sample)
        assertEqual(balance.purchasedUSD ?? -1, 110, "余额取 total_balance")
        assertEqual(balance.currencyCode, "CNY", "币种随响应 currency 走")
        assertEqual(balance.included == nil, true, "余额型 provider 无内含额度")
        assertEqual(balance.isEmpty, false, "有余额不为空态")
        assertEqual(balance.totalAvailableUSD ?? -1, 110, "可用总额 = 已购余额")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "DeepSeek 官方样本解码")
    }

    // 多币种账户：优先取 USD，而不是碰巧排第一的币种
    let multi = """
    {"balance_infos": [{"currency": "CNY", "total_balance": "10.00"},
                       {"currency": "USD", "total_balance": "7.50"}]}
    """.data(using: .utf8)!
    let multiBalance = try? DeepSeekBillingDecoding.decodeBalance(from: multi)
    assertEqual(multiBalance?.purchasedUSD ?? -1, 7.5, "多币种优先取 USD")
    assertEqual(multiBalance?.currencyCode ?? "", "USD", "币种跟随取到的那条")

    // 边界：余额 0 是「真没钱」，不是「无数据」
    let zero = #"{"balance_infos": [{"currency": "CNY", "total_balance": "0.00"}]}"#
        .data(using: .utf8)!
    let zeroBalance = try? DeepSeekBillingDecoding.decodeBalance(from: zero)
    assertEqual(zeroBalance?.purchasedUSD ?? -1, 0, "余额 0 解析为 0（与无数据区分）")
    assertEqual(zeroBalance?.isEmpty ?? true, false, "余额 0 不是空余额态")

    // 异常：字段缺失 / 非数字 / 空 body 一律明确失败，不静默成 0
    assertEqual(billingErrorMessage {
        _ = try DeepSeekBillingDecoding.decodeBalance(from: Data(#"{"is_available": true}"#.utf8))
    }, "响应里没有 balance_infos", "缺 balance_infos 报解析失败")
    assertEqual(billingErrorMessage {
        _ = try DeepSeekBillingDecoding.decodeBalance(
            from: Data(#"{"balance_infos": [{"currency": "CNY"}]}"#.utf8))
    }, "total_balance 无法解析", "缺 total_balance 报解析失败")
    assertEqual(billingErrorMessage {
        _ = try DeepSeekBillingDecoding.decodeBalance(
            from: Data(#"{"balance_infos": [{"currency": "CNY", "total_balance": "abc"}]}"#.utf8))
    }, "total_balance 无法解析", "非数字金额报解析失败")
    assertEqual(billingErrorCase(deepSeekEmptyBodyError()), "invalidResponse", "空 body 报解析失败")
}

/// 空 body 的错误（JSONDecoder 的描述随系统版本变化，只断言错误类型）
private func deepSeekEmptyBodyError() -> BillingError {
    do {
        _ = try DeepSeekBillingDecoding.decodeBalance(from: Data())
    } catch let error as BillingError {
        return error
    } catch {
        return .transport("\(error)")
    }
    return BillingError.invalidRequest("空 body 没有抛错")
}

// MARK: - Moonshot

/// 官方 `/v1/users/me/balance` 形态：`data.available_balance` 为可用余额，
/// 币种由站点实例注入（国内站 CNY / 国际站 USD），接口本身不返回
private func testMoonshotBalanceDecoding() {
    let sample = """
    {"code": 0, "status": true,
     "data": {"available_balance": 100.5, "voucher_balance": 10, "cash_balance": 90.5}}
    """.data(using: .utf8)!
    do {
        let balance = try MoonshotBillingDecoding.decodeBalance(from: sample, currencyCode: "CNY")
        assertEqual(balance.purchasedUSD ?? -1, 100.5, "余额取 available_balance")
        assertEqual(balance.currencyCode, "CNY", "币种用站点本位币（国内站）")
        assertEqual(balance.isEmpty, false, "有余额不为空态")
        let intl = try MoonshotBillingDecoding.decodeBalance(from: sample, currencyCode: "USD")
        assertEqual(intl.currencyCode, "USD", "同一响应在国际站按 USD 计价")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "Moonshot 官方样本解码")
    }

    // 边界：可用余额 0（代金券已用完）仍是有效数据
    let zero = #"{"code": 0, "status": true, "data": {"available_balance": 0}}"#
        .data(using: .utf8)!
    let zeroBalance = try? MoonshotBillingDecoding.decodeBalance(from: zero, currencyCode: "USD")
    assertEqual(zeroBalance?.purchasedUSD ?? -1, 0, "余额 0 解析为 0（与无数据区分）")
    assertEqual(zeroBalance?.isEmpty ?? true, false, "余额 0 不是空余额态")

    // 异常：业务码 / 状态位 / 字段缺失都明确失败
    assertEqual(billingErrorMessage {
        _ = try MoonshotBillingDecoding.decodeBalance(
            from: Data(#"{"code": 1001, "status": true, "data": {"available_balance": 1}}"#.utf8),
            currencyCode: "CNY")
    }, "接口返回错误码 1001", "业务码非 0 报解析失败")
    assertEqual(billingErrorMessage {
        _ = try MoonshotBillingDecoding.decodeBalance(
            from: Data(#"{"code": 0, "status": false, "data": {"available_balance": 1}}"#.utf8),
            currencyCode: "CNY")
    }, "接口返回 status=false", "status=false 报解析失败")
    assertEqual(billingErrorMessage {
        _ = try MoonshotBillingDecoding.decodeBalance(from: Data(#"{"code": 0, "status": true}"#.utf8),
                                                      currencyCode: "CNY")
    }, "响应里没有 data.available_balance", "缺 data 报解析失败")
    assertEqual(billingErrorCase(moonshotEmptyBodyError()), "invalidResponse", "空 body 报解析失败")
}

/// 空 body 的错误（只断言错误类型）
private func moonshotEmptyBodyError() -> BillingError {
    do {
        _ = try MoonshotBillingDecoding.decodeBalance(from: Data(), currencyCode: "CNY")
    } catch let error as BillingError {
        return error
    } catch {
        return .transport("\(error)")
    }
    return BillingError.invalidRequest("空 body 没有抛错")
}

// MARK: - OpenRouter

/// 官方 `/api/v1/key` 形态：`limit` 为 null 表示无上限，余额 = `limit_remaining`
private func testOpenRouterBalanceDecoding() {
    let sample = """
    {"data": {"label": "sk-or-v1-abc", "limit": 100, "limit_remaining": 42.5,
              "limit_reset": "monthly", "usage": 57.5, "is_free_tier": false}}
    """.data(using: .utf8)!
    do {
        let balance = try OpenRouterBillingDecoding.decodeBalance(from: sample)
        assertEqual(balance.purchasedUSD ?? -1, 42.5, "余额取 limit_remaining")
        assertEqual(balance.currencyCode, "USD", "OpenRouter 按美元计价")
        assertEqual(balance.percentLimits.isEmpty, true, "有上限时不产百分比行")
        assertEqual(balance.isEmpty, false, "有余额不为空态")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "OpenRouter 官方样本解码")
    }

    // 兜底：缺 limit_remaining 时用 limit - usage
    let fallback = #"{"data": {"limit": 100, "usage": 30}}"#.data(using: .utf8)!
    let fallbackBalance = try? OpenRouterBillingDecoding.decodeBalance(from: fallback)
    assertEqual(fallbackBalance?.purchasedUSD ?? -1, 70, "缺 limit_remaining 时按 limit - usage 兜底")

    // 边界：余额 0 是「额度用完」，不是「无数据」
    let zero = #"{"data": {"limit": 100, "limit_remaining": 0, "usage": 100}}"#.data(using: .utf8)!
    let zeroBalance = try? OpenRouterBillingDecoding.decodeBalance(from: zero)
    assertEqual(zeroBalance?.purchasedUSD ?? -1, 0, "余额 0 解析为 0（与无数据区分）")
    assertEqual(zeroBalance?.isEmpty ?? true, false, "余额 0 不是空余额态")

    // 边界：无上限 Key 必须出「无限制」行，而不是 0
    let unlimited = #"{"data": {"label": "sk-or-v1-unlimited", "limit": null, "usage": 12.5}}"#
        .data(using: .utf8)!
    let unlimitedBalance = try? OpenRouterBillingDecoding.decodeBalance(from: unlimited)
    assertEqual(unlimitedBalance?.purchasedUSD == nil, true, "无上限 Key 不产出余额数字")
    assertEqual(unlimitedBalance?.percentLimits.count ?? 0, 1, "无上限 Key 产出一条额度行")
    assertEqual(unlimitedBalance?.percentLimits.first?.badge ?? "", "无限制", "无上限 Key 角标「无限制」")
    assertEqual(unlimitedBalance?.percentLimits.first?.remainingFraction ?? 0, 1, "无限制行剩余 100%")
    assertEqual(unlimitedBalance?.isEmpty ?? true, false, "无限制不算空余额态")

    // 异常：缺失 data / 非法 limit / 空 body
    assertEqual(billingErrorMessage {
        _ = try OpenRouterBillingDecoding.decodeBalance(from: Data(#"{"error": "unauthorized"}"#.utf8))
    }, "响应里没有 data", "缺 data 报解析失败")
    assertEqual(billingErrorMessage {
        _ = try OpenRouterBillingDecoding.decodeBalance(
            from: Data(#"{"data": {"limit": -1, "limit_remaining": 0}}"#.utf8))
    }, "limit 不是有效数字", "负 limit 报解析失败")
    assertEqual(billingErrorCase(openRouterEmptyBodyError()), "invalidResponse", "空 body 报解析失败")
}

/// 空 body 的错误（只断言错误类型）
private func openRouterEmptyBodyError() -> BillingError {
    do {
        _ = try OpenRouterBillingDecoding.decodeBalance(from: Data())
    } catch let error as BillingError {
        return error
    } catch {
        return .transport("\(error)")
    }
    return BillingError.invalidRequest("空 body 没有抛错")
}

#!/bin/bash
# 新增「额度 provider」脚手架 —— 生成 provider 类 + 打印必须人工改的 5 处
#
# 用法：
#   bash NetworkMonitor/Scripts/scaffold/new-billing-provider.sh <kindID> <显示名> [--dry-run] [--out <目录>] [--force]
#
# kindID 是凭据键 / 启用键 / 提醒状态键的组成部分（BillingInstance 的默认实例 id = kindID），
# 发布后不可变更。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

usage() {
    echo "用法：new-billing-provider.sh <kindID> <显示名> [选项]"
    echo ""
    echo "  kindID   小写字母 / 数字 / 连字符，如 acme、open-code"
    echo "  显示名   额度页 provider 卡标题，如「Acme」"
    usage_common
}

POSITIONAL=()
parse_common_args "$@"

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
    usage >&2
    exit 2
fi

KIND_ID="${POSITIONAL[0]}"
DISPLAY_NAME="${POSITIONAL[1]}"
require_id "${KIND_ID}" "provider kindID"

PASCAL="$(pascal_case "${KIND_ID}")"
TARGET_DIR="${OUT_DIR:-${NM_DIR}/Sources/NetworkMonitor/Billing/Providers}"
PROVIDER_PATH="${TARGET_DIR}/${PASCAL}BillingProvider.swift"

echo "额度 provider 脚手架：kindID=${KIND_ID} / 显示名=${DISPLAY_NAME} / 类名=${PASCAL}BillingProvider"

render_provider() {
    sed -e "s/__PASCAL__/${PASCAL}/g" -e "s/__KIND_ID__/${KIND_ID}/g" -e "s|__DISPLAY_NAME__|${DISPLAY_NAME}|g" <<'SWIFT'
import Foundation
import NetworkMonitorCore

// MARK: - __DISPLAY_NAME__ 额度 provider

/// __DISPLAY_NAME__ 额度 provider —— 由 Scripts/scaffold/new-billing-provider.sh 生成
///
/// 协议在 NetworkMonitorCore/Billing/BillingProvider.swift:9：
///   id / displayName / symbolName / supports* / credentialHint / credentialPageURL /
///   environmentCredentialKey / declaredQuotaWindowKinds / fetchBalance / fetchUsage
/// 协议已给默认实现（:184 起）：supportsTimeSeries=true、supportsUsage=true、
/// supportedUsageRanges=全部、minimumRefreshInterval=0、credentialPageURL=nil、
/// declaredQuotaWindowKinds=[]、environmentCredentialKey=BILLING_<ID>_API_KEY。
/// **只覆盖与本 provider 不符的项**，不要整组重写一遍默认值。
///
/// 错误一律扔 BillingError（:49 起）：missingCredential / unauthorized / forbidden /
/// rateLimited / serviceUnavailable / invalidRequest / invalidResponse / transport；
/// UI 直接展示 userMessage，不要再拼一套文案。
public final class __PASCAL__BillingProvider: BillingProvider {

    // MARK: 身份

    /// 稳定标识：凭据键 / 偏好键 / 提醒状态键都按它派生，发布后不可变更
    public let id = "__KIND_ID__"
    public let displayName = "__DISPLAY_NAME__"
    /// SF Symbols 名（禁止 emoji）
    public let symbolName = "creditcard"
    /// 是否返回按模型分组的明细（UI 据此决定是否显示模型 Top 列表）
    public let supportsModelBreakdown = false
    /// 只查余额时置 false：状态管理器会跳过用量请求，UI 隐藏用量区
    public let supportsUsage = false
    /// 官方未公布限流时给较长间隔（秒），少打接口
    public let minimumRefreshInterval: TimeInterval = 300

    public var credentialHint: String { "__DISPLAY_NAME__ API Key" }
    /// 凭据获取页（没有就删掉这一行，走协议默认 nil）
    public var credentialPageURL: URL? { URL(string: "https://example.com/keys") }

    // MARK: 依赖

    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.client = BillingHTTPClient(session: session, logger: logger)
        self.logger = logger
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let token = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BillingError.missingCredential }

        // TODO: 换成真实端点与鉴权头
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/balance")!)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        let response = try await client.send(request, providerName: displayName)
        guard response.isSuccess else {
            throw Self.mapHTTPError(statusCode: response.statusCode,
                                    retryAfter: response.retryAfter,
                                    message: response.message)
        }
        // TODO: 换成真实字段；币种按响应给（BillingBalance(currencyCode:)）
        let object = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
        guard let amount = object?["balance"] as? Double else {
            logger.warning("__DISPLAY_NAME__ 余额响应解析失败（接口可能已变更）")
            throw BillingError.invalidResponse("缺少 balance 字段")
        }
        return BillingBalance(purchasedUSD: amount, currencyCode: "USD")
    }

    /// 只查余额的 provider 必须在这里明确拒绝，不要返回空结构（UI 会以为查到了 0）
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("__DISPLAY_NAME__ 不提供用量明细")
    }

    // MARK: - HTTP 状态码收敛

    /// 8 种 BillingError 的映射口径与其余 provider 一致（见 BillingProvider.swift:49）
    static func mapHTTPError(statusCode: Int,
                             retryAfter: TimeInterval?,
                             message: String?) -> BillingError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 400..<500: return .invalidRequest(message)
        case 500..<600: return .serviceUnavailable(message)
        default: return .invalidResponse(message ?? "HTTP \(statusCode)")
        }
    }
}
SWIFT
}

emit_file "${PROVIDER_PATH}" "$(render_provider)"

print_step_header 5


echo ""
echo "1. 在组合根登记（唯一注册点）"
echo "   Sources/NetworkMonitor/AppAssemblyStages+Features.swift:25  billingKinds 数组加三元组"
echo "       ("${KIND_ID}", "${DISPLAY_NAME}", { ${PASCAL}BillingProvider(logger: billingLogger) }),"
echo "     · 数组顺序 = 额度页 provider 卡顺序（语义相邻处插入）"
echo "     · 实例（含命名实例 kindID::slug）由 BillingInstanceStore.ensureDefaults 自动派生，不用手写"

echo ""
echo "2. 若 provider 有周期窗口：声明窗口种类"
echo "   Sources/NetworkMonitorCore/Billing/__PASCAL__BillingProvider.swift（本文件）加"
echo "       public var declaredQuotaWindowKinds: [BillingWindowKind] { [.session, .weekly] }"
echo "     · 这是设置页「恢复通知按窗口勾选」的回落清单；不声明就按「实际观测 → 四档兜底」"
echo "     · 纯余额型（无窗口）保持默认 []"

echo ""
echo "3. 测试（解码 / 失败路径必须各一）"
echo "   新建 Sources/TestRunner/${PASCAL}BillingDecodingTests.swift：成功解码 + 8 类 HTTP 错误映射"
echo "     · 参照 Sources/TestRunner/BillingProviderFailureTests.swift 与 BillingDecodingTests.swift"
echo "     · 纯解码逻辑建议下沉到 Core（如 __PASCAL__BillingDecoding），TestRunner 才能不 import 可执行 target"
echo "   在 Sources/TestRunner/TestSuites+Billing.swift 加一行 run${PASCAL}BillingDecodingTests()"

echo ""
echo "4. 文档"
echo "   AGENTS.md「计费额度查询」行：九个 provider → 十个，写清端点 / 窗口 / 失败姿态"
echo "   docs/设计/ 若该接口需要一份规格（端点、字段、限流、降级），按「文档规范」补并在 docs/索引.md 挂链接"
echo "   规范出处：docs/开发指南/扩展点清单.md「额度 provider」一节"

echo ""
echo "5. 自检"
echo "   · 凭据必须走 SecretStorage（不要明文进 KeyValueStorage）——本模板不落地任何凭据"
echo "   · 端点失败只回报错误、保留上次成功数据（BillingMonitor 已统一处理，不要在 provider 内重试）"
echo "   · 汇率 / 币种按响应给，不要硬编码 USD → CNY 换算"

echo ""
echo "生成后可立刻编译：cd NetworkMonitor && swift build --disable-sandbox --build-system native"
echo "（未做步骤 1 时：类能编译，但额度页不会出现这个 provider）"

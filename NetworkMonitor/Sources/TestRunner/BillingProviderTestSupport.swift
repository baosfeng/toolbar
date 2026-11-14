import Foundation
import NetworkMonitorCore

// MARK: - 三家 provider 测试辅助

/// 取错误文案（成功时返回 "<no error>"）
///
/// 解析类错误返回 `detail` 本身（`userMessage` 会统一加「响应解析失败：」前缀，
/// 断言 detail 能同时验证下游文案内容）。
func billingErrorMessage(_ body: () throws -> Void) -> String {
    do {
        try body()
        return "<no error>"
    } catch let error as BillingError {
        if case .invalidResponse(let detail) = error { return detail }
        return error.userMessage
    } catch {
        return error.localizedDescription
    }
}

/// 把 BillingError 收敛成「枚举名」字符串，便于比较（关联值不参与）
func billingErrorCase(_ error: BillingError) -> String {
    switch error {
    case .missingCredential: return "missingCredential"
    case .unauthorized: return "unauthorized"
    case .forbidden: return "forbidden"
    case .rateLimited: return "rateLimited"
    case .serviceUnavailable: return "serviceUnavailable"
    case .invalidRequest: return "invalidRequest"
    case .invalidResponse: return "invalidResponse"
    case .transport: return "transport"
    }
}

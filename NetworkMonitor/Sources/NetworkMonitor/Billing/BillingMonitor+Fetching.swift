import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器（请求封装）

/// 请求封装 — 把 provider 的网络调用收敛为 `BillingOutcome`，失败统一映射为 `BillingError`。
///
/// 拆出原因：`BillingMonitor` 主体超过单文件 15 KiB 上限，按「主类 + 请求扩展」范式分离。
/// 成员由 `private` 放宽为 `internal`，供同模块的 `BillingMonitor` 主体调用。
extension BillingMonitor {

    // MARK: - 请求封装（nonisolated，避免占用主线程）

    /// 单次请求结果 — 自定义 Sendable 容器，跨 actor 传递无并发检查歧义
    enum BillingOutcome<Value: Sendable>: Sendable {
        case success(Value)
        case failure(BillingError)
    }

    /// 拉取余额，错误统一收敛为 `BillingError`
    nonisolated static func fetchBalance(
        provider: any BillingProvider,
        credential: String
    ) async -> BillingOutcome<BillingBalance> {
        do {
            return .success(try await provider.fetchBalance(credential: credential))
        } catch let error as BillingError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    /// 拉取指定范围用量，错误统一收敛为 `BillingError`
    nonisolated static func fetchUsage(
        provider: any BillingProvider,
        range: BillingRange,
        credential: String
    ) async -> BillingOutcome<BillingUsage> {
        do {
            return .success(try await provider.fetchUsage(range: range, credential: credential))
        } catch let error as BillingError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}

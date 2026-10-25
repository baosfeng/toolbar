import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器（请求封装）

/// 请求封装 — 把 provider 的网络调用收敛为 `BillingOutcome`，失败统一映射为 `BillingError`。
///
/// 拆出原因：`BillingMonitor` 主体超过单文件 15 KiB 上限，按「主类 + 请求扩展」范式分离。
/// 成员由 `private` 放宽为 `internal`，供同模块的 `BillingMonitor` 主体调用。
extension BillingMonitor {

    // MARK: - 刷新调度

    /// 一次刷新的目标 — 由调度按到期结果组装，主类只负责发起与合并
    struct FetchTarget: Sendable {
        /// provider 实现（注册表里的实例）
        let provider: any BillingProvider
        /// 该 provider 的凭据
        let credential: String
        /// 该 provider 当前选中的用量范围
        let range: BillingRange
        /// 稳定标识
        let id: String
        /// 本次请求代次（结果过期判定用）
        let generation: Int
    }

    /// 收集本次到期需要刷新的 provider — 每个 provider 按各自间隔独立节流
    ///
    /// 跳过条件：未配置凭据 / 正在请求中（force 也不重复打同一个 provider）。
    /// 间隔取全局下限与 provider 建议值的较大者（OpenCode Go 5 分钟、Ollama 60 秒）。
    func collectFetchTargets(now: Date, force: Bool) -> [FetchTarget] {
        var targets: [FetchTarget] = []
        for index in states.indices where states[index].isConfigured {
            let id = states[index].descriptor.id
            guard !states[index].isLoading,
                  let provider = registry.provider(id: id),
                  let credential = credentialStore.credential(for: id) else { continue }
            guard BillingRefreshScheduler.isDue(now: now,
                                                lastAttempt: lastAttempts[id],
                                                providerMinimum: provider.minimumRefreshInterval,
                                                force: force) else { continue }
            lastAttempts[id] = now
            let generation = nextGeneration(for: id)
            states[index].isLoading = true
            states[index].errorMessage = nil
            targets.append(FetchTarget(provider: provider, credential: credential,
                                       range: states[index].range, id: id,
                                       generation: generation))
        }
        return targets
    }

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
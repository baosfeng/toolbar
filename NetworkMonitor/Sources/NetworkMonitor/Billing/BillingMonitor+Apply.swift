import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器（结果合并）

/// 并发结果的合并与失败处理 —— 从 `BillingMonitor` 主体拆出（主文件接近 15 KiB 上限，
/// 而多实例注资需要新增存储属性与初始化参数）
///
/// 语义保持不变：成功项覆盖，失败项保留上次成功数据并记录错误文案。
extension BillingMonitor {

    /// 合并并发结果：成功项覆盖，失败项保留上次成功数据并记录错误文案
    func apply(results: [ProviderFetchResult], targets: [FetchTarget]) {
        var rateLimited: TimeInterval?
        for result in results {
            guard let index = states.firstIndex(where: { $0.descriptor.id == result.id }) else { continue }
            // 期间切换了范围 / 清除了凭据：丢弃本次结果，由更新的请求接管
            guard let target = targets.first(where: { $0.id == result.id }),
                  generations[result.id] == target.generation else { continue }
            states[index].isLoading = false

            var failure: BillingError?
            switch result.balance {
            case .success(let value):
                states[index].balance = value
                // 余额成功就算「刷新成功」：用量接口失败（如 Open Design 的解析 400）
                // 不该让卡头一直写「未刷新」—— 那会让「刚拉到额度」被读成「根本没查」
                states[index].lastUpdated = Date()
                alertService?.handle(balance: value,
                                     providerID: result.id,
                                     providerName: states[index].descriptor.displayName)
            case .failure(let error):
                failure = error
            }
            switch result.usage {
            case .some(.success(let value)):
                states[index].usage = value
            case .some(.failure(let error)):
                if failure == nil { failure = error }
            case .none:
                // provider 不支持用量明细：不发起请求，也不把它当失败
                states[index].usage = nil
            }

            if let failure {
                handle(failure: failure, providerID: result.id)
                if case .rateLimited(let retryAfter) = failure {
                    rateLimited = max(rateLimited ?? 0, retryAfter ?? Self.defaultRetryDelay)
                }
            } else {
                states[index].lastUpdated = Date()
                states[index].errorMessage = nil
                // 成功也留一条 debug：生产日志里没有额度数值时，无法判断「面板没数据」是哪一环
                if let balance = states[index].balance {
                    logger.debug("计费刷新成功（\(result.id)）：\(formatBalanceSummary(balance))")
                }
            }
        }
        if let rateLimited {
            retryNotBefore = Date().addingTimeInterval(rateLimited)
            logger.warning("计费查询触发限流，退避 \(Int(rateLimited)) 秒")
        } else {
            retryNotBefore = nil
        }
    }

    /// 单 provider 失败处理：429 记录退避，其余记日志（UI 展示 errorMessage）
    func handle(failure: BillingError, providerID: String) {
        if let index = states.firstIndex(where: { $0.descriptor.id == providerID }) {
            states[index].errorMessage = failure.userMessage
        }
        if case .rateLimited(let retryAfter) = failure {
            retryNotBefore = Date().addingTimeInterval(retryAfter ?? Self.defaultRetryDelay)
            logger.warning("计费查询触发限流，退避 \(Int(retryAfter ?? Self.defaultRetryDelay)) 秒")
        } else {
            logger.error("计费查询失败（\(providerID)）：\(failure.userMessage)")
        }
    }
}

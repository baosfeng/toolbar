import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器（实例增删改）

/// 实例管理 —— 设置页「额度 Provider」的「新增 / 重命名 / 删除实例」入口
///
/// 每次变更都同步三处：实例列表（`BillingInstanceStore`）、注册表（装饰器实例）、
/// 状态表（`rebuildStates`）。删除实例还会连带清凭据、启用键与提醒状态，
/// 避免同名新实例继承旧阈值记录。
extension BillingMonitor {

    /// 新增命名实例
    ///
    /// - Returns: 成功时返回新实例；失败时返回可读的 `BillingInstanceError`
    @discardableResult
    func addInstance(kindID: String, slug: String, title: String) -> Result<BillingInstance, BillingInstanceError> {
        guard let providerFactory else {
            return .failure(.notFound(kindID))
        }
        let instance: BillingInstance
        do {
            instance = try instances.add(kindID: kindID, slug: slug, title: title)
        } catch let error as BillingInstanceError {
            return .failure(error)
        } catch {
            return .failure(.invalidSlug)
        }
        if let base = providerFactory(kindID) {
            registry.register(BillingProviderInstance(base: base, instance: instance), instance: instance)
        }
        rebuildStates()
        emit()
        logger.info("已新增额度实例：\(instance.title)（\(instance.id)）")
        return .success(instance)
    }

    /// 重命名实例（只改展示名，凭据与提醒状态都保留）
    func renameInstance(_ instanceID: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let registration = registry.registrations.first(where: { $0.instance.id == instanceID }) else {
            return
        }
        instances.rename(instanceID: instanceID, title: trimmed)
        // 装饰器的 displayName 来自实例标题，需要重新注册一次
        registry.register(registration.provider, instance: registration.instance.renamed(trimmed))
        rebuildStates()
        emit()
        logger.info("已重命名额度实例：\(instanceID) → \(trimmed)")
    }

    /// 删除实例（默认实例不可删）
    ///
    /// 连带清理：凭据（避免留一条无人使用的密文）、启用键、提醒状态（避免同名新实例
    /// 继承旧阈值记录）、在途请求代次。
    func removeInstance(_ instanceID: String) {
        guard !BillingInstanceID.isDefault(instanceID),
              let instance = registry.instance(id: instanceID) else { return }
        credentialStore.setCredential(nil, for: instanceID)
        preferences.removeEnabled(for: instanceID)
        alertService?.clearAlerts(for: instanceID)
        try? instances.remove(instanceID: instanceID)
        registry.unregister(instanceID: instanceID)
        _ = nextGeneration(for: instanceID)
        lastAttempts[instanceID] = nil
        rebuildStates()
        emit()
        logger.info("已删除额度实例：\(instance.title)（\(instanceID)），凭据与提醒状态一并清除")
    }
}

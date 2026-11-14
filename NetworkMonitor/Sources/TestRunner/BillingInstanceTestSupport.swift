import Foundation
import NetworkMonitorCore

// MARK: - 多实例测试替身

/// 测试用 provider 桩（只实现协议必需成员，能力位可配置）
///
/// 多实例相关测试共用：`BillingInstanceTests` 用它验证装饰器与注册表，
/// `BillingInstanceMigrationTests` 用它验证默认实例的能力位转发。
struct InstanceStubProvider: BillingProvider {
    let id: String
    let displayName: String
    var symbolName: String { "circle" }
    var supportsModelBreakdown: Bool { true }
    var supportsUsage: Bool { usageSupport }
    var minimumRefreshInterval: TimeInterval { interval }
    var credentialHint: String { "Stub Key" }

    private let usageSupport: Bool
    private let interval: TimeInterval

    init(id: String, displayName: String, supportsUsage: Bool = true, minimumRefreshInterval: TimeInterval = 0) {
        self.id = id
        self.displayName = displayName
        self.usageSupport = supportsUsage
        self.interval = minimumRefreshInterval
    }

    func fetchBalance(credential: String) async throws -> BillingBalance {
        BillingBalance(included: BillingIncludedBalance(remainingUSD: Double(credential.count),
                                                        allowanceUSD: 100))
    }

    func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        BillingUsage(range: range, granularity: .day, start: Date(), end: Date(),
                     totals: BillingMetrics(), buckets: [])
    }
}

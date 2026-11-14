import Foundation
import NetworkMonitorCore

// MARK: - 开机自启动登记自愈

/// 假登记器：可控系统侧状态，记录注册 / 注销次数，并可注入注册失败
private final class FakeLoginItemRegistrar: LaunchAtStartupRegistering, @unchecked Sendable {
    var registration: LaunchAtStartupRegistration
    /// 注册次数（断言「只登记一次」用）
    private(set) var registerCount = 0
    /// 注销次数（断言「启动时不擅自注销」用）
    private(set) var unregisterCount = 0
    /// 注入注册失败
    var registerError: Error?

    init(registration: LaunchAtStartupRegistration) {
        self.registration = registration
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        registration = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        registration = .notRegistered
    }
}

/// 注入用的注册失败
private struct FakeRegisterError: Error, LocalizedError {
    var errorDescription: String? { "模拟系统拒绝登记" }
}

/// 静默日志：只验证行为，不回显预期内的失败日志
private final class SilentLogger: LoggingService, @unchecked Sendable {
    func log(_ level: LogLevel, _ message: String) {}
}

/// 开机自启动自愈 — 判定矩阵 + 隔离偏好 suite 上的端到端对账
func runLaunchAtStartupTests() {
    print("\n🧪 Testing 开机自启动登记自愈...")

    // MARK: 纯判定：偏好 × 系统侧四档
    assertEqual(LaunchAtStartupReconciler.decision(preferenceEnabled: true, registration: .enabled), .skip,
                "偏好开 + 已登记 → 不动")
    assertEqual(LaunchAtStartupReconciler.decision(preferenceEnabled: true, registration: .requiresApproval), .skip,
                "偏好开 + 等用户批准 → 不动（不把开关弹回关）")
    assertEqual(LaunchAtStartupReconciler.decision(preferenceEnabled: true, registration: .notRegistered), .register,
                "偏好开 + 未登记 → 重新登记")
    assertEqual(LaunchAtStartupReconciler.decision(preferenceEnabled: true, registration: .notFound), .register,
                "偏好开 + 系统找不到登记项（换过包路径）→ 重新登记")
    assertEqual(LaunchAtStartupReconciler.decision(preferenceEnabled: false, registration: .notRegistered), .skip,
                "偏好关 → 不动")
    assertEqual(LaunchAtStartupReconciler.decision(preferenceEnabled: false, registration: .enabled), .skip,
                "偏好关 + 已登记 → 启动时不擅自注销")

    // MARK: 端到端（隔离偏好 suite）：偏好 true + 未登记的迁移现场
    let key = "launchAtStartup"
    let suiteName = "com.example.NetworkMonitor.test.launchAtStartup"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let storage = UserDefaultsStorage(defaults: defaults)
    storage.set(true, forKey: key)

    let registrar = FakeLoginItemRegistrar(registration: .notFound)
    let reconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                               registrar: registrar, logger: SilentLogger())
    assertEqual(reconciler.isEnabled, true, "迁移现场：偏好仍是「用户想开」")
    assertEqual(reconciler.reconcileAtLaunch(), .registered, "偏好开 + 未登记 → 自愈重新登记")
    assertEqual(registrar.registerCount, 1, "只登记一次")
    assertEqual(registrar.registration, .enabled, "系统侧状态变已登记")
    assertEqual(storage.bool(forKey: key), true, "自愈成功后偏好保持为开")

    // 幂等：第二次启动不再重复登记
    assertEqual(reconciler.reconcileAtLaunch(), .skipped, "已登记后再次启动 → 不动")
    assertEqual(registrar.registerCount, 1, "不会重复登记")

    // MARK: 失败回滚：注册抛错 → 偏好回滚为关
    let failingRegistrar = FakeLoginItemRegistrar(registration: .notRegistered)
    failingRegistrar.registerError = FakeRegisterError()
    storage.set(true, forKey: key)
    let failingReconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                                      registrar: failingRegistrar, logger: SilentLogger())
    guard case .rolledBack = failingReconciler.reconcileAtLaunch() else {
        print("❌ 重新登记失败时应返回 rolledBack")
        exit(1)
    }
    print("✅ 重新登记失败 → 返回 rolledBack（并记 error 日志）")
    assertEqual(storage.bool(forKey: key), false,
                "回滚后偏好为关：设置页不会显示一个不会生效的「已开启」")

    // MARK: 偏好为关：启动阶段不碰系统状态
    storage.set(false, forKey: key)
    let offRegistrar = FakeLoginItemRegistrar(registration: .enabled)
    let offReconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                                  registrar: offRegistrar, logger: SilentLogger())
    assertEqual(offReconciler.reconcileAtLaunch(), .skipped, "偏好关 → 启动自愈不动")
    assertEqual(offRegistrar.registerCount, 0, "不登记")
    assertEqual(offRegistrar.unregisterCount, 0, "启动时不会替用户注销登记")

    // MARK: 等用户批准：保持偏好，不重新登记
    storage.set(true, forKey: key)
    let pendingRegistrar = FakeLoginItemRegistrar(registration: .requiresApproval)
    let pendingReconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                                      registrar: pendingRegistrar, logger: SilentLogger())
    assertEqual(pendingReconciler.reconcileAtLaunch(), .skipped, "待批准 → 不重复登记")
    assertEqual(pendingRegistrar.registerCount, 0, "待批准时不重复登记")
    assertEqual(storage.bool(forKey: key), true, "待批准时偏好保持为开")

    // MARK: 手动切换的失败回滚（既有行为不回归）
    storage.set(false, forKey: key)
    let toggleRegistrar = FakeLoginItemRegistrar(registration: .notRegistered)
    toggleRegistrar.registerError = FakeRegisterError()
    let toggleReconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                                     registrar: toggleRegistrar, logger: SilentLogger())
    assertEqual(toggleReconciler.setEnabled(true), false, "打开开关失败 → 返回 false")
    assertEqual(storage.bool(forKey: key), false, "打开失败 → 偏好回滚为关")

    defaults.removePersistentDomain(forName: suiteName)
}

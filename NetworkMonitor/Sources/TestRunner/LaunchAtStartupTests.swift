import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

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

    // MARK: 开关显示态 = 系统登记态（三入口统一判据）
    //
    // 用户口径「开机自启动很多地方都不统一」：通用页原来读偏好、系统权限页读登记态，
    // 同一时刻能显示相反结论。显示态一律以登记态为准，偏好键只补「待批准」这一档。
    assertEqual(LaunchAtStartupReconciler.switchState(preferenceEnabled: true, registration: .enabled),
                true, "已登记 → 开关开（与偏好无关）")
    assertEqual(LaunchAtStartupReconciler.switchState(preferenceEnabled: false, registration: .enabled),
                true, "偏好关但系统已登记 → 仍显示开（系统侧才是真相）")
    assertEqual(LaunchAtStartupReconciler.switchState(preferenceEnabled: true, registration: .notRegistered),
                false, "偏好开但系统没登记 → 显示关（旧包残留注册的迁移现场）")
    assertEqual(LaunchAtStartupReconciler.switchState(preferenceEnabled: true, registration: .notFound),
                false, "系统找不到登记项 → 显示关")
    assertEqual(LaunchAtStartupReconciler.switchState(preferenceEnabled: true, registration: .requiresApproval),
                true, "待批准 + 偏好开 → 开关保持开（标「待批准」，不弹回关）")
    assertEqual(LaunchAtStartupReconciler.switchState(preferenceEnabled: false, registration: .requiresApproval),
                false, "待批准 + 偏好关 → 开关关（注册失败回滚后不得弹回开）")

    // MARK: 三入口共用的显示口径（UI 库纯结构：开/关 + 副标题）
    let enabledPresentation = LaunchItemPresentation(registration: .enabled, preferenceEnabled: true)
    assertEqual(enabledPresentation.isOn, true, "已登记 → 开关开")
    assertContains(enabledPresentation.subtitle, AppIdentity.displayName, "已登记副标题带产品名")
    assertEqual(LaunchItemPresentation(registration: .notRegistered, preferenceEnabled: true).isOn,
                false, "系统没登记 → 开关关（哪怕偏好还是开）")
    let pendingOn = LaunchItemPresentation(registration: .requiresApproval, preferenceEnabled: true)
    assertEqual(pendingOn.isOn, true, "待批准 + 偏好开 → 开关开")
    assertContains(pendingOn.subtitle, "批准", "待批准副标题说明等用户去系统设置点一下")
    let pendingOff = LaunchItemPresentation(registration: .requiresApproval, preferenceEnabled: false)
    assertEqual(pendingOff.isOn, false, "待批准 + 偏好关 → 开关关")
    assertContains(pendingOff.subtitle, "残留", "残留登记不能说得像已启用")
    let rolledBack = LaunchItemPresentation(registration: .notRegistered, preferenceEnabled: false,
                                            failureReason: "模拟系统拒绝登记")
    assertContains(rolledBack.subtitle, "模拟系统拒绝登记", "回滚原因写进副标题")
    assertEqual(LaunchItemPresentation(registration: .notRegistered, preferenceEnabled: false).subtitle,
                "当前未登记开机自启动", "没发生过回滚不编原因")

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
    assertEqual(reconciler.isPreferenceEnabled, true, "迁移现场：偏好仍是「用户想开」")
    assertEqual(reconciler.isEnabled, false, "迁移现场：开关显示关（系统侧没登记，偏好不算数）")
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
    // 对账读偏好、开关读登记态：两者可以不同，但各自口径必须稳定
    assertEqual(offReconciler.isEnabled, true, "偏好关 + 系统已登记 → 开关仍显示开")

    // MARK: 注册失败回滚后开关不弹回开（回滚只管偏好，界面按登记态重算）
    let rollbackRegistrar = FakeLoginItemRegistrar(registration: .notRegistered)
    rollbackRegistrar.registerError = FakeRegisterError()
    storage.set(false, forKey: key)
    let rollbackReconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                                       registrar: rollbackRegistrar,
                                                       logger: SilentLogger())
    assertEqual(rollbackReconciler.setEnabled(true), false, "注册失败 → 返回 false")
    assertEqual(rollbackReconciler.isPreferenceEnabled, false, "偏好已回滚为关")
    assertEqual(rollbackReconciler.isEnabled, false, "开关按登记态显示关（与副标题的回滚说明一致）")
    // 待批准 + 偏好关：注册失败时系统侧可能留下待批准残留，同样不得显示为开
    let pendingRollback = FakeLoginItemRegistrar(registration: .requiresApproval)
    storage.set(false, forKey: key)
    let pendingRollbackReconciler = LaunchAtStartupReconciler(storage: storage, key: key,
                                                              registrar: pendingRollback,
                                                              logger: SilentLogger())
    assertEqual(pendingRollbackReconciler.isEnabled, false,
                "待批准残留 + 偏好关 → 开关保持关")

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

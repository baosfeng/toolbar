import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（局域网互传装配）

/// 互传链路装配 — 从 `AppCoordinator.swift` 拆出
///
/// 拆出原因：主文件因新增计费 provider 注册后超过单文件 15 KiB 规范上限；
/// 互传装配与组合根主流程无关，独立文件后主流程更短。
/// 跨文件访问的 `transferController` 由 private 放宽为 internal。
extension AppCoordinator {

    /// 装配传输服务：设备表 + 发现层 + HTTP 服务 + 面板控制器
    func makeTransferController() -> TransferController {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let identity = LocalIdentity.makeDefault(port: Int(TransferProtocol.defaultPorts[0]),
                                                 appVersion: appVersion)
        let registry = DeviceRegistry()
        let configuration = TransferService.Configuration(
            receiveDirectory: TransferService.Configuration.defaultReceiveDirectory(),
            appVersion: appVersion)
        let preferences = TransferPreferences(storage: AppContext.shared.storage)
        let knownPeers = KnownPeerStore(storage: AppContext.shared.storage, logger: logger)
        let service = TransferService(identity: identity,
                                      registry: registry,
                                      configuration: configuration,
                                      preferences: preferences,
                                      knownPeers: knownPeers,
                                      logger: logger)
        let controller = TransferController(service: service, registry: registry,
                                            preferences: preferences, logger: logger)
        transferController = controller
        // 服务常驻：面板未打开也要能收发，启动在后台完成
        controller.start()
        return controller
    }
}

import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 多命令热键注册表

/// 全局热键注册表 — 在既有单热键中心之外支持「多条命令 → 各自组合键」
///
/// 与剪贴板的 GlobalHotKeyCenter 分开：后者只有一个注册位，这里按 id 管理任意条，
/// 两者共用 Carbon 事件通道但签名不同，互不干扰。
@MainActor
final class HotKeyRegistry {

    enum RegisterResult: Equatable {
        case success(id: UInt32)
        /// 组合键被占用
        case conflict
        /// 注册失败并带 OSStatus
        case failed(OSStatus)
    }

    /// Carbon 事件签名（'MONS'），与剪贴板热键的 'MONH' 区分
    private static let signature: OSType = 0x4D4F4E53

    private let logger: LoggingService
    private var nextID: UInt32 = 1
    private var actions: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    // MARK: - 注册与注销

    @discardableResult
    func register(_ combo: HotKeyCombo, action: @escaping () -> Void) -> RegisterResult {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode,
                                          combo.modifiers,
                                          EventHotKeyID(signature: Self.signature, id: id),
                                          GetEventDispatcherTarget(),
                                          0,
                                          &reference)
        guard status == noErr, let reference else {
            logger.warning("热键注册失败 \(combo.displayString) status=\(status)")
            return status == noErr ? .conflict : .failed(status)
        }
        references[id] = reference
        actions[id] = action
        logger.info("热键已注册：\(combo.displayString) id=\(id)")
        return .success(id: id)
    }

    func unregister(_ id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        actions.removeValue(forKey: id)
    }

    func unregisterAll() {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        actions.removeAll()
    }

    // MARK: - 事件通道

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let parameterStatus = GetEventParameter(event,
                                                    EventParamName(kEventParamDirectObject),
                                                    EventParamType(typeEventHotKeyID),
                                                    nil,
                                                    MemoryLayout<EventHotKeyID>.size,
                                                    nil,
                                                    &identifier)
            guard parameterStatus == noErr, identifier.signature == HotKeyRegistry.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<HotKeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { registry.fire(id: identifier.id) }
            return noErr
        }, 1, &eventType, context, &handlerRef)
        guard status == noErr else {
            logger.error("热键事件处理器安装失败 status=\(status)")
            return
        }
        eventHandlerRef = handlerRef
    }

    fileprivate func fire(id: UInt32) {
        actions[id]?()
    }
}

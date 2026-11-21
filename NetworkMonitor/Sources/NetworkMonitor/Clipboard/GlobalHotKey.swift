import AppKit
import Carbon
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 快捷键组合（App 侧适配）

/// 组合键值类型本身在 NetworkMonitorUI（`displayString` 这类展示口径可被 TestRunner 直接断言，
/// 也避免 Core 为了键码常量依赖 Carbon），这里只留绕不开 AppKit 的那一段翻译：
/// NSEvent 修饰键集合 → Carbon 位掩码（NetworkMonitorUI 不 import AppKit）。
extension HotKeyCombo {

    /// 由 NSEvent 修饰键转换（录制控件与冲突提示共用同一口径）
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

// MARK: - 全局热键注册中心

/// 全局热键中心 — 基于 Carbon RegisterEventHotKey 的全局快捷键注册
///
/// 注册失败（非 noErr 或引用为空，通常为组合键被其他 App 占用）不静默：
/// 返回冲突结果，由调用方引导用户去「系统设置 → 键盘 → 键盘快捷键」释放占用后重试。
@MainActor
final class GlobalHotKeyCenter {

    /// 注册结果
    enum RegisterResult: Equatable {
        case success
        /// 组合键已被占用（Carbon 未返回错误但引用为空）
        case conflict
        /// 注册失败并带 OSStatus
        case failed(OSStatus)
    }

    /// Carbon 事件签名（'MONH'）与固定热键 id
    private static let signature: OSType = 0x4D4F4E48
    private static let hotKeyIdentifier: UInt32 = 1

    private let logger: LoggingService
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// 当前已生效的组合键（注册失败时为 nil）
    private(set) var registeredCombo: HotKeyCombo?

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    /// 注册全局热键（重复调用会先注销旧的注册）
    /// - Returns: 注册结果；非 success 时由调用方给出冲突提示，禁止静默失败
    @discardableResult
    func register(_ combo: HotKeyCombo, action: @escaping () -> Void) -> RegisterResult {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let parameterStatus = GetEventParameter(event,
                                                    EventParamName(kEventParamDirectObject),
                                                    EventParamType(typeEventHotKeyID),
                                                    nil,
                                                    MemoryLayout<EventHotKeyID>.size,
                                                    nil,
                                                    &identifier)
            guard parameterStatus == noErr, identifier.signature == GlobalHotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon 事件处理器挂在主 RunLoop 的 dispatcher target 上，回调必然在主线程交付
            let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.fire() }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        guard installStatus == noErr else {
            logger.error("全局热键事件处理器安装失败 status=\(installStatus)")
            self.action = nil
            return .failed(installStatus)
        }
        eventHandlerRef = handlerRef

        var reference: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(combo.keyCode,
                                                 combo.modifiers,
                                                 EventHotKeyID(signature: Self.signature, id: Self.hotKeyIdentifier),
                                                 GetEventDispatcherTarget(),
                                                 0,
                                                 &reference)
        guard registerStatus == noErr, let reference else {
            // 注册失败：回滚已安装的事件处理器，避免残留
            if let handlerRef { RemoveEventHandler(handlerRef) }
            eventHandlerRef = nil
            self.action = nil
            logger.warning("全局热键注册失败 status=\(registerStatus)，组合键可能被其他应用占用：\(combo.displayString)")
            return registerStatus == noErr ? .conflict : .failed(registerStatus)
        }

        hotKeyRef = reference
        registeredCombo = combo
        logger.info("全局热键已注册：\(combo.displayString)")
        return .success
    }

    /// 注销当前全局热键（幂等）
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        registeredCombo = nil
        action = nil
    }

    /// 触发已注册动作（私有，仅供 Carbon 回调调用）
    fileprivate func fire() {
        action?()
    }
}

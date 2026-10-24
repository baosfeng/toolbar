import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 快捷键组合

/// 全局快捷键组合 — Carbon 键码 + Carbon 修饰键位掩码
///
/// 与偏好层共用：keyCode / modifiers 直接以整数持久化，避免平台枚举的编码不稳定。
struct HotKeyCombo: Equatable, Sendable {
    /// Carbon 虚拟键码（kVK_*）
    var keyCode: UInt32
    /// Carbon 修饰键位掩码（cmdKey / shiftKey / optionKey / controlKey）
    var modifiers: UInt32

    /// 默认唤起组合：⌥⌘V（keyCode 9 = kVK_ANSI_V）
    static let defaultPanelToggle = HotKeyCombo(keyCode: 9, modifiers: UInt32(cmdKey | optionKey))

    /// 是否带至少一个修饰键（单键不允许作为全局热键）
    var hasModifier: Bool { modifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey) != 0 }

    /// 展示文本，如 "⌥⌘V"（组合顺序固定为 ⌃⌥⇧⌘）
    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyLabel(keyCode)
    }

    /// 由 NSEvent 修饰键转换（录制控件与冲突提示共用同一口径）
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// 键码转展示字符（仅覆盖常用键，未知键码回退为「键码 N」）
    private static func keyLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "\u{60}"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_Space: return "空格"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        default: return "键码 \(keyCode)"
        }
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

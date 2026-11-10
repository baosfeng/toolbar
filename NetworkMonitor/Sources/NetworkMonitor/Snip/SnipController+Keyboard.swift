import AppKit
import CoreGraphics
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 覆盖层键盘（从编排主类拆出，守住单文件门禁）

/// CGEventTap 回调里用的桥（不持有业务逻辑，只把按键转回主线程）
///
/// 用 @unchecked Sendable：box 只在主线程被读写，回调线程只做一次派发。
final class SnipKeyboardTapBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var target: (any SnipKeyboardReceiving)?
    /// 输入框正在编辑时让按键透传给窗口（否则打不进字）
    private var passThrough = false

    func attach(_ target: any SnipKeyboardReceiving) {
        lock.lock(); self.target = target; lock.unlock()
    }

    func detach() {
        lock.lock(); target = nil; lock.unlock()
    }

    func setPassThrough(_ value: Bool) {
        lock.lock(); passThrough = value; lock.unlock()
    }

    /// 回调线程调用：这次按键该怎么处理
    ///
    /// 只有「覆盖层在屏 + 不在输入文字 + 命中白名单」才吞掉；
    /// 早期实现「tap 装着就吞一切」，于是截图界面把整个键盘扣住
    /// （⌘Tab / ⌘Q / ⌘空格失效），而文字输入框里敲字母又打不进字。
    func decision(keyCode: Int,
                  characters: String?,
                  modifiers: SnipKeyCommandResolver.Modifiers) -> SnipKeyboardRouting.Decision {
        lock.lock()
        let hasTarget = target != nil
        let isEditing = passThrough
        lock.unlock()
        return SnipKeyboardRouting.decision(hasTarget: hasTarget,
                                            isTextEditing: isEditing,
                                            keyCode: keyCode,
                                            characters: characters,
                                            modifiers: modifiers)
    }

    /// 回调线程调用：把按键转给主线程
    ///
    /// 字符由系统在回调线程解码后一起带过来：早期用「键码 → 字母」硬编码表，
    /// Dvorak / 非美式布局下按下的物理键与字母对不上，⌘C 之类的组合会解析错。
    func forward(keyCode: Int, characters: String?, flags: CGEventFlags) {
        lock.lock(); let target = self.target; lock.unlock()
        guard let target else { return }
        DispatchQueue.main.async {
            target.receiveSystemKey(keyCode: keyCode, characters: characters, flags: flags)
        }
    }
}

/// 能接收系统层按键的覆盖层（由 SnipController 实现）
@MainActor
protocol SnipKeyboardReceiving: AnyObject {
    func receiveSystemKey(keyCode: Int, characters: String?, flags: CGEventFlags)
}

extension SnipController {

    /// 覆盖层键盘兜底：系统层 CGEventTap + AppKit 本地监视器双通道
    ///
    /// 菜单栏 App（LSUIElement + 自签名）拿不到稳定的系统级前台：
    /// 窗口 isKeyWindow=true、NSApp.isActive=true，但键盘事件有时仍不派给覆盖层视图，
    /// 表现就是「覆盖层看得见、Esc 和回车时灵时不灵」。
    /// 因此优先装一条 CGEventTap（系统层取键，不要求本 App 当前台）；
    /// 没有输入监控权限时回落 NSEvent 本地监视器（要求本 App 是前台）。
    func installKeyboardFallback() {
        guard keyboardFallback == nil else { return }
        let bridge = SnipKeyboardTapBridge()
        bridge.attach(self)
        keyboardBridge = bridge
        if installEventTap(bridge) {
            logger.info("截图键盘通道：CGEventTap（系统层）")
        } else if !keyboardTapWarningShown {
            // 只在第一次提示：没有「输入监控」权限时 tap 必然失败，反复刷日志没有信息量
            keyboardTapWarningShown = true
            logger.warning("截图键盘通道：本地监视器（如需在非前台状态接键，请在系统设置里授予「输入监控」）")
        }
        // 本地监视器始终安装：tap 失效时它还能兜住（App 当前台时必然生效）
        keyboardFallback = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let overlay = self.keyboardTarget(for: event) else { return event }
            if overlay.hasActiveTextInput { return event }
            overlay.handleKeyEvent(event)
            return nil
        }
    }

    /// 安装 CGEventTap；返回是否成功
    private func installEventTap(_ bridge: SnipKeyboardTapBridge) -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(bridge).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            let bridge = Unmanaged<SnipKeyboardTapBridge>.fromOpaque(userData).takeUnretainedValue()
            // 系统因超时临时禁用 tap 时重新启用，否则接键会静默失效
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            // 字符口径由系统解码（字母键受输入法 / 键盘布局影响，不能硬编码键码表）
            let characters = SnipCGEventCharacters.text(of: event)
            let modifiers = SnipKeyCommandResolver.Modifiers(cgEventFlags: flags)
            switch bridge.decision(keyCode: keyCode, characters: characters, modifiers: modifiers) {
            case .ignore:
                return Unmanaged.passUnretained(event)
            case .passThrough:
                // 放行的键不往主线程派发：它们由窗口 / 系统正常处理，重复处理会变成「按一次发生两次」
                return Unmanaged.passUnretained(event)
            case .swallow:
                bridge.forward(keyCode: keyCode, characters: characters, flags: flags)
                return nil
            }
        }, userInfo: context) else {
            logger.warning("截图键盘通道：CGEventTap 创建失败（缺输入监控权限），回落本地监视器")
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 该事件应该交给哪个覆盖层：事件自带窗口就用那一屏，否则交首屏
    func keyboardTarget(for event: NSEvent) -> SnipOverlayView? {
        if let window = event.window, let match = overlays.first(where: { $0 === window }) {
            return match.overlayView
        }
        return overlays.first?.overlayView
    }

    func removeKeyboardFallback() {
        if let monitor = keyboardFallback {
            NSEvent.removeMonitor(monitor)
            keyboardFallback = nil
        }
        keyboardBridge?.detach()
        keyboardBridge = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            eventTapSource = nil
        }
    }

    /// 让已存在的覆盖层重新接管键盘（重复按热键、或被别的窗口抢走焦点后）
    func refocusOverlays() {
        guard let window = overlays.first else { return }
        window.present()
        logger.info("截图进行中，重新接管键盘焦点")
    }

    /// 截图失败时的可读原因（调用方据此给出用户可见提示）
    static func failureDescription(_ error: any Error) -> String {
        guard let capture = error as? SnipCaptureError else {
            return error.localizedDescription
        }
        switch capture {
        case .permissionDenied: return "缺少「屏幕录制」权限"
        case .noDisplays: return "系统没有可用屏幕"
        case .displayUnavailable(let id): return "屏幕 \(id) 当前不可捕获"
        case .systemTooOld: return "系统版本过低，不支持截图接口"
        case .captureFailed(let detail): return detail
        }
    }

    /// 失败提示：日志 + 系统提示音 + 轻提示条（截图键按下去没结果时必须有反馈）
    func fail(message: String) {
        logger.error("截图失败：\(message)")
        captures = []
        NSSound.beep()
        SnipFailureNotice.present(message: message, logger: logger)
    }
}

extension SnipController: SnipKeyboardReceiving {

    /// 系统层按键转成 NSEvent 后走与窗口 keyDown 相同的处理路径
    func receiveSystemKey(keyCode: Int, characters: String?, flags: CGEventFlags) {
        guard let overlay = overlays.first?.overlayView ?? nil else { return }
        guard !overlay.hasActiveTextInput else { return }
        keyboardBridge?.setPassThrough(overlay.hasActiveTextInput)
        var modifierFlags: NSEvent.ModifierFlags = []
        if flags.contains(.maskShift) { modifierFlags.insert(.shift) }
        if flags.contains(.maskControl) { modifierFlags.insert(.control) }
        if flags.contains(.maskAlternate) { modifierFlags.insert(.option) }
        if flags.contains(.maskCommand) { modifierFlags.insert(.command) }
        guard let event = NSEvent.keyEvent(with: .keyDown,
                                           location: .zero,
                                           modifierFlags: modifierFlags,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: overlay.window?.windowNumber ?? 0,
                                           context: nil,
                                           characters: characters ?? SnipKeyCharacters.text(for: keyCode),
                                           charactersIgnoringModifiers: characters ?? SnipKeyCharacters.text(for: keyCode),
                                           isARepeat: false,
                                           keyCode: UInt16(keyCode)) else { return }
        overlay.handleKeyEvent(event)
    }
}

/// 键码 → 字符（兜底用：系统没给字符时（部分输入法 / 特殊键）仍能补上）
enum SnipKeyCharacters {
    static func text(for keyCode: Int) -> String {
        switch keyCode {
        case 53: return "\u{1B}"
        case 36, 76: return "\r"
        case 49: return " "
        case 43: return ","
        case 47: return "."
        case 48: return "\t"
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 13: return "w"
        case 8: return "c"
        case 15: return "r"
        case 17: return "t"
        case 6: return "z"
        default: return ""
        }
    }
}

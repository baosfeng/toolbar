import AppKit
import CoreGraphics
import NetworkMonitorCore
import QuartzCore

// MARK: - 事件 tap 与回调

/// tap 的安装 / 拆除与回调判据 —— 从 `ScrollSmoothingEngine` 拆出（守住单文件门禁）
///
/// 这一段的职责只有一件：**决定要不要接管这条事件**。所有「不确定」都返回
/// 「不接管」——它是全局输入路径上唯一的闸门，判错的代价是系统滚动被吞掉。
extension ScrollSmoothingEngine {

    // MARK: - 事件 tap

    /// 安装事件 tap（失败返回 false，调用方回落 fail-open）
    /// internal：拆到扩展文件后跨文件调用（同 target 内）
    func installTap() -> Bool {
        let mask = eventMask()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: scrollSmoothingTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        handles.tap = tap
        handles.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 关心的位：滚轮 + 两类「tap 被禁用」通知
    ///
    /// 禁用通知不在监听掩码里也常会送达，但显式带上不依赖实现细节：
    /// 收不到它就没法重新启用 tap，系统滚动会卡在「被吞掉」的状态。
    func eventMask() -> CGEventMask {
        let scrollWheel = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let timeout = CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
        let userInput = CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        return scrollWheel | timeout | userInput
    }

    /// 拆除 tap（幂等）
    /// internal：拆到扩展文件后跨文件调用（同 target 内）
    func removeTap() {
        if let source = handles.source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = handles.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        handles.source = nil
        handles.tap = nil
    }

    // MARK: - 回调（主线程）

    /// 回调入口（C 回调只传原始指针进来：不让非 Sendable 的 CGEvent 跨隔离域）
    ///
    /// - Returns: true = 吞掉原始事件（已排入平滑队列）
    func handle(rawType: UInt32, eventAddress: Int) -> Bool {
        guard let type = CGEventType(rawValue: rawType),
              let pointer = UnsafeMutableRawPointer(bitPattern: eventAddress) else {
            return false
        }
        let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
        return handle(type: type, event: event)
    }

    /// tap 回调本体 —— 返回 true 表示吞掉原始事件
    ///
    /// internal 是为了让同 target 的测试替身直接驱动判据（不装真 tap）。
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisabled(type: type)
            return false
        case .scrollWheel:
            break
        default:
            return false
        }

        guard state == .running else { return false }

        // 自己回投的事件：必须放行，否则会再被拆一次（自我放大的死循环）
        if ScrollEventClassifier.isOwnInjectedEvent(
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)) {
            return false
        }

        // 触控板 / 妙控鼠标（带 phase）/ 惯性滑行（momentum）/ 连续滚动：一律不接管
        guard ScrollEventClassifier.isSmoothableMouseWheel(
            phase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0) else {
            return false
        }

        let vertical = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let horizontal = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        guard vertical != 0 || horizontal != 0 else { return false }

        // 走到这里说明 tap 真的在处理事件：健康计数清零
        health.recordHealthyEvent()
        enqueue(vertical: vertical, horizontal: horizontal, flags: event.flags)
        return true
    }

    /// tap 被系统禁用：先重新启用，连续第 3 次则停用整个功能
    /// internal：拆到扩展文件后跨文件调用（同 target 内）
    func handleTapDisabled(type: CGEventType) {
        let action = health.recordDisable()
        let reason = type == .tapDisabledByTimeout ? "回调超时" : "用户输入"
        switch action {
        case .reenable:
            logger.warning("事件 tap 被系统禁用（\(reason)），第 \(health.consecutiveDisables) 次，重新启用")
            if let tap = handles.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .giveUp:
            logger.error("事件 tap 连续 \(ScrollTapHealth.maximumConsecutiveDisables) 次被系统禁用（\(reason)），"
                         + "自动停用鼠标滚轮平滑，滚动恢复系统原生行为")
            didGiveUp = true
            state = .stoppedAfterRepeatedDisables
            stopDisplayLink()
            pendingFrames.removeAll()
            // 不在自己的回调里销毁 tap：下一轮 run loop 收尾
            Task { @MainActor [weak self] in self?.removeTap() }
        }
    }
}

// MARK: - CF 句柄

/// tap 句柄容器 —— 纯 CF 层，非隔离持有
///
/// 只为一件事存在：让 `ScrollSmoothingEngine.deinit`（nonisolated）也能拆掉 tap。
/// 不碰 UI、不带业务状态，@unchecked Sendable 的约定是「只在主线程读写」。
final class ScrollSmoothingTapHandles: @unchecked Sendable {
    var tap: CFMachPort?
    var source: CFRunLoopSource?
}

// MARK: - tap 回调

/// C 回调入口 —— 只做三件事：取回引擎、确认在主线程、回到 @MainActor 处理
///
/// 任何一步不成立都原样放行：这条路径上「不接管」永远比「吞掉」安全。
private func scrollSmoothingTapCallback(proxy: CGEventTapProxy,
                                        type: CGEventType,
                                        event: CGEvent,
                                        refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    // tap 挂在主 run loop 上，回调本就在主线程；万一不是，原样放行而不是硬闯 @MainActor
    guard Thread.isMainThread else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<ScrollSmoothingEngine>.fromOpaque(refcon).takeUnretainedValue()
    let eventAddress = Int(bitPattern: Unmanaged.passUnretained(event).toOpaque())
    let rawType = type.rawValue
    let consumed = MainActor.assumeIsolated {
        engine.handle(rawType: rawType, eventAddress: eventAddress)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
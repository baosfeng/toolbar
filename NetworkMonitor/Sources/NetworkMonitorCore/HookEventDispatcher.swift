import Foundation

// MARK: - Hook 事件分发器

/// Hook 事件分发器 — 按事件类型路由到已注册的处理器
///
/// 注册表语义：
/// - `register` 时 `handledTypes` 为空集的处理器接收**所有**事件（全局处理器）
/// - 其余处理器按声明的事件类型精确匹配
/// - 同一事件的多个处理器按**注册顺序**同步执行（保证写库/通知等先后依赖）
///
/// 线程安全：注册与分发通过内部锁保护，可在任意队列调用。
public final class HookEventDispatcher: @unchecked Sendable {
    /// 处理器注册表：事件类型 → 处理器列表；`nil` 键为全局处理器
    private var handlers: [ReasonixHookEventType?: [any HookEventHandler]] = [:]
    private let lock = NSLock()

    public init() {}

    /// 注册处理器（线程安全）
    /// - Parameter handler: 处理器；`handledTypes` 为空集时接收所有事件
    public func register(_ handler: any HookEventHandler) {
        lock.lock()
        defer { lock.unlock() }

        if handler.handledTypes.isEmpty {
            handlers[nil, default: []].append(handler)
        } else {
            for type in handler.handledTypes {
                handlers[type, default: []].append(handler)
            }
        }
    }

    /// 分发事件到匹配的处理器（按注册顺序同步执行）
    /// - Parameter event: 已解析并补全的事件
    public func dispatch(_ event: ReasonixHookEvent) {
        let targets: [any HookEventHandler]
        lock.lock()
        targets = (handlers[event.eventType] ?? []) + (handlers[nil] ?? [])
        lock.unlock()

        for handler in targets {
            handler.handle(event)
        }
    }
}

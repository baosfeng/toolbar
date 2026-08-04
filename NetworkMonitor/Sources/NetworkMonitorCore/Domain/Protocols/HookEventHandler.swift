import Foundation

// MARK: - Hook 事件处理器

/// Hook 事件处理器协议 — 事件处理逻辑的 SPI 扩展点
///
/// 新增事件处理逻辑时实现本协议并注册到 `HookEventDispatcher`，
/// 无需修改监听器核心与分发逻辑。
public protocol HookEventHandler: AnyObject, Sendable {
    /// 声明处理的事件类型；**空集表示处理所有事件**
    var handledTypes: Set<ReasonixHookEventType> { get }

    /// 处理事件（在事件处理队列上同步调用，按注册顺序执行）
    func handle(_ event: ReasonixHookEvent)
}

import Foundation

// MARK: - 截图键盘闸门（编辑态信号与白名单裁决的同一次读取）

/// 系统层按键通道的编辑态闸门（纯逻辑，可单测）
///
/// 为什么单独抽出来：编辑态信号早先写在接收端 `receiveSystemKey` 里，
/// 而那段被 `guard !hasActiveTextInput else { return }` 挡在前面，于是那一行永远写 false——
/// 输入框里 a / s / d / w / c / r / 退格 / 回车全被白名单吞掉又无人消费
/// （用户口径：「敲键盘看不到字、退格删不掉」）。判定函数 `SnipKeyboardRouting` 本身是对的，
/// 错的只是编辑态从未被写进去：纯函数测得到、真通道走不到。
///
/// 现在把「通道有无目标 + 是否编辑」收进这个类：主线程只调用 `setEditing`，
/// tap 的回调线程只调用 `decision`，两者由锁隔开。编辑态不再依赖
/// 「先收到一个被吞掉的键」才同步——按下第一个键之前闸门就已经打开。
public final class SnipKeyboardGate: @unchecked Sendable {

    private let lock = NSLock()
    private var editing = false

    public init() {}

    /// 输入框是否正在编辑（覆盖层里存在尺寸框或文字框）
    public var isEditing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return editing
    }

    /// 输入框装上 / 卸下时调用（主线程；由 SnipOverlayView 的编辑态收口处驱动）
    public func setEditing(_ value: Bool) {
        lock.lock()
        editing = value
        lock.unlock()
    }

    /// tap 回调线程调用：这次按键该怎么处理
    ///
    /// 编辑态在同一次加锁里读出，避免「读到有目标、读到未编辑」这种半拍组合
    /// 把输入框里的键判成截图指令。
    public func decision(hasTarget: Bool,
                         keyCode: Int,
                         characters: String?,
                         modifiers: SnipKeyCommandResolver.Modifiers) -> SnipKeyboardRouting.Decision {
        lock.lock()
        let editingNow = editing
        lock.unlock()
        return SnipKeyboardRouting.decision(hasTarget: hasTarget,
                                            isTextEditing: editingNow,
                                            keyCode: keyCode,
                                            characters: characters,
                                            modifiers: modifiers)
    }
}

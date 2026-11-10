import Foundation

// MARK: - 截图键盘拦截判定（纯逻辑，可单测）

/// 系统层按键通道该不该接管某个键
///
/// 覆盖层存在期间会装一条 CGEventTap（系统层取键，用于 App 不是前台时仍能接住 Esc / 回车）。
/// 早期实现只要 tap 装着就吞掉**所有** keyDown，于是截图界面里 ⌘Tab、⌘Q、⌘空格
/// 这些系统快捷键全部失效——覆盖层把整个键盘扣住了。
/// 这里把「该接管哪些键」写死成一张显式白名单，其余一律放行。
public enum SnipKeyboardInterception {

    /// 是否接管该按键
    ///
    /// 只接管覆盖层真有语义的键：取消 / 确认 / 显隐工具条 / 切窗口检测 / 历史循环 /
    /// 微调 / 取色与「复制、保存、贴图、撤销、重做、全选、旋转」这些 ⌘ 组合。
    /// 系统快捷键（⌘Tab、⌘Q、⌘空格、⌘W 等）不在白名单内，直接放行。
    public static func shouldIntercept(keyCode: Int,
                                       characters: String?,
                                       modifiers: SnipKeyCommandResolver.Modifiers) -> Bool {
        SnipKeyCommandResolver.resolve(keyCode: keyCode,
                                       characters: characters,
                                       modifiers: modifiers) != .none
    }
}

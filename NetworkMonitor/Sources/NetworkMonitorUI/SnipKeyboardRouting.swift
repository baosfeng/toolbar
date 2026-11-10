import Foundation

// MARK: - 截图键盘路由（纯逻辑，可单测）

/// 系统层按键通道对一次按键该怎么处理
///
/// 通道关闭（覆盖层已收掉）、正在输入文字、以及非白名单键都必须放行；
/// 只有「覆盖层在屏 + 不在编辑文字 + 命中白名单」才吞掉。
///
/// 早期实现只看「tap 装着就吞一切」，且编辑态判断写在接收端：
/// 于是文字标注输入框里敲 a / s / c / r 会被吞掉又没人消费——**字打不进去**。
public enum SnipKeyboardRouting {

    public enum Decision: Equatable {
        /// 覆盖层不在屏：不接管，也不转发
        case ignore
        /// 吞掉按键并转给覆盖层
        case swallow
        /// 放行给窗口 / 系统（输入文字时的字符、系统快捷键都走这条）
        case passThrough
    }

    public static func decision(hasTarget: Bool,
                                isTextEditing: Bool,
                                keyCode: Int,
                                characters: String?,
                                modifiers: SnipKeyCommandResolver.Modifiers) -> Decision {
        guard hasTarget else { return .ignore }
        guard !isTextEditing else { return .passThrough }
        let intercept = SnipKeyboardInterception.shouldIntercept(keyCode: keyCode,
                                                                characters: characters,
                                                                modifiers: modifiers)
        return intercept ? .swallow : .passThrough
    }
}

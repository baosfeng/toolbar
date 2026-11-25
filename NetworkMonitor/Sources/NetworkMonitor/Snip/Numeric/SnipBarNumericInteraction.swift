import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条上的数值交互（滚轮 / 双击）

/// 工具条两颗数值按钮（当前色 / 当前线宽）上滚轮与双击的判定
///
/// 单独成类型而不是写在 SnipToolBarView 里：SnipToolBarView 族已有四个文件，
/// 同族合计门禁只允许变小——按类名继续堆 +扩展 会一直撞这道门。
/// 这里只做「命中的那颗按钮代表哪个参数」+「滚了几格」+「是不是双击复位」三件判断，
/// 工具条只留一行转发，视图不再长身体。
@MainActor
enum SnipBarNumericInteraction {

    /// 命中的按钮代表哪个可调参数（nil = 这颗按钮不管数值）
    ///
    /// 与 Snipaste「指针停在哪个控件上决定滚轮语义」一致：
    /// 线宽按钮在文字工具下代表字号，颜色按钮代表透明度。
    static func param(for item: SnipBarItem, selectedTool: SnipTool?) -> SnipNumericParam? {
        switch item {
        case .width:
            return selectedTool == .text ? .fontSize : .lineWidth
        case .color:
            // 颜色按钮上滚 = 调透明度（官方在标注态就是这么做的）
            return .opacity
        default:
            return nil
        }
    }

    /// 一次滚轮要推进几步（余量累加在调用方持有）
    ///
    /// 与画布上滚轮共用同一份归一化口径（SnipScrollStepper），
    /// 否则同一台机器上「在画布上滚」与「在按钮上滚」手感会不一样。
    static func steps(for event: NSEvent, stepper: inout SnipScrollStepper) -> Int {
        stepper.feed(delta: event.scrollingDeltaY,
                     hasPreciseDeltas: event.hasPreciseScrollingDeltas,
                     isMomentum: event.momentumPhase != [])
    }

    /// 滚轮的调整意图（⌘ 快 / ⌥ 精）
    static func intent(for event: NSEvent) -> SnipNumericIntent {
        SnipNumericIntent.resolve(command: event.modifierFlags.contains(.command),
                                  option: event.modifierFlags.contains(.option))
    }
}

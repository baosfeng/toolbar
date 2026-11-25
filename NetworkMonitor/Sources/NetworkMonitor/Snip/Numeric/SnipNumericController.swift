import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 数值控制器（数值旋钮的唯一所有者）

/// 覆盖层里所有数值旋钮的读写、滚轮分流、读数反馈都归它
///
/// 为什么从 SnipOverlayView 的扩展改成独立类：数值调整是一套自成体系的行为
/// （参数表 / 步进 / 意图 / 滚轮归一 / 读数 / 输入 / 图形缩放），塞进视图的 +扩展
/// 只会让 SnipOverlayView 这个族越堆越大 —— 而同族合计门禁正是要拦这种「按类名堆文件」。
/// 现在视图只留两个触点：把当前状态喂进来（closures），把改动接回去。
@MainActor
final class SnipNumericController {

    // MARK: - 宿主注入的口子

    /// 读当前样式
    var readStyle: () -> SnipAnnotationStyle
    /// 写当前样式并触发回灌工具条 / 落偏好 / 重绘（由覆盖层实现，只此一条出口）
    var commitStyle: (SnipAnnotationStyle) -> Void
    /// 当前选中的标注下标（nil = 无选中）
    var selectedIndex: () -> Int?
    /// 读一条已绘标注
    var annotationAt: (Int) -> SnipAnnotation?
    /// 替换一条已绘标注
    var replaceAnnotation: (Int, SnipAnnotation) -> Void
    /// 当前工具（nil = 还在操作选区）
    var activeTool: () -> SnipTool?
    /// 是否已成立选区
    var hasSelection: () -> Bool
    /// 光标在本地点坐标里的位置（读数气泡按它定位）
    var pointerLocation: () -> CGPoint
    /// 覆盖层范围（气泡避让用）
    var viewBounds: () -> CGRect
    /// 挂读数气泡的父视图（由覆盖层提供，控制器不持有窗口）
    var hostView: () -> NSView?

    // MARK: - 会话状态

    /// 放宽为 internal(set)：读数与输入的扩展文件（+HUD）要写 editingParam
    var session = SnipNumericSession()
    /// 放宽为 internal：读数与输入的扩展文件（+HUD）要读写
    var hud: SnipNumericHUDView?
    /// 放宽为 internal：同上
    var hudTask: DispatchWorkItem?

    init(readStyle: @escaping () -> SnipAnnotationStyle,
         commitStyle: @escaping (SnipAnnotationStyle) -> Void,
         selectedIndex: @escaping () -> Int?,
         annotationAt: @escaping (Int) -> SnipAnnotation?,
         replaceAnnotation: @escaping (Int, SnipAnnotation) -> Void,
         activeTool: @escaping () -> SnipTool?,
         hasSelection: @escaping () -> Bool,
         pointerLocation: @escaping () -> CGPoint,
         viewBounds: @escaping () -> CGRect,
         hostView: @escaping () -> NSView?) {
        self.readStyle = readStyle
        self.commitStyle = commitStyle
        self.selectedIndex = selectedIndex
        self.annotationAt = annotationAt
        self.replaceAnnotation = replaceAnnotation
        self.activeTool = activeTool
        self.hasSelection = hasSelection
        self.pointerLocation = pointerLocation
        self.viewBounds = viewBounds
        self.hostView = hostView
    }

    // MARK: - 当前工具对应哪根旋钮

    /// 当前工具决定滚轮 / 1 2 / [ ] 调的是哪个参数
    ///
    /// 与 Snipaste 的「同一组键在不同工具下语义不同」一致：画笔调粗细、文字调字号、
    /// 马赛克调粒度、模糊调强度。工具条上「更多」里的工具同样适用。
    var activeParam: SnipNumericParam? {
        guard let tool = activeTool(), hasSelection() else { return nil }
        switch tool {
        case .text: return .fontSize
        case .mosaic: return .mosaicBlock
        case .blur: return .blurRadius
        default: return .lineWidth
        }
    }

    /// 读一个参数当前的值
    ///
    /// 字号缺省时回落旧公式 max(lineWidth*5,14)：用户从没调过字号时，
    /// 第一格滚轮应当从「他现在看到的那个大小」开始走，而不是从隐藏的 20 跳过去。
    func value(of param: SnipNumericParam) -> CGFloat {
        let style = readStyle()
        switch param {
        case .lineWidth: return style.lineWidth
        case .fontSize: return style.text.fontSize ?? max(style.lineWidth * 5, 14)
        case .opacity: return style.color.alpha
        case .mosaicBlock: return style.effect.mosaicBlock
        case .blurRadius: return style.effect.blurRadius
        case .magnifierZoom: return session.magnifierZoom
        }
    }

    /// 写一个参数的值（已夹取量化过）
    ///
    /// 只改**下一笔**的样式；是否同步到已选中的图形由调用方决定，
    /// 与 Snipaste「调的是这支笔，不是已经画好的那笔」的语义一致。
    private func write(_ value: CGFloat, to param: SnipNumericParam) {
        let clamped = param.quantized(value)
        switch param {
        case .magnifierZoom:
            session.magnifierZoom = clamped
            return
        default:
            break
        }
        var style = readStyle()
        switch param {
        case .lineWidth: style.lineWidth = clamped
        case .fontSize: style.text.fontSize = clamped
        case .opacity: style.color = style.color.withAlpha(clamped)
        case .mosaicBlock: style.effect.mosaicBlock = SnipEffectStyle.clampMosaic(clamped)
        case .blurRadius: style.effect.blurRadius = SnipEffectStyle.clampBlur(clamped)
        case .magnifierZoom: break
        }
        commitStyle(style)
    }

    // MARK: - 推进一步

    /// 按意图推进一个参数若干步；返回是否真的变了
    ///
    /// 返回值给调用方决定按键是否放行：已经到 40pt 还按加粗，应当把键交回系统，
    /// 而不是吞掉一个什么都不做的操作（吞键会让用户以为键盘失灵）。
    @discardableResult
    func adjust(_ param: SnipNumericParam, steps: Int, intent: SnipNumericIntent) -> Bool {
        let current = value(of: param)
        let next = SnipNumericStepper.step(current, param: param, steps: steps, intent: intent)
        guard abs(next - param.quantized(current)) > 0.0001 else { return false }
        write(next, to: param)
        showHUD(param, intent: intent)
        return true
    }

    /// 直接设一个绝对值（输入框 / 双击复位用）；返回是否真的变了
    @discardableResult
    func assign(_ param: SnipNumericParam, value newValue: CGFloat, showsHUD: Bool = true) -> Bool {
        let next = SnipNumericStepper.set(newValue, param: param)
        guard abs(next - param.quantized(value(of: param))) > 0.0001 else { return false }
        write(next, to: param)
        if showsHUD {
            showHUD(param, intent: .coarse)
        }
        return true
    }

    /// 回到该参数的默认值（双击复位）
    @discardableResult
    func reset(_ param: SnipNumericParam) -> Bool {
        assign(param, value: param.defaultValue)
    }

    // MARK: - 滚轮

    /// 滚轮统一入口：返回 true 表示已消费
    ///
    /// 四条通路按优先级排列，与 Snipaste 的「窗口 → 工具 → 有无选中 → 指针在哪个控件上」同构：
    /// 0. ⇧ = 整体缩放选中的图形（v2.11 同款）；⌃ = 调透明度；
    /// 1. 选中了标注 → 改这一条；2. 有工具 → 改该工具的参数；3. 都没选 → 调放大镜倍数。
    func handleScroll(_ event: NSEvent) -> Bool {
        let steps = session.scrollStepper.feed(delta: scrollDelta(of: event),
                                               hasPreciseDeltas: event.hasPreciseScrollingDeltas,
                                               isMomentum: event.momentumPhase != [])
        guard steps != 0 else { return false }
        let intent = SnipNumericIntent.resolve(
            command: event.modifierFlags.contains(.command),
            option: event.modifierFlags.contains(.option))
        if event.modifierFlags.contains(.shift), selectedIndex() != nil {
            return scaleSelected(by: steps)
        }
        if event.modifierFlags.contains(.control) {
            return adjust(.opacity, steps: steps, intent: .coarse)
        }
        if selectedIndex() != nil {
            return adjustSelected(by: steps, intent: intent)
        }
        if let param = activeParam {
            return adjust(param, steps: steps, intent: intent)
        }
        return adjust(.magnifierZoom, steps: steps, intent: intent)
    }

    /// 滚轮增量：按系统「自然滚动」偏好归一
    ///
    /// 关掉自然滚动（鼠标党常见）时 delta 方向是反的，不归一就会出现
    /// 「向下滚变粗、向上滚变细」，与工具条上 −/+ 的方向相反。
    private func scrollDelta(of event: NSEvent) -> CGFloat {
        let raw = event.scrollingDeltaY
        return event.isDirectionInvertedFromDevice ? -raw : raw
    }

    /// ⇧ + 滚轮：整体缩放选中的图形；返回是否消费了这次滚轮
    @discardableResult
    func scaleSelected(by steps: Int) -> Bool {
        guard let index = selectedIndex(), let current = annotationAt(index) else { return false }
        let (next, changed) = SnipAnnotationScaler.scaled(current, steps: steps)
        guard changed else { return false }
        replaceAnnotation(index, next)
        // 缩放没有对应的单一数值：借用「线宽」这一项显示缩放后的宽度，用户关心的是「变多大」
        showHUD(.lineWidth, intent: .coarse, overrideValue: next.boundingRect.width)
        return true
    }

    /// 改选中的那条标注
    ///
    /// 文字：改它的基准字号（fontScale 是另一层临时缩放，这里不动它，
    /// 否则连续滚轮会把两层叠在一起，用户再也回不到原大小）。
    /// 其余图形：改它自己的线宽。
    private func adjustSelected(by steps: Int, intent: SnipNumericIntent) -> Bool {
        guard let index = selectedIndex(), var annotation = annotationAt(index) else { return false }
        let isText = annotation.kind == .text
        let param: SnipNumericParam = isText ? .fontSize : .lineWidth
        let current = isText
            ? (annotation.style.text.fontSize ?? max(annotation.style.lineWidth * 5, 14))
            : annotation.style.lineWidth
        let next = SnipNumericStepper.step(current, param: param, steps: steps, intent: intent)
        guard abs(next - param.quantized(current)) > 0.0001 else { return false }
        if isText {
            annotation.style.text.fontSize = next
        } else {
            annotation.style.lineWidth = next
        }
        replaceAnnotation(index, annotation)
        showHUD(param, intent: intent)
        return true
    }
}

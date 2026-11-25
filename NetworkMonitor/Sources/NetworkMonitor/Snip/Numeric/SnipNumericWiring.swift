import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 数值控制器的装配

/// 把覆盖层的状态接到数值控制器上（控制器不反向持有视图类型，只拿闭包）
///
/// 十个闭包都指向 self：控制器是覆盖层的 `lazy var`，生命周期一致，
/// 因此用 unowned 而不是 weak —— weak 会让每次滚轮多一次解包，
/// 而这里不存在「控制器比视图活得久」的可能（它是视图的属性）。
extension SnipOverlayView {

    /// 装配数值控制器（首次访问 `numeric` 时执行一次）
    func makeNumericController() -> SnipNumericController {
        SnipNumericController(
            readStyle: { [unowned self] in self.currentStyle },
            commitStyle: { [unowned self] style in self.toolBarDidChangeStyle(style) },
            selectedIndex: { [unowned self] in self.selectedAnnotationIndex },
            annotationAt: { [unowned self] index in
                self.annotationStack.annotations.indices.contains(index)
                    ? self.annotationStack.annotations[index] : nil
            },
            replaceAnnotation: { [unowned self] index, annotation in
                guard self.annotationStack.annotations.indices.contains(index) else { return }
                self.annotationStack.replace(at: index, with: annotation)
                self.needsDisplay = true
            },
            activeTool: { [unowned self] in self.activeTool },
            hasSelection: { [unowned self] in self.state.phase == .selected },
            pointerLocation: { [unowned self] in self.pointer },
            viewBounds: { [unowned self] in self.bounds },
            hostView: { [unowned self] in self })
    }
}

import AppKit
import NetworkMonitorCore

// MARK: - 贴图窗右键菜单的动作出口

/// 菜单项 → 选择器映射 + 各菜单动作的实现
///
/// 从 PinWindow.swift 拆出：主文件只保留窗口自身的职责（尺寸 / 变换 / 键盘 / 滚动 / 棋盘底），
/// 菜单这一整块（映射表 + 十余个 @objc 出口）单独一份，两边都属于同一个类。
/// 映射表与动作必须同文件维护：锚点 `#selector(menuXxx)` 与实现分开就容易改一处漏一处。
extension PinWindow {

    /// 菜单项 → 响应选择器（枚举在 Core，不能带 Selector，映射只在这里维护一份）
    ///
    /// 跨文件可见性说明：由 PinWindow.swift 的 rightMouseDown 调用，故放宽为 internal。
    static func selector(for action: PinMenuAction) -> Selector {
        switch action {
        case .copy: return #selector(menuCopy)
        case .save: return #selector(menuSave)
        case .rotate: return #selector(menuRotate)
        case .mirrorHorizontal: return #selector(menuMirrorH)
        case .mirrorVertical: return #selector(menuMirrorV)
        case .grayscale: return #selector(menuGrayscale)
        case .invert: return #selector(menuInvert)
        case .thumbnail: return #selector(menuThumbnail)
        case .boardBackground: return #selector(menuToggleBoard)
        case .resetSizeAndAlpha: return #selector(menuResetAll)
        case .close: return #selector(menuClose)
        case .destroy: return #selector(menuDestroy)
        }
    }

    @objc private func menuCopy() { onCopy?(self) }
    @objc private func menuSave() { onSave?(self) }
    @objc private func menuRotate() { rotate(clockwise: true) }
    @objc private func menuMirrorH() { mirror(horizontal: true) }
    @objc private func menuMirrorV() { mirror(horizontal: false) }
    @objc private func menuGrayscale() { grayscale() }
    @objc private func menuInvert() { invert() }
    @objc private func menuThumbnail() { toggleThumbnail() }
    @objc private func menuToggleBoard() { setBoardBackground(!isBoardBackgroundEnabled) }
    @objc private func menuResetAll() { resetSizeAndAlpha() }
    @objc private func menuClose() { closeAndReport() }
    @objc private func menuDestroy() { destroy() }
}

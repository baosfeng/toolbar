import AppKit
import NetworkMonitorCore

// MARK: - 贴图窗口

/// 贴到屏幕上的浮窗 — 无边框、非激活式面板、置顶到 screenSaver 层级、跨 Space 与全屏 App
///
/// 四件套缺一不可：.nonactivatingPanel + level .screenSaver + collectionBehavior 四项 + 调用方保持
/// .accessory 激活策略；少任何一项都压不住别人的全屏窗口。
@MainActor
final class PinWindow: NSPanel {

    /// 回调：关闭（第二个参数为 true 表示销毁，不可恢复）
    var onClosed: ((PinWindow, Bool) -> Void)?
    /// 回调：请求复制当前图像
    var onCopy: ((PinWindow) -> Void)?
    /// 回调：请求另存为
    var onSave: ((PinWindow) -> Void)?

    private let imageView = NSImageView()
    private(set) var currentImage: CGImage
    /// 100% 尺寸（点）
    private(set) var baseSize: CGSize
    private(set) var currentScale: CGFloat = 1
    private(set) var isThumbnail = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage, initialSize: CGSize) {
        currentImage = image
        baseSize = initialSize
        super.init(contentRect: NSRect(origin: .zero, size: initialSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        imageView.frame = NSRect(origin: .zero, size: initialSize)
        imageView.image = NSImage(cgImage: image, size: initialSize)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        contentView = imageView
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            if event.modifierFlags.contains(.shift) { destroy() } else { closeAndReport() }
            return
        case 18, 19:
            rotate(clockwise: event.keyCode == 19)
            return
        case 20:
            mirror(horizontal: true)
            return
        case 21:
            mirror(horizontal: false)
            return
        default:
            break
        }
        switch event.charactersIgnoringModifiers {
        case "1": rotate(clockwise: true)
        case "2": rotate(clockwise: false)
        case "3": mirror(horizontal: true)
        case "4": mirror(horizontal: false)
        case "5": toggleThumbnail()
        default: super.keyDown(with: event)
        }
    }

    // MARK: - 滚轮：缩放 / 透明度

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            adjustAlpha(by: event.scrollingDeltaY * 0.03)
        } else {
            setScale(currentScale * (1 + event.scrollingDeltaY * 0.02))
        }
    }

    /// 以窗口中心为锚点缩放
    func setScale(_ scale: CGFloat) {
        let clamped = min(max(scale, 0.1), 10)
        guard abs(clamped - currentScale) > 0.0001 else { return }
        currentScale = clamped
        applySize(CGSize(width: baseSize.width * clamped, height: baseSize.height * clamped))
    }

    /// 固定尺寸缩略图：缩到 30%，再按一次还原
    func toggleThumbnail() {
        if isThumbnail {
            isThumbnail = false
            setScale(1)
        } else {
            isThumbnail = true
            setScale(0.3)
        }
    }

    // MARK: - 变换

    func rotate(clockwise: Bool) {
        guard let rotated = SnipImageTransform.rotated(currentImage, clockwise: clockwise) else { return }
        applyImage(rotated)
    }

    func mirror(horizontal: Bool) {
        guard let mirrored = SnipImageTransform.mirrored(currentImage, horizontal: horizontal) else { return }
        applyImage(mirrored)
    }

    func adjustAlpha(by delta: CGFloat) {
        alphaValue = min(max(alphaValue + delta, 0.1), 1)
    }

    private func applyImage(_ image: CGImage) {
        let screenScale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let pointSize = CGSize(width: CGFloat(image.width) / screenScale,
                               height: CGFloat(image.height) / screenScale)
        currentImage = image
        baseSize = pointSize
        imageView.image = NSImage(cgImage: image, size: pointSize)
        applySize(CGSize(width: pointSize.width * currentScale,
                         height: pointSize.height * currentScale))
    }

    private func applySize(_ size: CGSize) {
        var frame = self.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = size
        frame.origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        setFrame(frame, display: true)
    }

    // MARK: - 关闭与销毁

    func closeAndReport() {
        close()
        onClosed?(self, false)
    }

    func destroy() {
        close()
        onClosed?(self, true)
    }

    // MARK: - 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制图像", action: #selector(menuCopy), keyEquivalent: "").target = self
        menu.addItem(withTitle: "另存为…", action: #selector(menuSave), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "旋转 90°", action: #selector(menuRotate), keyEquivalent: "").target = self
        menu.addItem(withTitle: "水平镜像", action: #selector(menuMirrorH), keyEquivalent: "").target = self
        menu.addItem(withTitle: "缩略图", action: #selector(menuThumbnail), keyEquivalent: "").target = self
        menu.addItem(withTitle: "不透明度 100%", action: #selector(menuResetAlpha), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭（可恢复）", action: #selector(menuClose), keyEquivalent: "").target = self
        menu.addItem(withTitle: "销毁", action: #selector(menuDestroy), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: imageView)
    }

    @objc private func menuCopy() { onCopy?(self) }
    @objc private func menuSave() { onSave?(self) }
    @objc private func menuRotate() { rotate(clockwise: true) }
    @objc private func menuMirrorH() { mirror(horizontal: true) }
    @objc private func menuThumbnail() { toggleThumbnail() }
    @objc private func menuResetAlpha() { alphaValue = 1 }
    @objc private func menuClose() { closeAndReport() }
    @objc private func menuDestroy() { destroy() }
}

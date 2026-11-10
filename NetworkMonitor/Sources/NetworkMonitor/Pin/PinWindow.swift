import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

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
    /// 回调：请求复制纯文本（⌘⇧C；该贴图不是文本来源时返回 nil）
    var onCopyPlainText: ((PinWindow) -> String?)?

    /// 该贴图的来源纯文本（文本 / HTML / 文件路径贴图才有）
    ///
    /// 官方贴图键位表：⌘⇧C 复制纯文本（如果该贴图是由文本转换而来）。
    /// 贴图窗只持有位图，来源文本必须由贴图时一并记下，否则这个出口无从实现。
    var sourceText: String?

    private let imageView = NSImageView()
    /// 内容视图：双击 / 中键必须在这里判，否则会被窗口拖动吃掉（见 PinContentView）
    private let container = PinContentView(frame: .zero)
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
        container.frame = NSRect(origin: .zero, size: initialSize)
        container.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        // 官方贴图行为：左键双击关闭、中键单击重置为 100% 大小与 100% 不透明
        container.onCloseRequest = { [weak self] in self?.closeAndReport() }
        container.onResetRequest = { [weak self] in self?.resetSizeAndAlpha() }
        contentView = container
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let modifiers = SnipKeyCommandResolver.Modifiers(nsEventFlags: event.modifierFlags)
        guard let command = PinKeyCommandResolver.resolve(keyCode: Int(event.keyCode),
                                                          characters: event.charactersIgnoringModifiers,
                                                          modifiers: modifiers) else {
            super.keyDown(with: event)
            return
        }
        perform(command)
    }

    /// 执行一条贴图键位命令
    private func perform(_ command: PinKeyCommand) {
        switch command {
        case .close: closeAndReport()
        case .destroy: destroy()
        case .rotateClockwise: rotate(clockwise: true)
        case .rotateCounterClockwise: rotate(clockwise: false)
        case .mirrorHorizontal: mirror(horizontal: true)
        case .mirrorVertical: mirror(horizontal: false)
        case .thumbnail: toggleThumbnail()
        case .zoom(let factor): setScale(currentScale * factor)
        case .alphaDelta(let delta): adjustAlpha(by: delta)
        case .resetSizeAndAlpha: resetSizeAndAlpha()
        case .copyPlainText: copyPlainTextToPasteboard()
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

    /// 复制该贴图的来源纯文本到剪贴板（官方 ⌘⇧C）
    ///
    /// 没有来源文本时不静默：贴图窗不是文本来源（例如截图像素贴图），
    /// 用户按了没反应会以为是按键失效，这里给出提示音 + 日志。
    func copyPlainTextToPasteboard() {
        guard let text = sourceText, !text.isEmpty else {
            NSSound.beep()
            AppContext.shared.logger.info("该贴图没有来源文本，⌘⇧C 无内容可复制")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        AppContext.shared.logger.info("已复制贴图来源文本（\(text.count) 字）")
    }

    /// 重置为 100% 大小与 100% 不透明（中键单击的官方语义）
    func resetSizeAndAlpha() {
        isThumbnail = false
        alphaValue = 1
        setScale(1)
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
        menu.addItem(withTitle: "垂直镜像", action: #selector(menuMirrorV), keyEquivalent: "").target = self
        menu.addItem(withTitle: "缩略图", action: #selector(menuThumbnail), keyEquivalent: "").target = self
        menu.addItem(withTitle: "重置大小与不透明度", action: #selector(menuResetAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭（可恢复）", action: #selector(menuClose), keyEquivalent: "").target = self
        menu.addItem(withTitle: "销毁", action: #selector(menuDestroy), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: imageView)
    }

    @objc private func menuCopy() { onCopy?(self) }
    @objc private func menuSave() { onSave?(self) }
    @objc private func menuRotate() { rotate(clockwise: true) }
    @objc private func menuMirrorH() { mirror(horizontal: true) }
    @objc private func menuMirrorV() { mirror(horizontal: false) }
    @objc private func menuThumbnail() { toggleThumbnail() }
    @objc private func menuResetAll() { resetSizeAndAlpha() }
    @objc private func menuClose() { closeAndReport() }
    @objc private func menuDestroy() { destroy() }
}

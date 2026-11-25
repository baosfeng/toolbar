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

    /// 偏好存储：右键菜单顺序每次现读（改完不重启也生效），禁止直读 UserDefaults
    private let storage: any KeyValueStorage
    private let imageView = NSImageView()
    /// 棋盘底：容器最底层的装饰视图，仅当「开关打开 + 图含透明像素」时显示
    private let boardView = PinBoardView(frame: .zero)
    /// 内容视图：双击 / 中键必须在这里判，否则会被窗口拖动吃掉（见 PinContentView）
    private let container = PinContentView(frame: .zero)
    private(set) var currentImage: CGImage
    /// 100% 尺寸（点）
    ///
    /// 跨文件可见性说明：缩放与透明度收在 PinWindow+Scroll.swift（滚轮 / 键位 / 中键共用），
    /// 那条路径要写这两个值，故去掉 private(set) 放宽为 internal。
    var baseSize: CGSize
    var currentScale: CGFloat = 1
    private(set) var isThumbnail = false
    /// 棋盘底开关（本窗当前状态；缺键即关，右键菜单切一次即落盘）
    private(set) var isBoardBackgroundEnabled = false
    /// 当前图是否含透明像素 —— 建窗时与每次换图时算一次，绘制路径不重复整图扫描
    private var currentImageHasAlpha = false

    /// 当前是否处于「按住拖动移动窗口」会话（拖动中一律不响应滚轮）
    ///
    /// 由 PinContentView 在按下 / 抬起时置位：拖动与滚轮在物理上可能同时发生
    /// （机械滚轮在拖动时会被带出抖动事件），叠在一起用户看到的就是
    /// 「我移动贴图的时候，贴图的透明度还会发生变化，越来越透明了」。
    /// 跨文件可见性说明：置位在 PinWindow+Scroll.swift 的 setDraggingWindow，
    /// 跨文件时 private(set) 的 setter 不可达，故整个属性放宽为 internal（只此一处写入）。
    var isDraggingWindow = false


    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage,
         initialSize: CGSize,
         storage: any KeyValueStorage = AppContext.shared.storage) {
        currentImage = image
        baseSize = initialSize
        self.storage = storage
        super.init(contentRect: NSRect(origin: .zero, size: initialSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 保留窗口背景拖动能力作为兜底；正常路径是 PinContentView 自己算位移
        // （nonactivatingPanel 上的默认拖动与非活跃时的 performDrag 都不可靠，见 PinContentView）
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        // 棋盘底开关：缺键即关（老用户零变化）；本窗只读不写，右键菜单切换时才落盘
        isBoardBackgroundEnabled = PinBoardBackgroundResolver.isEnabled(storage: storage)
        currentImageHasAlpha = SnipImageAlphaProbe.hasTransparentPixels(image)
        // 默认透明度来自设置页：建窗时读一次，之后滚轮 / 快捷键只改本窗，不影响偏好
        alphaValue = CGFloat(PinDefaultAlphaResolver.resolve(
            raw: storage.object(forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha) as? Double))

        imageView.frame = NSRect(origin: .zero, size: initialSize)
        imageView.image = NSImage(cgImage: image, size: initialSize)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        // 棋盘底先加 = 容器最底层；开关缺键即关，老用户看到的外观与接线前一致
        boardView.frame = NSRect(origin: .zero, size: initialSize)
        boardView.autoresizingMask = [.width, .height]
        container.frame = NSRect(origin: .zero, size: initialSize)
        container.autoresizingMask = [.width, .height]
        container.addSubview(boardView)
        container.addSubview(imageView)
        // 官方贴图行为：左键双击关闭、中键单击重置为 100% 大小与 100% 不透明
        container.onCloseRequest = { [weak self] in self?.closeAndReport() }
        container.onResetRequest = { [weak self] in self?.resetSizeAndAlpha() }
        contentView = container
        // 首帧就把棋盘底的显隐算好：透明图 + 开关打开时一出现就能看清哪里是透明区
        refreshBoardVisibility()
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
        case .grayscale: grayscale()
        case .invert: invert()
        case .thumbnail: toggleThumbnail()
        case .zoom(let factor): setScale(currentScale * factor)
        case .alphaDelta(let delta): adjustAlpha(by: delta)
        case .resetSizeAndAlpha: resetSizeAndAlpha()
        case .copyPlainText: copyPlainTextToPasteboard()
        }
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
    ///
    /// 不回落设置页的默认透明度：默认值只决定「新建贴图」的初始值，
    /// 中键是「恢复满不透明」的临时动作，回落默认值会让设过 0.5 的用户再也回不到 100%。
    func resetSizeAndAlpha() {
        isThumbnail = false
        setAlpha(1)
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

    /// 灰度（菜单项与键位 5）
    ///
    /// 与旋转 / 镜像同一条出口：重采样成新图后走 applyImage，尺寸与缩放保持不变。
    func grayscale() {
        guard let gray = SnipImageTransform.grayscale(currentImage) else { return }
        applyImage(gray)
    }

    /// 反色（菜单项与键位 6）
    ///
    /// 连续按两次回到原图（反色是对合运算），不额外记撤销栈，与旋转镜像的行为一致。
    func invert() {
        guard let inverted = SnipImageTransform.inverted(currentImage) else { return }
        applyImage(inverted)
    }

    // MARK: - 棋盘底

    /// 切换棋盘底开关（右键菜单项）
    ///
    /// 开关是**偏好**：切一次即落盘，之后新建的贴图沿用；
    /// 已有贴图只改本窗显隐（用户可能只是想把当前这张看清楚）。
    func setBoardBackground(_ enabled: Bool) {
        isBoardBackgroundEnabled = enabled
        PinBoardBackgroundResolver.save(enabled, storage: storage)
        refreshBoardVisibility()
        AppContext.shared.logger.info("贴图棋盘底：\(enabled ? "开" : "关")"
            + "（当前图含透明像素=\(currentImageHasAlpha)）")
    }

    /// 按「开关 + 是否含 alpha」重算棋盘底显隐
    ///
    /// 判据只在 PinBoardBackgroundResolver 里定义一次，视图只执行结果。
    private func refreshBoardVisibility() {
        boardView.isHidden = !PinBoardBackgroundResolver.shouldDraw(
            enabled: isBoardBackgroundEnabled,
            hasTransparentPixels: currentImageHasAlpha)
    }

    private func applyImage(_ image: CGImage) {
        let screenScale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let pointSize = CGSize(width: CGFloat(image.width) / screenScale,
                               height: CGFloat(image.height) / screenScale)
        currentImage = image
        // 换图（旋转 / 镜像 / 灰度 / 反色）后 alpha 分布可能变了，棋盘底判据要跟着重算
        currentImageHasAlpha = SnipImageAlphaProbe.hasTransparentPixels(image)
        refreshBoardVisibility()
        baseSize = pointSize
        imageView.image = NSImage(cgImage: image, size: pointSize)
        applySize(CGSize(width: pointSize.width * currentScale,
                         height: pointSize.height * currentScale))
    }

    /// 套用新尺寸并重算原点
    ///
    /// 原点口径只有一份（PinZoomAnchor）：锚点为 nil 时按窗口中心换算，
    /// 与旧实现「中心不变」逐点等价；滚轮缩放传鼠标位置，锚点下的内容点不动。
    /// 跨文件可见性说明：缩放 / 透明度都在 PinWindow+Scroll.swift，
    /// 那条路径改完尺寸要回到这里换算原点，故放宽为 internal。
    func applySize(_ size: CGSize, anchor: CGPoint? = nil) {
        let origin = PinZoomAnchor.origin(frame: frame, newSize: size, anchor: anchor)
        setFrame(CGRect(origin: origin, size: size), display: true)
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

    /// 右键菜单每次现读偏好再装配 —— 设置页改完顺序，下一张右键菜单就按新顺序出现
    ///
    /// 各项的顺序与标题都来自 PinMenuAction（Core），且允许跨组换序，
    /// 分隔线因此按**最终顺序**在语义分组变化处插入（PinMenuDivider），不看固定分组区间。
    /// 选择器映射与各菜单动作在 PinWindow+Menu.swift（同一个类的扩展）。
    /// 危险项位置由顺序决定，误点风险由视觉兜：菜单里用红色文字标出「关闭 / 销毁」。
    override func rightMouseDown(with event: NSEvent) {
#if DEBUG
        PinDragProbe.recordContextMenu()
#endif
        let menu = NSMenu()
        let order = PinMenuOrderResolver.load(storage: storage)
        let separators = PinMenuDivider.leadingSeparators(for: order)
        for (index, action) in order.enumerated() {
            if separators[index] {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: action.title,
                                  action: Self.selector(for: action),
                                  keyEquivalent: "")
            item.target = self
            // 开关项带勾选态：棋盘底开着时菜单里能直接看出来
            if action == .boardBackground {
                item.state = isBoardBackgroundEnabled ? .on : .off
            }
            if action.isDestructive {
                item.attributedTitle = NSAttributedString(
                    string: action.title,
                    attributes: [.foregroundColor: NSColor.systemRed])
            }
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: imageView)
    }

}

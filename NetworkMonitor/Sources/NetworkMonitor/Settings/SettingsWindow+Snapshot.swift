#if DEBUG
import AppKit

// MARK: - 设置窗口快照自证（仅 DEBUG）

/// 快照所需的几个入口 — 从 `SettingsWindow.swift` 拆出
///
/// 拆出原因：窗口主文件只留容器与切页，而这些方法只服务于 DEBUG 快照取证。
/// 跨文件访问：`window` / `factories` / `rootView` / `currentPane` / `contentScroll`
/// 由 private 放宽为 internal，仅供本扩展使用。
extension SettingsWindow {

    /// 快照自证（仅 DEBUG）：用一个全新窗口复现「用户第一次打开设置」的路径
    ///
    /// 与 `prepareForSnapshot` 的区别是**不做任何显式布局**，用来复现首次进入的版式问题。
    /// 侧栏直接复用 `SettingsSidebarBuilder`：结构改过之后探针图必须与真实窗口同构，
    /// 否则「首次进入空白」这类回归会被探针图掩盖。
    func makeFreshForFirstOpenProbe() -> NSView? {
        guard let factory = factories[.general] else { return nil }
        let probeWindow = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsTheme.windowSize),
                                   styleMask: [.titled, .closable, .miniaturizable],
                                   backing: .buffered, defer: false)
        let root = SettingsSurfaceView { SettingsTheme.surface }
        let built = SettingsSidebarBuilder.make { _ in }
        built.items[.general]?.isSelected = true
        let sidebar = built.view

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let container = SettingsFlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container
        let pane = factory()
        pane.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pane)
        root.addSubview(sidebar)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsTheme.sidebarWidth),
            scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: SettingsTheme.contentInset),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                           constant: -SettingsTheme.contentInset),
            pane.topAnchor.constraint(equalTo: container.topAnchor,
                                      constant: SettingsTheme.contentInset),
            pane.bottomAnchor.constraint(equalTo: container.bottomAnchor,
                                         constant: -SettingsTheme.contentInset),
        ])
        probeWindow.contentView = root
        return root
    }

    /// 快照自证（仅 DEBUG）：切到指定分类并滚到「距底部 offset 点」处
    ///
    /// 用于首屏之外、但又不在页面最底部的区块（例如截图页的「识别 / 保存」两张卡）：
    /// 滚到底部会把它们挤出视野，只滚一段才能同时看到。
    func prepareForSnapshotScrolled(toBottomOffset offset: CGFloat,
                                    section: SettingsSection) -> NSView? {
        window.contentView = rootView
        select(section)
        rootView.layoutSubtreeIfNeeded()
        let documentHeight = contentContainer.bounds.height
        let viewportHeight = contentScroll.contentView.bounds.height
        let target = max(0, documentHeight - viewportHeight - offset)
        contentScroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        return rootView
    }

    /// 快照自证（仅 DEBUG）：当前页实例（探针要按页面类型取控件状态）
    var currentPaneForSnapshot: SettingsPaneView? { currentPane }

    /// 快照自证（仅 DEBUG）：切到指定分类，并滚到「本页通知事件卡」完整可见的位置
    ///
    /// 事件卡已按功能下沉到各页（额度 / 截图 / 剪贴板 / 互传 / 通用），在页内位置靠后，
    /// 首屏图看不到它；这里按卡片在文档里的实际坐标滚一段，让图能直接证明「行确实在这页」。
    func prepareForSnapshotShowingNotificationCard(_ section: SettingsSection) -> NSView? {
        window.contentView = rootView
        select(section)
        rootView.layoutSubtreeIfNeeded()
        guard let host = currentPane as? SettingsNotificationEventHosting else { return rootView }
        let card = host.notificationCard.card
        let cardRect = card.convert(card.bounds, to: contentContainer)
        let viewportHeight = contentScroll.contentView.bounds.height
        let maxOffset = max(0, contentContainer.bounds.height - viewportHeight)
        // 卡片顶端贴到视口上方留一个内容内边距，避免被页头遮住
        let target = min(max(0, cardRect.minY - SettingsTheme.contentInset), maxOffset)
        contentScroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        return rootView
    }

    /// 快照自证（仅 DEBUG）：切到指定分类并返回内容视图，供离屏渲染
    func prepareForSnapshot(_ section: SettingsSection) -> NSView? {
        // 上一次渲染把根视图借进了离屏容器并移除，这里先挂回去再切页
        window.contentView = rootView
        select(section)
        rootView.layoutSubtreeIfNeeded()
        // 内容超过一屏时上次的滚动位置会残留，快照前统一回到顶部
        contentScroll.contentView.scroll(to: .zero)
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        return rootView
    }

    /// 快照自证（仅 DEBUG）：当前页文档高度（页面内容是否超出视口、需要下滚多少）
    var snapshotScrollDocumentHeight: CGFloat? { contentContainer.bounds.height }

    /// 快照自证（仅 DEBUG）：切到指定分类并滚动到底部后返回内容视图
    ///
    /// 用于核对「首屏之外」的内容（例如剪贴板页的存储卡）：版式基线仍按首屏出图，
    /// 滚动图只作为该区块可见性 / 深浅色不压字的证据，不替代首屏图。
    func prepareForSnapshotScrolledToBottom(_ section: SettingsSection) -> NSView? {
        window.contentView = rootView
        select(section)
        rootView.layoutSubtreeIfNeeded()
        let documentHeight = contentContainer.bounds.height
        let viewportHeight = contentScroll.contentView.bounds.height
        // 文档是 flipped：y 越大越靠下；文档不超出视口时保持 0（不产生假滚动）
        contentScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, documentHeight - viewportHeight)))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        return rootView
    }
}
#endif
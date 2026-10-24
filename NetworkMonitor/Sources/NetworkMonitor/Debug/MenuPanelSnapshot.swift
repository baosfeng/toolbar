#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 开发期面板快照钩子（仅 DEBUG）

/// 菜单面板 / 剪贴板面板快照钩子 — **仅 DEBUG 编译**，release 构建完全不包含本文件
///
/// 触发方式：
/// ```
/// NM_SNAPSHOT_DIR=/tmp/nm-shots .build/arm64-apple-macosx/debug/NetworkMonitor
/// ```
/// 启动 700ms 后把菜单面板（三个 tab × 浅色/深色）与剪贴板面板渲染成 PNG，然后自行退出进程。
///
/// 存在理由：本机终端没有辅助功能权限（`AXIsProcessTrusted == false`），CGEvent 点不到状态栏
/// 按钮，也就无法自动点开 popover 做 GUI 取证；这里直接用同一套视图做离屏渲染。
/// 注意：为便于核对排版，速率/流量/进程这几项在快照里用固定示意值；IP / Wi-Fi / 剪贴板条目取真实数据。
@MainActor
enum MenuPanelSnapshot {

    /// 触发开关的环境变量名
    static let directoryEnvKey = "NM_SNAPSHOT_DIR"
    /// 超高内容自证开关（进程 12 个，验证滚动兜底）
    static let stressEnvKey = "NM_SNAPSHOT_STRESS"
    /// 额度页示意数据开关（快照模式默认注入，显式设置时只用于日志标记）
    static let billingMockEnvKey = "NM_BILLING_MOCK"
    /// 启动后延迟（等 Dock / 菜单栏 / 剪贴板采集初始化完成）
    private static let delayNanoseconds: UInt64 = 700_000_000
    /// 剪贴板面板画布尺寸（与 07-contract 的 640×260 画布口径一致）
    private static let clipboardPanelSize = NSSize(width: 640, height: 260)

    private static var logger: LoggingService { AppContext.shared.logger }

    /// 入口：环境变量存在时延时执行快照并退出进程；未设置时立即返回
    static func runIfRequested(repository: (any ClipboardRepository)?,
                                harness: (any HarnessUsageServicing)? = nil) {
        guard let path = ProcessInfo.processInfo.environment[directoryEnvKey], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            // Token 页：先等一次索引（已有落库数据时是快速增量），再用真实快照渲染
            let tokenSnapshot = await TokenPaneSnapshot.waitForSnapshot(harness: harness)
            captureAll(directory: directory, repository: repository, tokenSnapshot: tokenSnapshot)
            TokenPaneSnapshot.capture(directory: directory, tokenSnapshot: tokenSnapshot)
            NSApp.terminate(nil)
        }
    }

    // MARK: - 快照主流程

    private static func captureAll(directory: URL, repository: (any ClipboardRepository)?,
                                   tokenSnapshot: HarnessUsageSnapshot?) {
        let items = repository?.fetchClipboardItems(kind: nil, limit: 5) ?? []
        let stress = (ProcessInfo.processInfo.environment[stressEnvKey]?.isEmpty == false)
        let billingMock = (ProcessInfo.processInfo.environment[billingMockEnvKey]?.isEmpty == false)
        logger.info("快照模式启动：目录=\(directory.path)，剪贴板条目 \(items.count) 条，超高自证=\(stress)，额度模拟=\(billingMock)")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("快照目录创建失败：\(error.localizedDescription)")
            return
        }

        // 1. 菜单面板：三个 tab × 深浅色
        for tab in MenuPanelTab.allCases {
            let panel = makeMenuPanel(tab: tab, items: items, tokenSnapshot: tokenSnapshot)
            let needed = panel.desiredContentHeight
            let height = min(max(needed, 180), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent("menu-\(tab.fileNameSuffix)-\(suffix).png")
                render(view: panel, size: size, appearanceName: appearance, to: url)
            }
        }

        // 2. 额度页补充状态：未配置凭据 / 查询失败 + 遗留计划限额（浅色 + 深色）
        captureCreditsStates(directory: directory)

        // 3. 超高内容自证：进程 12 个 → 内容高度 > 520pt，验证不裁切且可滚动
        if stress {
            captureStress(directory: directory, items: items)
        }

        // 4. 剪贴板面板：一个视图 × 深浅色
        let clipboardBackdrop = makeClipboardPanel(items: items)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("panel-clipboard-\(suffix).png")
            render(view: clipboardBackdrop.makeView(), size: clipboardPanelSize,
                   appearanceName: appearance, to: url)
        }

        logger.info("快照完成：目录=\(directory.path)")
    }

    /// 额度页补充状态 — 未配置 / 查询失败（含遗留计划限额）/ 遗留计划用量 / Open Design，
    /// 各出浅色、深色两张
    private static func captureCreditsStates(directory: URL) {
        let states: [(suffix: String, configured: Bool, error: String?, legacyUsage: Bool,
                      openDesign: Bool)] = [
            ("unconfigured", false, nil, false, false),
            ("error", true, "API Key 无效或已过期", false, false),
            ("legacy", true, nil, true, false),
            // Open Design：credits 限额明细、无柱状图、模型行显示 token 合计
            ("open-design", true, nil, false, true),
        ]
        for state in states {
            let panel = MenuPanelView()
            panel.billingPane.injectPreview(configured: state.configured,
                                            errorMessage: state.error,
                                            legacyLimits: state.error != nil || state.legacyUsage,
                                            legacyUsage: state.legacyUsage,
                                            openDesign: state.openDesign)
            panel.select(tab: .credits)
            let height = min(max(panel.desiredContentHeight, 180), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent("menu-credits-\(state.suffix)-\(name).png")
                // 遗留计划快照额外强制悬停一根有数据的柱，用于 tooltip 取证
                let hover: ((NSView) -> Void)? = state.legacyUsage ? { view in
                    (view as? MenuPanelView)?.billingPane.forceChartHoverForSnapshot(23)
                } : nil
                render(view: panel, size: size, appearanceName: appearance, to: url,
                       postLayout: hover)
            }
        }
    }

    /// 超高内容自证：把进程数拉到 12（内容 > 520pt），截「视口顶部」与「滚到底部」两张图，
    /// 并把文档高度 / 视口高度写进 metrics 文本，证明内容没有被裁切、而是变成可滚动。
    private static func captureStress(directory: URL, items: [ClipboardItem]) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let panel = makeMenuPanel(tab: .network, items: items, processCount: 12)
            let needed = panel.desiredContentHeight
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)

            render(view: panel, size: size, appearanceName: appearance,
                   to: directory.appendingPathComponent("menu-network-stress-\(suffix).png"))

            let scrolledPanel = makeMenuPanel(tab: .network, items: items, processCount: 12)
            render(view: scrolledPanel, size: size, appearanceName: appearance,
                   to: directory.appendingPathComponent("menu-network-stress-\(suffix)-scrolled.png")) { view in
                guard let panel = view as? MenuPanelView else { return }
                let metrics = panel.snapshotScrollMetrics()
                panel.scrollToBottomForSnapshot()
                writeSnapshotMetrics(directory: directory, needed: needed, size: size, metrics: metrics)
            }
        }
    }

    /// 构建菜单面板并填入快照数据（速率/流量/进程为固定示意值，剪贴板/系统取真实数据）
    private static func makeMenuPanel(tab: MenuPanelTab, items: [ClipboardItem],
                                      processCount: Int = 5,
                                      tokenSnapshot: HarnessUsageSnapshot? = nil) -> MenuPanelView {
        let panel = MenuPanelView()
        panel.updateSpeeds(down: 1_200_000, up: 340_000,
                           downHistory: SnapshotFixtures.history(base: 900_000, amplitude: 700_000),
                           upHistory: SnapshotFixtures.history(base: 180_000, amplitude: 260_000))
        panel.updateTraffic(todayRx: 12_500_000_000, todayTx: 3_200_000_000,
                            dailyBars: SnapshotFixtures.dailyBars())
#if DEBUG
        if processCount > 5 {
            // 产品路径固定 Top5；快照自证需要把上限临时抬高才能构造超高内容
            panel.networkPane.processRowLimitOverride = processCount
        }
#endif
        panel.updateProcesses(SnapshotFixtures.processes(count: processCount))
        panel.updateClipboardItems(items)
        panel.launchAtStartupEnabled = AppContext.shared.storage
            .bool(forKey: ClipboardPreferences.launchAtStartupKey)
        // 额度页：快照用原型同款示意数据（余额 72.50/100、已购 25、24h 用量、2 个模型）
        if tab == .credits {
            panel.billingPane.injectPreview()
        }
        if tab == .token, let tokenSnapshot {
            // Token 页：真实索引快照（来自 HarnessUsageService.snapshot()）
            panel.updateToken(tokenSnapshot, notifySize: false)
        }
        panel.select(tab: tab)
        return panel
    }

    /// 构建剪贴板面板画布：背景 + 真实面板同款材质底 + ClipboardPanelView
    private static func makeClipboardPanel(items: [ClipboardItem]) -> SnapshotClipboardPanel {
        SnapshotClipboardPanel(size: clipboardPanelSize, items: items)
    }

    // MARK: - 离屏渲染

    /// 把视图渲染成 PNG（强制指定外观，浅色/深色各一份）
    ///
    /// 步骤：套一层纯色背景容器 → 放进离屏 borderless 窗口 → 布局 → `cacheDisplay` 抓位图 → 写 PNG。
    /// 面板本身已是不透明背景，这里不改材质，保证离屏结果与真实窗口一致。任何一步失败只记日志。
    static func render(view: NSView, size: NSSize,
                               appearanceName: NSAppearance.Name, to url: URL,
                               postLayout: ((NSView) -> Void)? = nil) {
        guard let appearance = NSAppearance(named: appearanceName) else {
            logger.error("快照外观不可用：\(appearanceName.rawValue)")
            return
        }

        let container = SnapshotBackdropView(frame: NSRect(origin: .zero, size: size))
        container.appearance = appearance

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = container

        view.appearance = appearance
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        container.needsDisplay = true
        view.displayIfNeeded()
        container.displayIfNeeded()
        // 布局完成后、抓图前插入的钩子（滚动自证 / 指标读取）
        postLayout?(view)
        container.needsDisplay = true
        container.displayIfNeeded()

        defer {
            view.removeFromSuperview()
            window.contentView = nil
        }

        // 显式按 1pt = 1px 建位图：证据图尺寸即画布尺寸（320×高 / 640×260），
        // 不受屏幕 backingScaleFactor 影响（Retina 上默认会输出 2 倍图）。
        let pixelWidth = max(1, Int(container.bounds.width.rounded()))
        let pixelHeight = max(1, Int(container.bounds.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            logger.error("快照位图创建失败：\(url.lastPathComponent)")
            return
        }
        rep.size = container.bounds.size
        container.cacheDisplay(in: container.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            logger.error("快照 PNG 编码失败：\(url.lastPathComponent)")
            return
        }
        do {
            try data.write(to: url)
            logger.info("快照已写入 \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } catch {
            logger.error("快照写入失败 \(url.lastPathComponent)：\(error.localizedDescription)")
        }
    }
}

// MARK: - 文件命名

private extension MenuPanelTab {
    /// 快照文件名后缀
    var fileNameSuffix: String {
        switch self {
        case .network: return "network"
        case .clipboard: return "clipboard"
        case .transfer: return "transfer"
        case .credits: return "credits"
        case .token: return "token"
        }
    }
}
#endif
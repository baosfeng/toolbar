import AppKit
import NetworkMonitorCore

// MARK: - 二级详情页容器

/// 详情页数据上下文 — 一帧快照 + 60 点历史 + 采样周期
///
/// 五个详情页共用同一份上下文：曲线都来自控制器注入的 60 点历史，不在页内另起采样；
/// 采样周期来自设置页偏好（不硬编码 1 秒）。
struct SystemDetailContext {
    let snapshot: SystemMetricsSnapshot?
    let sampleInterval: Double?
    let cpuHistory: [Double]
    let cpuSystemHistory: [Double]
    let gpuHistory: [Double]
    let memoryHistory: [Double]
    let memoryWiredHistory: [Double]
    let memoryActiveHistory: [Double]
    let memoryCompressedHistory: [Double]
    let diskReadHistory: [Double]
    let diskWriteHistory: [Double]
    let loadShortHistory: [Double]
    let loadMediumHistory: [Double]
    let loadLongHistory: [Double]
}

/// 二级详情页容器 — 顶部「‹ 系统」返回条 + 五页互斥内容
///
/// 覆盖在系统页内（同一 320pt 宽），**不弹新窗口、不新增 tab**：进入时隐藏首屏，
/// 返回时恢复首屏。页面切换只切 `isHidden`，各页实例复用（历史与榜单切换态不丢）。
@MainActor
final class SystemDetailPaneView: NSView {

    /// 详情页
    enum Page: String, CaseIterable {
        case cpu
        case gpu
        case memory
        case disk
        case process

        /// 返回条面包屑
        var crumb: String {
            switch self {
            case .cpu: return "/ CPU 详情"
            case .gpu: return "/ GPU 详情"
            case .memory: return "/ 内存 详情"
            case .disk: return "/ 磁盘 详情"
            case .process: return "/ 压力详情"
            }
        }
    }

    /// 返回回调（由 SystemPaneView 接到「显示首屏」）
    var onBack: (() -> Void)?

    private(set) var page: Page = .cpu

    private let backButton = SystemDetailBackButton()
    private let crumbLabel: NSTextField
    private let contentStack = NSStackView()
    private let cpuPage = SystemCPUDetailView()
    private let gpuPage = SystemGPUDetailView()
    private let memoryPage = SystemMemoryDetailView()
    private let diskPage = SystemDiskDetailView()
    private let processPage = SystemProcessDetailView()
    private var lastContext: SystemDetailContext?

    init() {
        crumbLabel = MenuPanelLabel.text(Page.cpu.crumb,
                                         font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                         color: SystemPalette.meta)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let backBar = NSStackView(views: [backButton, crumbLabel,
                                          MenuPanelLabel.spacer(),
                                          MenuPanelLabel.text("近 60 秒",
                                                              font: SystemPaneStyle.tinyFont,
                                                              color: SystemPalette.meta)])
        backBar.orientation = .horizontal
        backBar.alignment = .centerY
        backBar.spacing = 5
        backBar.translatesAutoresizingMaskIntoConstraints = false

        backButton.target = self
        backButton.action = #selector(goBack)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 7
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView(views: [backBar, contentStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 7
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            backBar.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentStack.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])

        for pageView in [cpuPage, gpuPage, memoryPage, diskPage, processPage] {
            contentStack.addArrangedSubview(pageView)
            pageView.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            pageView.isHidden = true
        }
        show(.cpu)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 页面切换

    /// 切到指定详情页（同页重复调用只刷新）
    func show(_ page: Page) {
        self.page = page
        crumbLabel.stringValue = page.crumb
        cpuPage.isHidden = page != .cpu
        gpuPage.isHidden = page != .gpu
        memoryPage.isHidden = page != .memory
        diskPage.isHidden = page != .disk
        processPage.isHidden = page != .process
        if let lastContext {
            update(page: page, context: lastContext)
        }
        // 不抢面板第一响应者：菜单面板的键盘遍历（Tab / ↑↓ / Esc）由 MenuPanelView 统一处理，
        // 若把 NSButton 设为 firstResponder，Tab 会掉进 AppKit 的 key-view loop，返回键反而更难用。
        // 键盘可达性由「Esc 先返回首屏 + 返回后焦点还给卡片」保证。
    }

    /// 刷新上下文 — 只更新当前页（切页时用最近一帧补齐，避免空白页）
    func update(_ context: SystemDetailContext) {
        lastContext = context
        update(page: page, context: context)
    }

    private func update(page: Page, context: SystemDetailContext) {
        switch page {
        case .cpu: cpuPage.update(context)
        case .gpu: gpuPage.update(context)
        case .memory: memoryPage.update(context)
        case .disk: diskPage.update(context)
        case .process: processPage.update(context)
        }
    }

    @objc private func goBack() {
        onBack?()
    }

    // MARK: - 共享小工具

    /// 采样周期拆成「数值 + 单位」（详情页事实行要求数值与单位分开排版）
    static func sampleIntervalParts(_ seconds: Double?) -> (value: String, unit: String?) {
        let text = SystemDetailFormatting.sampleIntervalText(seconds)
        guard text != SystemDetailFormatting.placeholder else { return (text, nil) }
        let parts = text.split(separator: " ", maxSplits: 1)
        return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : nil)
    }
}

import AppKit
import NetworkMonitorCore

// MARK: - 采集服务实现

/// 剪贴板采集器 — 同一个实现的两种模式（设计规格第 6 节分支 A / B）
///
/// - 模式 B（polling，当前默认）：动态间隔 Timer 轮询 + changeCount 变更即读
///   间隔由 `ClipboardPollSchedule` 决定（0.5s / 2.0s / 5.0s，随用户活跃度切换），
///   另有 `com.apple.pasteboard.changed` 分布式通知作提前唤醒（只提前跑一次 capture，不改轮询节奏）
/// - 模式 A（onDemand）：不启动轮询，仅在打开面板或点击「采集当前剪贴板」时调 captureNow()
///
/// 两种模式共用同一条流水线：changeCount 判定 → 访问权限判定 → 忽略判定 → 哈希 → 落盘 → onCapture。
/// 落库与事件通知由调用方（组合根）在 onCapture 回调里完成，采集器不直接触碰仓储。
@MainActor
final class PasteboardWatcher: ClipboardCaptureService {

    /// 活跃档轮询间隔（历史固定值，增量 B 起作为最快档上限，供测试与既有断言使用）
    ///
    /// 实际间隔由 `ClipboardPollSchedule.interval(idleSeconds:isAppActive:)` 逐次计算，
    /// 本常量只代表「用户刚有输入且本 App 前台」时的档位。
    static let pollInterval: TimeInterval = ClipboardPollSchedule.activeInterval

    /// 剪贴板变更的分布式通知名（只作提前唤醒；changeCount 仍是唯一准入闸门）
    static let pasteboardChangedNotification = Notification.Name("com.apple.pasteboard.changed")

    private let preferences: ClipboardPreferences
    private let logger: LoggingService
    private let pasteboard: NSPasteboard
    /// 用户活跃度探针（免权限读秒 + 前台状态缓存）
    private let activityMonitor: UserActivityMonitor
    /// 提前唤醒的通知观察者（stop() 时注销）
    private var wakeObserver: NSObjectProtocol?

    /// 下一次 tick 的一次性 Timer（每次 tick 后按当前档位重排，不重建 RunLoop 源）
    private var timer: Timer?
    /// 上次读到的 changeCount；初值取哨兵值，避免在初始化阶段读取剪贴板（探针未覆盖的路径不做多余访问）
    private var lastChangeCount = Int.min

    private(set) var isRunning = false
    var onStateChange: ((ClipboardCaptureState) -> Void)?
    var onCapture: ((ClipboardDraft) -> Void)?

    init(preferences: ClipboardPreferences,
         logger: LoggingService = AppContext.shared.logger,
         pasteboard: NSPasteboard = .general,
         activityMonitor: UserActivityMonitor? = nil) {
        self.preferences = preferences
        self.logger = logger
        self.pasteboard = pasteboard
        self.activityMonitor = activityMonitor ?? UserActivityMonitor()
    }

    // MARK: ClipboardCaptureService

    func start() {
        guard !isRunning else { return }
        guard preferences.captureMode == .polling else {
            // 分支 A：不轮询，退化为「打开面板读一次 + 面板内手动采集」
            logger.info("剪贴板采集启动：分支 A（按需），不启动后台轮询")
            onStateChange?(.stopped)
            return
        }
        guard checkAccessBehavior() else { return }

        isRunning = true
        activityMonitor.start()
        registerWakeObserver()
        scheduleTick()
        onStateChange?(.running)
        logger.info("剪贴板采集启动：分支 B（动态轮询 " + Self.secondsText(ClipboardPollSchedule.activeInterval)
                   + "–" + Self.secondsText(ClipboardPollSchedule.idleInterval) + "s）")
    }

    func stop() {
        // 先落 isRunning = false：重排决策依赖它，迟到的一次性 Timer 不会再排下一次
        let wasRunning = isRunning
        isRunning = false
        timer?.invalidate()
        timer = nil
        unregisterWakeObserver()
        activityMonitor.stop()
        // 未运行时只是「清理已泄漏的观察者」，不发状态事件（保持原有静默语义）
        guard wasRunning else { return }
        onStateChange?(.stopped)
        logger.info("剪贴板采集已停止")
    }

    // deinit 与 @MainActor 隔离（Swift 6 isolated deinit）：Timer 失效与观察者摘除都在主线程上做，
    // 避免跨线程碰 Timer 这类非 Sendable 资源；即便调用方忘了 stop()，析构时也会自动收口。
    isolated deinit {
        timer?.invalidate()
        if let wakeObserver {
            DistributedNotificationCenter.default().removeObserver(wakeObserver)
        }
    }

    // MARK: 动态轮询

    /// 按当前档位排下一次一次性 tick（停止后永不重排）
    private func scheduleTick() {
        timer?.invalidate()
        timer = nil
        let idleSeconds = activityMonitor.idleSeconds
        let isAppActive = activityMonitor.isAppActive
        guard let interval = ClipboardPollSchedule.nextInterval(isRunning: isRunning,
                                                               idleSeconds: idleSeconds,
                                                               isAppActive: isAppActive) else {
            return
        }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // 加入 RunLoop 的 common modes：菜单展开 / 拖拽期间也不停止采集
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 一次 tick：采集一次 + 按新的活跃度重排下一次
    private func tick() {
        guard isRunning else { return }
        capture()
        scheduleTick()
    }

    /// 剪贴板变更的提前唤醒：立即跑一次采集，不改轮询节奏
    ///
    /// 通知可能来自任意进程与线程，统一回主线程；changeCount 未变时 capture() 直接返回，
    /// 因此唤醒只可能「提前一点读到」，不会重复入库、也不会改变忽略判定。
    private func registerWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.pasteboardChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.capture()
            }
        }
    }

    private func unregisterWakeObserver() {
        guard let wakeObserver else { return }
        DistributedNotificationCenter.default().removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    /// 日志用的秒数文案（一位小数，避免打印 0.5000000001 这类浮点尾数）
    private static func secondsText(_ interval: TimeInterval) -> String {
        String(format: "%.1f", interval)
    }

    /// 立即采集一次（分支 A 的面板打开 / 手动采集按钮；与轮询同一条流水线，无新内容时静默返回）
    func captureNow() {
        capture()
    }

    // MARK: 采集流水线

    private func capture() {
        guard checkAccessBehavior() else { return }
        let changeCount = pasteboard.changeCount
        // 第 5 节第 2 步：changeCount 未变立即返回，不读任何内容数据（含类型列表）
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let typeNames = (pasteboard.types ?? []).map(\.rawValue)
        let source = sourceApplication()
        if let reason = ClipboardIgnorePolicy.ignoreReason(typeNames: typeNames,
                                                           bundleID: source?.bundleIdentifier,
                                                           blacklistedBundleIDs: preferences.ignoredBundleIDs) {
            logger.debug("剪贴板采集跳过：\(reason.label)")
            return
        }
        guard let draft = makeDraft(source: source) else {
            logger.debug("剪贴板无可用内容（空内容 / 图片超限 / 无支持类型）")
            return
        }
        onCapture?(draft)
    }

    /// 读取系统剪贴板访问行为；alwaysDeny 时停采并提示（不得静默）
    private func checkAccessBehavior() -> Bool {
        guard #available(macOS 15.4, *) else { return true }
        guard pasteboard.accessBehavior == .alwaysDeny else { return true }
        stop()
        onStateChange?(.denied(.alwaysDeny))
        logger.warning("剪贴板访问被系统拒绝：请前往「系统设置 → 隐私与安全性」允许本应用访问剪贴板")
        return false
    }

    /// 来源 App：前台应用即用户的复制来源；前台是本 App 时不记录来源（面板打开态的采集）
    private func sourceApplication() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        if let ownBundleID = Bundle.main.bundleIdentifier, frontmost.bundleIdentifier == ownBundleID {
            return nil
        }
        return frontmost
    }

    // MARK: 内容解析

    /// 按优先级解析：文件 URL > 图片 > RTF > 纯文本
    private func makeDraft(source: NSRunningApplication?) -> ClipboardDraft? {
        let bundleID = source?.bundleIdentifier
        let appName = source?.localizedName
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let now = Date()

        // 1) 文件 URL（多个文件合并为一条记录）
        let paths = pasteboardItems
            .compactMap { $0.string(forType: .fileURL) }
            .compactMap { URL(string: $0)?.path }
        if !paths.isEmpty, let payload = ClipboardContentHasher.prepareText(paths.joined(separator: "\n")) {
            return ClipboardDraft(kind: .file,
                                  contentHash: payload.contentHash,
                                  text: payload.text,
                                  preview: ClipboardPreview.make(from: payload.text),
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now)
        }

        // 2) 图片（PNG 优先、TIFF 兜底，同一表示同时用于哈希与落盘）
        if let imageDraft = makeImageDraft(pasteboardItems: pasteboardItems, bundleID: bundleID, appName: appName, now: now) {
            return imageDraft
        }

        // 3) RTF（模型不存富文本字节，落纯文本正文）
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           let payload = ClipboardContentHasher.prepareText(attributed.string) {
            return ClipboardDraft(kind: .rtf,
                                  contentHash: payload.contentHash,
                                  text: payload.text,
                                  preview: ClipboardPreview.make(from: payload.text),
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now)
        }

        // 4) 纯文本：多个 pasteboardItems 按换行拼接为一条记录
        var texts = pasteboardItems.compactMap { $0.string(forType: .string) }
        if texts.isEmpty, let text = pasteboard.string(forType: .string) { texts = [text] }
        guard let payload = ClipboardContentHasher.prepareText(texts.joined(separator: "\n")) else { return nil }
        return ClipboardDraft(kind: .text,
                              contentHash: payload.contentHash,
                              text: payload.text,
                              preview: ClipboardPreview.make(from: payload.text),
                              sourceBundleID: bundleID,
                              sourceAppName: appName,
                              createdAt: now)
    }

    /// 图片条目：多个 pasteboardItems 只取首个可解码项
    ///
    /// 像素守卫在落盘前判定：超限的图不写盘、不生成缩略图，只留一条带尺寸的占位记录
    /// （卡片按 `imagePath == nil` 渲染占位符号，用户可见「超过像素上限，未保存原图」）。
    private func makeImageDraft(pasteboardItems: [NSPasteboardItem],
                                bundleID: String?,
                                appName: String?,
                                now: Date) -> ClipboardDraft? {
        for pasteboardItem in pasteboardItems {
            guard let representation = Self.imageRepresentation(of: pasteboardItem) else { continue }
            guard let contentHash = ClipboardContentHasher.prepareImageData(representation.data) else {
                logger.debug("图片为空或超过压缩字节上限，跳过落库")
                continue
            }
            guard let outcome = ClipboardImageStore.store(data: representation.data,
                                                          contentHash: contentHash,
                                                          logger: logger) else { continue }
            switch outcome {
            case .stored(let stored):
                return ClipboardDraft(kind: .image,
                                      contentHash: contentHash,
                                      preview: "图片 \(stored.width)×\(stored.height)",
                                      imagePath: stored.path,
                                      imageWidth: stored.width,
                                      imageHeight: stored.height,
                                      sourceBundleID: bundleID,
                                      sourceAppName: appName,
                                      createdAt: now)
            case .rejected(let rejection):
                // 占位降级：图太大（或不合法）时只记尺寸与提示，绝不落盘、不缓存
                return ClipboardDraft(kind: .image,
                                      contentHash: contentHash,
                                      preview: rejection.placeholderPreview,
                                      imagePath: nil,
                                      imageWidth: rejection.width,
                                      imageHeight: rejection.height,
                                      sourceBundleID: bundleID,
                                      sourceAppName: appName,
                                      createdAt: now)
            }
        }
        return nil
    }

    /// PNG 优先、缺失或不合法时兜底 TIFF；同一次复制只取一种表示
    private static func imageRepresentation(of pasteboardItem: NSPasteboardItem) -> (data: Data, isPNG: Bool)? {
        if let png = pasteboardItem.data(forType: .png) { return (png, true) }
        if let tiff = pasteboardItem.data(forType: .tiff) { return (tiff, false) }
        return nil
    }
}

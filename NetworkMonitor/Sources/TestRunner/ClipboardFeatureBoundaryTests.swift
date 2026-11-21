import AppKit
import Foundation
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 剪贴板服务层（独立 target）边界测试

/// 跨 target 断言：采集 / 粘贴 / 粘贴栈 / 图片落盘与回收 / 缩略图解码 / OCR 调度住在新拆出的
/// NetworkMonitorFeatureClipboard 里，TestRunner 直接 import 该模块、走真实入口。
///
/// 改造前测不到：服务层在可执行 target NetworkMonitor 里，TestRunner 对 PasteboardWatcher /
/// ClipboardPaster / PasteStackController 不可见，只能断言 Core 的纯判据。
/// 这里补三类：① 端口注入（logger / 缓存 / 偏好必传）；② 行为（粘贴栈状态机 / 缓存命中 / 结果文案）；
/// ③ 边界（App 里不再有那些服务文件，新 target 不反向依赖 App 的偏好聚合类与面板类型）。
@MainActor
func runClipboardFeatureBoundaryTests() {
    print("\n🧪 Testing 剪贴板服务层跨 target 边界（端口注入 / 粘贴栈状态机 / 缓存端口 / 源码边界）...")
    testPortsRequireInjectedDependencies()
    testPasteOutcomeMessages()
    testPasteStackStateMachineInFeatureTarget()
    testThumbnailCachePortInFeatureTarget()
    testSourceBoundaries()
    print("✅ 剪贴板服务层跨 target 边界 works")
}

// MARK: - 端口替身

/// 采集偏好替身：端口只有 6 个键，替身直接实现（不依赖 App 的偏好聚合类）
private final class ClipboardBoundaryPreferences: ClipboardCapturePreferences,
                                                 ClipboardOCRPreferences,
                                                 @unchecked Sendable {
    var captureMode: ClipboardCaptureMode = .polling
    var isPaused = false
    var pausedUntil: Date = .distantPast
    var ignoredBundleIDs: Set<String> = []
    var lastExternalBundleID: String?
    var imageOCRRecognizeEnabled = true

    /// 与 App 侧 ClipboardPreferences 同一口径：定时到点即视为未暂停
    var isPausedNow: Bool {
        guard isPaused else { return false }
        guard pausedUntil.timeIntervalSince1970 > 0 else { return true }
        return Date() < pausedUntil
    }
}

/// 写回替身：只记录写了哪几条，不碰真实系统剪贴板
@MainActor
private final class ClipboardBoundaryWriter: ClipboardWriter {
    private(set) var writtenIDs: [UUID] = []

    @discardableResult
    func write(_ item: ClipboardItem, asPlainText: Bool) -> Bool {
        writtenIDs.append(item.id)
        return true
    }

    @discardableResult
    func writeText(_ text: String) -> Bool { true }

    func beginInternalWrite() {}
    func endInternalWrite() {}
}

/// 缩略图缓存替身：只数读写次数，用来证明命中路径不再走后台解码
@MainActor
private final class ClipboardBoundaryThumbnailCache: ClipboardThumbnailCaching {
    fileprivate(set) var images: [String: NSImage] = [:]
    fileprivate(set) var readCount = 0

    func thumbnail(forKey key: String) -> NSImage? {
        readCount += 1
        return images[key]
    }

    func store(_ image: NSImage, forKey key: String, cost: Int) {
        images[key] = image
    }
}

/// 识别替身：本组只验证端口注入与公开面，不真跑 Vision
private final class ClipboardBoundaryRecognizer: SnipTextRecognizing {
    func recognize(in image: SnipTextRecognitionImage) async throws -> [SnipTextLine] { [] }
}

// MARK: - 依赖注入（logger / 缓存 / 偏好必传）

@MainActor
private func testPortsRequireInjectedDependencies() {
    let logger = RecordingLogger()
    let preferences = ClipboardBoundaryPreferences()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bsfeng.macmonitor.clipboard.boundary"))
    let database = DatabaseManager()
    database.initializeInMemory()

    // 这几行能编译即证明三件事：服务对象的构造器已跨 target 公开；
    // logger 没有默认值（不再默认取 App 层的 AppContext.shared.logger）；
    // 缩略图缓存与采集偏好都走端口，不认 App 的具体类。
    let watcher = PasteboardWatcher(preferences: preferences, logger: logger, pasteboard: pasteboard)
    let writer = PasteboardWriter(logger: logger)
    let paster = ClipboardPaster(writer: writer, preferences: preferences, logger: logger)
    let stack = PasteStackController(repository: database, writer: writer, logger: logger)
    let loader = ClipboardThumbnailLoader(logger: logger, cache: ClipboardBoundaryThumbnailCache())
    let ocr = ClipboardOCRCoordinator(recognizer: ClipboardBoundaryRecognizer(),
                                      repository: database,
                                      preferences: preferences,
                                      logger: logger)

    assertEqual(watcher.isRunning, false, "未 start 时不采集（构造不产生副作用）")
    assertEqual(watcher.isPaused, false, "默认未暂停（读的是注入的偏好端口）")
    assertEqual(paster.hasTargetApplication, false, "未记录目标 App 时降级为仅复制")
    assertEqual(stack.remainingCount, 0, "新栈为空")
    loader.cancelAll()   // 公开面：取消在途解码（面板收起时由 App 直接驱动）
    ocr.cancelAll()
    assertEqual(logger.all.isEmpty, true, "仅构造不运行时不产生日志")

    watcher.stop()
    stack.stop()
}

// MARK: - 粘贴结果文案

@MainActor
private func testPasteOutcomeMessages() {
    assertEqual(ClipboardPasteOutcome.pasted.message, "", "成功粘贴不出提示")
    assertEqual(ClipboardPasteOutcome.copiedOnly("需要辅助功能权限才能自动粘贴，内容已复制").message,
                "需要辅助功能权限才能自动粘贴，内容已复制", "降级只复制的文案原样透出")
    assertEqual(ClipboardPasteOutcome.failed("写入剪贴板失败").message, "写入剪贴板失败",
                "失败文案原样透出（不静默）")
}

// MARK: - 粘贴栈状态机

@MainActor
private func testPasteStackStateMachineInFeatureTarget() {
    let logger = RecordingLogger()
    let database = DatabaseManager()
    database.initializeInMemory()
    let writer = ClipboardBoundaryWriter()
    let stack = PasteStackController(repository: database, writer: writer, logger: logger)
    stack.start()

    assertEqual(stack.accessibilityGranted, PasteStackController.probeAccessibility(),
                "启动时读到的授权态与静默探测一致（不自己另编一份判据）")
    // 强制放行入栈：测试进程通常没有辅助功能授权，状态机断言不该被权限态挡住
    stack.syncAccessibility(true)

    let first = UUID()
    let second = UUID()
    assertEqual(stack.push(id: first), true, "有授权即可入栈")
    assertEqual(stack.push(id: second), true, "第二条入栈")
    assertEqual(stack.orderedIDs, [first, second], "入栈追加到队尾（顺序即粘贴顺序）")
    assertEqual(stack.push(id: first), true, "重复入栈幂等（返回成功）")
    assertEqual(stack.orderedIDs, [first, second], "重复入栈不改变顺序")
    assertEqual(stack.remainingCount, 2, "剩余条数只数不重复的条目")
    assertEqual(stack.stackTotal, 2, "累计入栈条数作分母")
    assertEqual(stack.contains(id: second), true, "在栈判定按 id")

    stack.advanceOnPaste()
    assertEqual(stack.orderedIDs, [second], "推进 = 弹出队首，其余整体前移")
    assertEqual(stack.remainingCount, 1, "推进后剩余条数减一")
    assertEqual(stack.stackTotal, 2, "累计入栈条数不清零（分母保持）")

    stack.removeAll()
    assertEqual(stack.orderedIDs, [], "清空后无剩余")
    assertEqual(stack.stackTotal, 0, "清空后累计归零")

    stack.syncAccessibility(false)
    stack.stop()
}

// MARK: - 缩略图缓存端口

@MainActor
private func testThumbnailCachePortInFeatureTarget() {
    let cache = ClipboardBoundaryThumbnailCache()
    let loader = ClipboardThumbnailLoader(logger: RecordingLogger(), cache: cache)
    let image = NSImage(size: NSSize(width: 4, height: 4))
    cache.images["hash-cached"] = image

    var received: NSImage?
    loader.request(contentHash: "  hash-cached  ", imagePath: nil) { received = $0 }
    assertNotNil(received, "缓存命中即同步回调（不再入后台队列）")
    assertEqual(received === image, true, "回调的就是缓存里那张图（端口存取同一实例）")
    assertEqual(cache.readCount, 1, "命中路径只读一次缓存")
    assertEqual(cache.images.keys.contains("hash-cached"), true, "命中不重写缓存")

    var second: NSImage?
    loader.request(contentHash: "   ", imagePath: nil) { second = $0 }
    assertEqual(second == nil, true, "空内容哈希不请求、不回调")
    assertEqual(cache.readCount, 1, "空哈希连缓存都不查")

    loader.cancelAll()
    assertEqual(cache.readCount, 1, "cancelAll 不碰缓存（只清在途登记与排期）")
}

// MARK: - 源码边界（拆干净）

@MainActor
private func testSourceBoundaries() {
    let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // TestRunner
        .deletingLastPathComponent()   // Sources

    let movedFiles = ["PasteboardWatcher.swift", "PasteboardWatcher+Images.swift",
                      "ClipboardPaster.swift", "PasteStackController.swift",
                      "ClipboardImageStore.swift", "ClipboardImageGC.swift",
                      "ClipboardImagePipeline.swift", "ClipboardThumbnailLoader.swift",
                      "ClipboardOCRCoordinator.swift", "UserActivityMonitor.swift"]
    let appClipboard = sourcesRoot.appendingPathComponent("NetworkMonitor/Clipboard")
    let appFiles = Set(((try? FileManager.default.contentsOfDirectory(atPath: appClipboard.path)) ?? [])
        .filter { $0.hasSuffix(".swift") })
    for moved in movedFiles {
        assertEqual(appFiles.contains(moved), false, "App target 里不再有 " + moved)
    }
    // 面板暂停入口仍在 App（它扩展的是 ClipboardPanelController，属 UI 层）
    assertEqual(appFiles.contains("ClipboardPauseControl.swift"), true, "面板侧暂停接线留在 App")

    let featureDirectory = sourcesRoot.appendingPathComponent("NetworkMonitorFeatureClipboard")
    let featureFiles = ((try? FileManager.default.contentsOfDirectory(atPath: featureDirectory.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()
    assertEqual(featureFiles.count, 15, "新 target 15 个文件（10 整搬 + 暂停扩展 + 采集模式 + 3 端口）")
    for moved in movedFiles {
        assertEqual(featureFiles.contains(moved), true, moved + " 在新 target 里只此一份")
    }
    assertEqual(featureFiles.contains("PasteboardWatcher+Pause.swift"), true, "暂停状态机随采集器一起搬走")

    // 功能层不取 AppContext.shared：logger / 偏好 / 缓存一律由调用方注入
    // 只看代码行：文件头的注释会写「不取 AppContext.shared」，那是说明不是调用
    let appContextUsers = featureTexts(featureDirectory).filter { entry in
        codeLines(entry.text).contains { $0.contains("AppContext.shared") }
    }
    assertEqual(appContextUsers.map(\.file), [], "新 target 不出现 AppContext.shared（logger 显式注入）")

    // 不反向依赖 App：面板 / 卡片 / 设计令牌一个都不许出现在功能层
    let uiTypes = ["final class ClipboardPanelController", "final class ClipboardPanelView",
                   "final class ClipboardCardView", "enum PaneCardStyle"]
    let uiLeaks = featureTexts(featureDirectory).filter { entry in
        uiTypes.contains { entry.text.contains($0) }
    }
    assertEqual(uiLeaks.map(\.file), [], "新 target 不定义 / 不引用 App 的 UI 类型")

    // 允许 AppKit（NSPasteboard / NSRunningApplication 绕不开），但只在这几个采集 / 写回 / 解码 / 监听文件里
    let appKitFiles = featureTexts(featureDirectory)
        .filter { $0.text.contains("import AppKit") }
        .map(\.file)
        .sorted()
    assertEqual(appKitFiles, ["ClipboardPaster.swift", "ClipboardThumbnailCaching.swift",
                              "ClipboardThumbnailLoader.swift", "PasteStackController.swift",
                              "PasteboardWatcher+Images.swift", "PasteboardWatcher.swift",
                              "UserActivityMonitor.swift"],
                "AppKit 依赖集中在采集 / 写回 / 解码 / 监听四处")

    // App 侧两处适配：偏好聚合类 conformance + 缩略图缓存端口适配器
    let portsPath = sourcesRoot.appendingPathComponent("NetworkMonitor/Clipboard/ClipboardPreferences+ServicePorts.swift")
    let portsText = (try? String(contentsOf: portsPath, encoding: .utf8)) ?? ""
    assertEqual(portsText.contains("extension ClipboardPreferences: ClipboardCapturePreferences {}"), true,
                "采集偏好端口由 App 的偏好聚合类一行 conformance")
    assertEqual(portsText.contains("extension ClipboardPreferences: ClipboardOCRPreferences {}"), true,
                "识别开关端口同一处 conformance")

    let cachePath = sourcesRoot.appendingPathComponent("NetworkMonitor/Clipboard/ClipboardThumbnailCachePort.swift")
    let cacheText = (try? String(contentsOf: cachePath, encoding: .utf8)) ?? ""
    assertEqual(cacheText.contains("final class ClipboardCardThumbnailCache: ClipboardThumbnailCaching"), true,
                "缩略图缓存端口由 App 侧的 NSCache 适配器实现")
    assertEqual(cacheText.contains("static let shared = ClipboardThumbnailLoader("), true,
                "共享解码器改由 App 侧装配（服务层不持单例、不取 AppContext）")

    // 依赖方向：新 target 只依赖 Core，且按需链接 ApplicationServices
    let manifestPath = sourcesRoot.deletingLastPathComponent().appendingPathComponent("Package.swift")
    let manifest = (try? String(contentsOf: manifestPath, encoding: .utf8)) ?? ""
    assertEqual(manifest.contains("NetworkMonitorFeatureClipboard"),
                true, "包清单里登记了新 target")
    assertEqual(manifest.contains(".linkedFramework(\"ApplicationServices\")"),
                true, "按需链接 ApplicationServices（合成 ⌘V / 辅助功能判定）")
}

/// 只取代码行（去掉整行注释与空行）：注释里提到某个类型名不算依赖
private func codeLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }
}

/// 读一目录下的 Swift 正文（相对文件名 + 内容，供源码层断言用）
private func featureTexts(_ directory: URL) -> [(file: String, text: String)] {
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()
    return names.map { name in
        let text = (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return (name, text)
    }
}

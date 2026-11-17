#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 筛选芯片取证（来源 App + 日期，仅 DEBUG）

/// 筛选芯片的离屏取证 —— 同一批夹具在「无筛选」与「来源芯片 + 日期芯片」两种状态下各渲染一张
///
/// 触发：`NM_SNAPSHOT_CLIPBOARD_FILTER=1 NM_SNAPSHOT_DIR=/tmp/<dir> <bundle 内可执行>`
/// 产出：`panel-clipboard-filter-off.png` / `panel-clipboard-filter-on.png` 与一份计数自证文本。
///
/// 存在理由：芯片是否真的把列表筛小，截图看不出来（卡片本来就少）；必须同时给出过滤前后条数，
/// 且这两个数由产品自己的 `ClipboardFilterMatcher` 算出来，而不是取证代码各写一套。
@MainActor
enum SnapshotClipboardFilter {

    /// 取证开关（与 NM_SNAPSHOT_DIR 组合使用）
    static let envKey = "NM_SNAPSHOT_CLIPBOARD_FILTER"

    /// 画布尺寸（与其余剪贴板取证同一份）
    private static let canvasSize = SnapshotClipboardPanel.panelSize

    /// 取证入口：开关打开时出「无筛选 / 有筛选」两张图 + 计数自证
    static func captureIfRequested(directory: URL) {
        guard ProcessInfo.processInfo.environment[envKey]?.isEmpty == false else { return }
        let logger = AppContext.shared.logger
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("筛选取证目录创建失败：\(error.localizedDescription)")
            return
        }
        let now = SnapshotClock.now
        let items = makeFixtureItems(now: now)
        // 两枚芯片：来源 App + 日期；叠加口径与面板里完全一致
        let tokens = [ClipboardFilterToken.source("Safari"), ClipboardFilterToken.date(.today)]
        let filtered = items.filter { ClipboardFilterMatcher.matches($0, tokens: tokens, now: now) }

        render(items: items, tokens: [], size: canvasSize,
               to: directory.appendingPathComponent("panel-clipboard-filter-off.png"))
        render(items: filtered, tokens: tokens, size: canvasSize,
               to: directory.appendingPathComponent("panel-clipboard-filter-on.png"))
        writeStatus(directory: directory, total: items.count, shown: filtered.count,
                    tokens: tokens, logger: logger)
    }

    /// 渲染一个面板态：先灌芯片再布局，保证芯片矩形与搜索框位置都是真实排版结果
    private static func render(items: [ClipboardItem], tokens: [ClipboardFilterToken],
                               size: NSSize, to url: URL) {
        let canvas = SnapshotClipboardPanel(size: size, items: items).makeView()
        if let panel = canvas.subviews.compactMap({ $0 as? ClipboardPanelView }).first {
            panel.setFilterTokens(tokens)
            panel.updateCounts(total: items.count, pinned: items.filter(\.isPinned).count)
        }
        canvas.layoutSubtreeIfNeeded()
        MenuPanelSnapshot.render(view: canvas, size: size, appearanceName: .aqua, to: url)
    }

    // MARK: - 夹具

    /// 三条来源 / 三个时间档的文本条目（覆盖「来源命中但日期不命中」这类边界）
    private static func makeFixtureItems(now: Date) -> [ClipboardItem] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: todayStart) ?? todayStart
        // 「今天」的夹具取今天 00:01 而不是「now − 2 分钟」：取证常在午夜附近跑，后者会掉到昨天
        let todaySlot = todayStart.addingTimeInterval(60)
        let specs: [(text: String, app: String, bundle: String, at: Date)] = [
            ("https://api.example.com/v1/status 今天复制", "Safari", "com.apple.Safari", todaySlot),
            ("三天前的 Safari 页面标题", "Safari", "com.apple.Safari", threeDaysAgo),
            ("今天从终端复制的命令", "终端", "com.apple.Terminal", todaySlot.addingTimeInterval(120)),
        ]
        return specs.enumerated().map { index, spec in
            ClipboardItem(kind: .text, text: spec.text, preview: spec.text,
                          contentHash: ClipboardContentHasher.hash(text: spec.text) ?? "filter-fixture-\(index)",
                          sourceBundleID: spec.bundle, sourceAppName: spec.app,
                          createdAt: spec.at)
        }
    }

    // MARK: - 自证文本

    /// 计数自证：过滤前后的条数与生效芯片（截图之外的第二份证据）
    private static func writeStatus(directory: URL, total: Int, shown: Int,
                                    tokens: [ClipboardFilterToken], logger: LoggingService) {
        let text = """
        fixture_items = \(total)
        chips = \(tokens.map { $0.kind.menuTitle + ":" + $0.label }.joined(separator: " + "))
        matched_items = \(shown)
        filtered_out = \(total - shown)
        counts_label = \(ClipboardPanelFooterText.countsLabel(total: shown, pinned: 0))
        """ + "\n"
        let url = directory.appendingPathComponent("panel-clipboard-filter-status.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("筛选取证状态写入失败：\(error.localizedDescription)")
        }
        logger.info("筛选取证完成：\(total) 条 → \(shown) 条")
    }
}
#endif

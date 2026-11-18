#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板卡片状态取证（hover / 多选）

/// 三段式卡片的两条交互态取证 —— **仅 DEBUG**
///
/// 触发：`NM_SNAPSHOT_CLIPBOARD_STATES=1 NM_SNAPSHOT_DIR=/tmp/<dir> <bundle 内可执行>`
/// 产出（640×388，与 `SnapshotClipboardPanel.panelSize` 同口径）：
/// 1. `panel-clipboard-hover.png`：第 2 张卡处于 hover（提亮 + 1.5pt 描边 + 容器投影）
/// 2. `panel-clipboard-multiselect.png`：第 1–3 张卡同时选中（2pt accent 描边 + 6% 叠色 + 详情区改多选摘要）
///
/// 为什么单独一个开关：`SnapshotClipboardEvidence` 出的是「内容链路」三张（首帧 / 就绪 / 删除提示），
/// 交互态与它无关，混进同一条链路会让那次取证的时间序依赖变复杂。
@MainActor
enum SnapshotClipboardCardStates {

    /// 取证开关（与 `NM_SNAPSHOT_DIR` 组合使用）
    static let envKey = "NM_SNAPSHOT_CLIPBOARD_STATES"

    /// 画布尺寸（与其余剪贴板取证同一份）
    private static let canvasSize = SnapshotClipboardPanel.panelSize

    /// 取证入口：未开开关立即返回
    static func captureIfRequested(directory: URL) {
        guard ProcessInfo.processInfo.environment[envKey]?.isEmpty == false else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            AppContext.shared.logger.error("卡片状态取证目录创建失败：\(error.localizedDescription)")
            return
        }
        let items = makeItems()
        guard items.count >= 3 else { return }

        // hover：只置第 2 张
        let hoverCanvas = SnapshotClipboardPanel(size: canvasSize, items: items).makeView(hoveredIndex: 1)
        MenuPanelSnapshot.render(view: hoverCanvas, size: canvasSize, appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-hover.png"))

        // 多选：第 1–3 张一起选中
        let multi = Set(items.prefix(3).map(\.id))
        let multiCanvas = SnapshotClipboardPanel(size: canvasSize, items: items).makeView(selectedIDs: multi)
        MenuPanelSnapshot.render(view: multiCanvas, size: canvasSize, appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-multiselect.png"))
    }

    /// 四条夹具：链接 / 文本 / 图片 / 文件各一（覆盖四种卡头色与三种卡身渲染）
    private static func makeItems() -> [ClipboardItem] {
        let now = SnapshotClock.now
        let link = ClipboardItem(kind: .text,
                                 text: "https://pasteapp.io/what-paste-captures",
                                 preview: "https://pasteapp.io/what-paste-captures",
                                 contentHash: "states-link",
                                 sourceBundleID: "com.apple.Safari", sourceAppName: "Safari",
                                 createdAt: now.addingTimeInterval(-180))
        let text = ClipboardItem(kind: .text,
                                 text: "明天的评审挪到下午三点，会议室换到 3 楼东侧。别忘了带原型链接。",
                                 preview: "明天的评审挪到下午三点，会议室换到 3 楼东侧。别忘了带原型链接。",
                                 contentHash: "states-text",
                                 sourceBundleID: "com.tencent.xinWeChat", sourceAppName: "微信",
                                 createdAt: now.addingTimeInterval(-720))
        let image = ClipboardItem(kind: .image, preview: "图片 2400×1600",
                                  imagePath: "/tmp/states-截图 2026-11-18 21.04.png",
                                  imageWidth: 2400, imageHeight: 1600,
                                  contentHash: "states-image",
                                  sourceBundleID: "com.apple.finder", sourceAppName: "访达",
                                  copyCount: 2, createdAt: now.addingTimeInterval(-3600))
        let file = ClipboardItem(kind: .file,
                                 text: "/Users/x/Documents/一览-设计规格.pdf",
                                 preview: "/Users/x/Documents/一览-设计规格.pdf",
                                 contentHash: "states-file",
                                 sourceBundleID: "com.apple.finder", sourceAppName: "访达",
                                 createdAt: now.addingTimeInterval(-7200))
        return [link, text, image, file]
    }
}
#endif

#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板卡片交互自证（仅 DEBUG）

/// 整卡自绘后的交互自证 —— 一张真实绘制的卡片图 + 一份逐项断言文本
///
/// 触发：`NM_CLIPBOARD_CARD_PROBE=<输出目录>`
/// 产出：
/// - `clipboard-card-probe.png`：4 张卡（选中 / 收藏 + 栈角标 / 缩略图就绪 / 普通）真实绘制；
/// - `clipboard-card-probe.txt`：命中区域 → 动作、右键五项菜单、无障碍上报、选中过渡值。
///
/// 为什么不用合成鼠标事件：离屏窗口不接收事件，直接调用 mouseDown 覆盖不到 AppKit 的
/// 命中与菜单分发；这里用「同一套纯函数 + 真实视图属性」自证，事件分发本身仍走
/// ClipboardCardView+Interaction（与纯函数一一对应）。
@MainActor
enum ClipboardCardProbe {

    /// 探针开关
    static let envKey = "NM_CLIPBOARD_CARD_PROBE"

    static func runIfRequested() -> Bool {
        guard let directory = ProcessInfo.processInfo.environment[envKey], !directory.isEmpty else {
            return false
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let cards = makeCards()
        let report = makeReport(cards: cards)
        try? report.write(to: url.appendingPathComponent("clipboard-card-probe.txt"),
                          atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(report.utf8))

        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 4 * 186, height: 210))
        canvas.wantsLayer = true
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: CGFloat(index) * 186 + 5, y: 6, width: 176, height: 198)
            canvas.addSubview(card)
        }
        MenuPanelSnapshot.render(view: canvas,
                                 size: NSSize(width: 4 * 186, height: 210),
                                 appearanceName: .aqua,
                                 to: url.appendingPathComponent("clipboard-card-probe.png"))
        // 第二张：第 3 张卡进入 hover 态（提亮 + 加粗描边 + 容器投影）
        cards[2].applyHover(true, animated: false)
        cards[2].onShadowStateChange?()
        MenuPanelSnapshot.render(view: canvas,
                                 size: NSSize(width: 4 * 186, height: 210),
                                 appearanceName: .aqua,
                                 to: url.appendingPathComponent("clipboard-card-probe-hover.png"))
        exit(0)
    }

    // MARK: 夹具

    private static func makeCards() -> [ClipboardCardView] {
        let now = Date()
        let text = ClipboardItem(kind: .text,
                                 text: "curl -I https://api.example.com/v1/status",
                                 preview: "curl -I https://api.example.com/v1/status",
                                 contentHash: "probe-text-1",
                                 sourceBundleID: "com.apple.Terminal", sourceAppName: "终端",
                                 createdAt: now.addingTimeInterval(-600))
        let starred = ClipboardItem(kind: .text,
                                    text: "收藏并进入 Paste Stack 的条目",
                                    preview: "收藏并进入 Paste Stack 的条目",
                                    contentHash: "probe-text-2",
                                    sourceBundleID: "com.apple.Notes", sourceAppName: "备忘录",
                                    isPinned: true,
                                    createdAt: now.addingTimeInterval(-120),
                                    stackPosition: 2)
        let image = ClipboardItem(kind: .image,
                                  preview: "图片 5120×2880",
                                  imagePath: "/tmp/probe.png",
                                  imageWidth: 5120, imageHeight: 2880,
                                  contentHash: "probe-image-hash",
                                  sourceBundleID: "com.apple.Safari", sourceAppName: "Safari",
                                  createdAt: now.addingTimeInterval(-30))
        let plain = ClipboardItem(kind: .file,
                                  text: "/Users/probe/Documents/设计稿.png",
                                  preview: "设计稿.png",
                                  contentHash: "probe-file-1",
                                  sourceBundleID: "com.apple.finder", sourceAppName: "访达",
                                  createdAt: now.addingTimeInterval(-7200))

        if let thumbnail = makeThumbnail() {
            ClipboardCardView.thumbnailCache.setObject(thumbnail,
                                                       forKey: "probe-image-hash" as NSString,
                                                       cost: 64 * 64 * 4)
        }

        let items = [image, starred, text, plain]
        return items.enumerated().map { index, item in
            let card = ClipboardCardView(frame: NSRect(x: 0, y: 0, width: 176, height: 198))
            card.configure(with: item, isSelected: index == 0, number: index + 1)
            return card
        }
    }

    private static func makeThumbnail() -> NSImage? {
        let size = NSSize(width: 64, height: 64)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: 64, pixelsHigh: 64,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: [.systemTeal, .systemBlue])?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        NSGraphicsContext.restoreGraphicsState()
        return NSImage(size: size, flipped: false) { rect in
            rep.draw(in: rect)
            return true
        }
    }

    // MARK: 自证文本

    private static func makeReport(cards: [ClipboardCardView]) -> String {
        var lines = ["# 剪贴板卡片交互自证", ""]
        guard let first = cards.first else { return lines.joined(separator: "\n") }

        // 星标与角标只在带对应状态的卡片上存在，采集点按该卡的真实几何算
        let starCard = cards.count > 2 ? cards[2] : first
        let badgeCard = cards.count > 1 ? cards[1] : first
        let starPoint = CGPoint(x: ClipboardCardGeometry.starRect(in: first.bounds,
                                                                  shortcutWidth: starCard.shortcutWidth).midX,
                                y: ClipboardCardGeometry.starRect(in: first.bounds,
                                                                  shortcutWidth: starCard.shortcutWidth).midY)
        let badgeRect = ClipboardCardGeometry.badgeRect(in: badgeCard.bounds, badgeSize: badgeCard.badgeSize)
        lines.append("## 命中区域 → 动作（卡内坐标，176×198）")
        let points: [(String, ClipboardCardView, CGPoint)] = [
            ("正文中心（图片卡）", first, CGPoint(x: 88, y: 88)),
            ("正文中心（文本卡）", starCard, CGPoint(x: 88, y: 88)),
            ("meta 行", first, CGPoint(x: 100, y: 180)),
            ("收藏星", starCard, starPoint),
            ("角标", badgeCard, CGPoint(x: badgeRect.midX, y: badgeRect.midY)),
        ]
        for (name, card, point) in points {
            let region = card.hitRegion(at: point)
            let single = ClipboardCardHitTest.action(for: region, clickCount: 1, isContextMenu: false)
            let double = ClipboardCardHitTest.action(for: region, clickCount: 2, isContextMenu: false)
            let context = ClipboardCardHitTest.action(for: region, clickCount: 1, isContextMenu: true)
            lines.append("- \(name) @(\(Int(point.x)),\(Int(point.y))) → 区域 \(region)：单击 \(single) / 双击 \(double) / 右键 \(context)")
        }

        lines.append("")
        lines.append("## 右键菜单（五项固定顺序）")
        if let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                                          modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 0),
           let menu = first.menu(for: event) {
            for (index, item) in menu.items.enumerated() {
                lines.append("- \(index + 1). \(item.title)（tag=\(item.tag)，state=\(item.state == .on ? "on" : "off")，id=\(item.representedObject == nil ? "nil" : "有")）")
            }
        } else {
            lines.append("- 菜单构造失败")
        }

        lines.append("")
        lines.append("## 无障碍上报")
        for (index, card) in cards.enumerated() {
            lines.append("- 卡片 \(index + 1)：role=\(card.accessibilityRole()?.rawValue ?? "nil") "
                         + "label=\(card.accessibilityLabel() ?? "nil") "
                         + "value=\(card.accessibilityValue() as? String ?? "") "
                         + "isElement=\(card.isAccessibilityElement())")
        }
        // 探针夹具没有挂卡片流回调，先补一个与真实卡片流等价的单击回调再验证读屏激活
        first.onClickWithModifiers = { _, _ in }
        let pressed = first.accessibilityPerformPress()
        lines.append("- accessibilityPerformPress 可用：\(pressed)（等同单击选中）")

        lines.append("")
        lines.append("## 卡片状态")
        for (index, card) in cards.enumerated() {
            lines.append("- 卡片 \(index + 1)：selected=\(card.isSelected) "
                         + "shortcutWidth=\(String(format: "%.1f", card.shortcutWidth)) "
                         + "badgeSize=\(card.badgeSize) "
                         + "thumbnail=\(card.thumbnail == nil ? "占位" : "真图") "
                         + "starBlend=\(String(format: "%.2f", card.starPopBlend.value)) "
                         + "badgeBlend=\(String(format: "%.2f", card.badgePopBlend.value))")
        }

        let target = cards[1]
        target.setSelected(true)
        lines.append("")
        lines.append("## 选中切换（setSelected(true)，离屏不播过渡直接落终态）")
        lines.append("- 卡片 2 selected=\(target.isSelected)，selectionBlend=\(String(format: "%.2f", target.selectionBlend.value))")

        // hover 推进：目标走 DrawnHoverState（进入 / 退出各一条路径），过渡值走 DrawnBlend
        lines.append("")
        lines.append("## hover 推进（目标：DrawnHoverState，过渡：DrawnBlend）")
        let hoverCard = cards[2]
        hoverCard.applyHover(true, animated: false)
        lines.append("- 进入 hover：isHovering=\(hoverCard.isHovering)，"
                     + "hoverBlend=\(String(format: "%.2f", hoverCard.hoverBlend.value))（期望 true / 1.00）")
        hoverCard.applyHover(true, animated: false)
        lines.append("- 重复进入（目标未变）：hoverBlend=\(String(format: "%.2f", hoverCard.hoverBlend.value))（期望 1.00，不重启过渡）")
        hoverCard.applyHover(false, animated: false)
        lines.append("- 退出 hover：isHovering=\(hoverCard.isHovering)，"
                     + "hoverBlend=\(String(format: "%.2f", hoverCard.hoverBlend.value))（期望 false / 0.00）")
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif

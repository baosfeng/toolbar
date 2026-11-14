#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 自绘组件取证（仅 DEBUG）

/// 把自绘行列表离屏渲染成 PNG —— 用于核对「自绘组件」与现有 AppKit 组件是否同一套视觉
///
/// 触发：`NM_DRAWN_PROBE=<输出目录>`（需打包成 .app 后跑包内可执行文件，见踩坑「快照取证需打包成 app」）
@MainActor
enum DrawnUIProbe {

    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["NM_DRAWN_PROBE"] else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let list = DrawnRowList()
        list.rowSpacing = 2
        list.rows = [
            DrawnRowSpec(title: "未缓存输入", value: "1.24M", progress: 0.62),
            DrawnRowSpec(title: "缓存输入", value: "8.41M", progress: 0.81, tone: .strong),
            DrawnRowSpec(title: "缓存写入", value: "340K", progress: 0.12),
            DrawnRowSpec(title: "输出", value: "96.2K", progress: 0.05),
            DrawnRowSpec(title: "剩余额度", value: "12%", progress: 0.12, tone: .warning),
            DrawnRowSpec(title: "今日 Token 合计", value: "12.4M", tone: .strong),
            DrawnRowSpec(title: "本机下载 / 上传", value: "1.2M / 348K"),
            DrawnRowSpec(title: "这一行故意写了一个长到一定会被截断的行名用来验证尾部省略号与进度条的让位行为", value: "3.1%", progress: 0.031),
            DrawnRowSpec(title: "可点击行（悬停与焦点态）", value: "查看", tone: .strong, isActionable: true),
        ]
        list.focusedIndex = 8

        // 诊断：把每行的宽度分配打出来（取证图只用于看视觉，数字以这里为准）
        for (i, row) in list.rows.enumerated() {
            let m = DrawnRowLayout.metrics(rowWidth: 340,
                                           leadingInset: list.horizontalInset,
                                           trailingInset: list.horizontalInset,
                                           titleWidth: DrawnTextRun(string: row.title, font: PaneCardStyle.rowNameFont, color: .labelColor).width(),
                                           valueWidth: DrawnTextRun(string: row.value, font: PaneCardStyle.rowValueFont, color: .labelColor).width(),
                                           gap: list.elementGap,
                                           hasProgress: row.progress != nil,
                                           minBarWidth: list.minBarWidth)
            FileHandle.standardError.write(Data("row \(i) bar=\(Int(m.barWidth)) title=\(Int(m.titleWidth)) value=\(Int(m.valueWidth))\n".utf8))
        }
        let width: CGFloat = 340
        let height = list.intrinsicContentSize.height
        list.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let canvas = NSRect(x: 0, y: 0, width: width, height: height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(width * 2),
                                         pixelsHigh: Int(height * 2),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        rep.size = canvas.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        NSColor.windowBackgroundColor.setFill()
        canvas.fill()
        // 卡片底（与 PaneCardStyle 同源）
        DrawnInk.fill(canvas.insetBy(dx: 2, dy: 2), radius: PaneCardStyle.cardRadius, color: PaneCardStyle.cardFill)
        list.displayIgnoringOpacity(list.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()

        let cardData = DrawnUIProbe.renderCard()
        if let cardData {
            try? cardData.write(to: url.appendingPathComponent("drawn-card.png"))
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let file = url.appendingPathComponent("drawn-rowlist.png")
        try? data.write(to: file)
        FileHandle.standardError.write(Data("DrawnUIProbe -> \(file.path)\n".utf8))
        exit(0)
    }

    /// 渲染一张自绘卡片（卡头 + 行列表），验证组合单元
    private static func renderCard() -> Data? {
        let card = DrawnCard()
        card.title = "输入与缓存"
        card.caption = "近 14 天"
        card.fillColor = PaneCardStyle.uncachedCardFill
        card.list.rowSpacing = 2
        card.list.rows = [
            DrawnRowSpec(title: "未缓存输入", value: "1.24M", progress: 0.62),
            DrawnRowSpec(title: "缓存输入", value: "8.41M", progress: 0.81, tone: .strong),
            DrawnRowSpec(title: "缓存命中率", value: "87.1%", progress: 0.871),
            DrawnRowSpec(title: "输出", value: "96.2K", progress: 0.05),
        ]
        let width: CGFloat = 300
        let height = card.intrinsicContentSize.height
        guard height > 0 else { return nil }
        card.frame = NSRect(x: 0, y: 0, width: width, height: height)
        card.layout()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(width * 2),
                                         pixelsHigh: Int(height * 2),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        card.displayIgnoringOpacity(card.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
#endif

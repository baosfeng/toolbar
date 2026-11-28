import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 底部详情区（几何 / 内容 / 面板分段）

/// 详情区与面板分段的守门测试
///
/// 背景（v2）：详情区不再是常驻段 —— 完整内容走「空格预览」，详情区只在 ⌘E / ⌘N 编辑期间
/// 作为浮层出现在面板底部。这里钉住三件事：
/// 1. 详情区高度恒定 —— 编辑浮层的几何与内容口径不变（文本全文 / 图片尺寸 / 元信息拼装）；
/// 2. 面板分段只剩两段 —— 工具条 + 卡片区，首尾相接、加起来等于面板高；
/// 3. 卡片尺寸随卡片区高度等比自适应，且守住上下限。
func runClipboardDetailStripTests() {
    print("🧪 Testing clipboard detail strip & panel sections...")

    // MARK: 详情区常量

    assertEqual(ClipboardDetailStrip.separatorHeight, 1, "详情区顶部分隔线 1pt")
    assertEqual(ClipboardDetailStrip.totalHeight,
                ClipboardDetailStrip.separatorHeight + ClipboardDetailStrip.contentHeight,
                "详情区整块高 = 分隔线 + 内容")
    assertEqual(ClipboardDetailStrip.contentHeight, 101, "内容高 101pt（上下 8 + 元信息 13 + 间距 4 + 正文 4 行）")
    // 正文可视高度按 12.5pt 系统字体（行高约 15–17）算出来正好 4 行
    assertEqual(ClipboardDetailStrip.bodyHeight, 68, "正文可视高度 68pt")
    assertEqual(ClipboardDetailStrip.bodyHeight >= 4 * 15, true, "68pt 至少容得下 4 行 12.5pt 正文")
    assertEqual(ClipboardDetailStrip.emptyText, "选中一条查看详情", "空态文案")
    assertEqual(ClipboardDetailStrip.bodyHeight,
                ClipboardDetailStrip.contentHeight - ClipboardDetailStrip.insetY * 2
                    - ClipboardDetailStrip.metaHeight - ClipboardDetailStrip.metaGap,
                "正文可视高度 = 内容高 − 上下内边距 − 元信息行 − 间距")

    // MARK: 内容：无选中

    let reference = Date(timeIntervalSince1970: 1_700_000_000)
    let empty = ClipboardDetailStrip.content(for: nil, now: reference)
    assertEqual(empty.body, "选中一条查看详情", "无选中显示空态文案")
    assertEqual(empty.meta, "", "无选中不给元信息（不留一行空白小字）")
    assertEqual(empty.isEmpty, true, "无选中标记为空态")

    // MARK: 内容：文本条目

    let longText = (1...20).map { "第 \($0) 行正文" }.joined(separator: "\n")
    let textItem = ClipboardItem(kind: .text,
                                text: longText,
                                preview: "第 1 行正文",
                                contentHash: "detail-text",
                                sourceAppName: "终端",
                                createdAt: reference.addingTimeInterval(-90))
    let textContent = ClipboardDetailStrip.content(for: textItem, now: reference)
    assertEqual(textContent.body, longText, "文本条目给完整正文（不提前截断，滚动交给视图）")
    assertEqual(textContent.isEmpty, false, "有选中不是空态")
    assertEqual(textContent.meta, "复制 1 次 · 文本 · 1 分钟前 · 终端",
                "元信息：复制次数 · 类型 · 相对时间 · 来源")

    // 正文缺失时退回摘要；都没有给「（空内容）」
    let previewOnly = ClipboardItem(kind: .text, preview: "只有摘要", contentHash: "detail-preview")
    assertEqual(ClipboardDetailStrip.bodyText(for: previewOnly), "只有摘要", "正文缺失退回摘要")
    let blank = ClipboardItem(kind: .text, text: "   \n ", preview: "", contentHash: "detail-blank")
    assertEqual(ClipboardDetailStrip.bodyText(for: blank), "（空内容）", "空白正文给占位文案")

    // 来源缺失：元信息不留尾部空段
    let noSource = ClipboardItem(kind: .text, text: "无来源", contentHash: "detail-nosource", createdAt: reference)
    let noSourceMeta = ClipboardDetailStrip.metaText(for: noSource, now: reference)
    assertEqual(noSourceMeta, "复制 1 次 · 文本 · 刚刚", "没有来源 App 时不留尾部「· 」")
    assertEqual(noSourceMeta.hasSuffix("· "), false, "元信息末尾没有悬空分隔符")

    // MARK: 内容：图片条目

    let image = ClipboardItem(kind: .image,
                              preview: "图片 1512×982",
                              imagePath: "/tmp/detail.png",
                              imageWidth: 1512, imageHeight: 982,
                              contentHash: "detail-image",
                              sourceAppName: "截图",
                              copyCount: 3,
                              createdAt: reference.addingTimeInterval(-7200))
    let imageContent = ClipboardDetailStrip.content(for: image, now: reference)
    assertEqual(imageContent.body, "图片 1512×982", "图片条目给尺寸摘要")
    assertEqual(imageContent.body.contains("�"), false, "图片摘要里没有解码失败的替换字符")
    assertEqual(imageContent.meta, "复制 3 次 · 图片 · 2 小时前 · 截图", "图片元信息按同口径拼装")

    // 尺寸缺失时退回既有摘要；连摘要都没有给「图片」
    let noSize = ClipboardItem(kind: .image, preview: "图片", contentHash: "detail-nosize")
    assertEqual(ClipboardDetailStrip.bodyText(for: noSize), "图片", "没有尺寸时退回摘要")
    let rejected = ClipboardItem(kind: .image, preview: "图片过大（18000×18000）", contentHash: "detail-rejected")
    assertEqual(ClipboardDetailStrip.bodyText(for: rejected), "图片过大（18000×18000）",
                "像素超限的占位条目把拒绝原因原样展示")

    // MARK: 类型名口径（详情区与菜单面板共用）

    let link = ClipboardItem(kind: .text, text: "https://example.com/x", contentHash: "detail-link")
    assertEqual(ClipboardItemKindLabel.label(for: link), "链接", "URL 文本显示为链接")
    let fileItem = ClipboardItem(kind: .file, text: "/tmp/a.swift", contentHash: "detail-file")
    assertEqual(ClipboardItemKindLabel.label(for: fileItem), "文件", "文件条目显示为文件")
    let rtfItem = ClipboardItem(kind: .rtf, text: "{\\rtf1}", contentHash: "detail-rtf")
    assertEqual(ClipboardItemKindLabel.label(for: rtfItem), "富文本", "RTF 显示为富文本")
    assertEqual(ClipboardItemKindLabel.label(for: textItem), "文本", "纯文本显示为文本")

    // MARK: 面板分段（v2：只剩工具条 + 卡片区）

    assertEqual(ClipboardPanelLayout.minPanelHeight,
                Double(ClipboardPanelLayout.toolbarHeight
                       + ClipboardCardGeometry.minCardHeight + ClipboardCardGeometry.cardSlack),
                "下限 = 工具条 + 最矮整卡 + 卡片区留白（没有详情区、没有提示行）")
    assertEqual(ClipboardPanelLayout.defaultPanelHeight > ClipboardPanelLayout.minPanelHeight, true,
                "默认高度高于下限：默认档给的是基准卡 198pt，不是压扁的最低档")

    let size = CGSize(width: 640, height: 400)
    let sections = ClipboardPanelLayout.sections(in: size)
    assertEqual(sections.toolbar.height, ClipboardPanelLayout.toolbarHeight, "工具条 34pt（单行）")
    assertEqual(sections.toolbar.minX, 0, "工具条整宽（自己管内边距）")
    assertEqual(sections.cards.minY, sections.toolbar.maxY, "卡片区紧跟工具条（没有第二行）")
    assertEqual(sections.cards.height, 400 - ClipboardPanelLayout.toolbarHeight, "卡片区吃掉剩余高度")
    assertEqual(sections.cards.maxY, 400, "卡片区直抵面板底（没有提示行）")
    assertEqual(sections.cards.minX, ClipboardPanelLayout.paddingX, "卡片区左右内缩")
    assertEqual(sections.separatorYs, [ClipboardPanelLayout.toolbarHeight], "只剩工具条底一条分隔线")

    let taller = ClipboardPanelLayout.sections(in: CGSize(width: 640, height: 500))
    assertEqual(taller.cards.height, sections.cards.height + 100, "增量全部给卡片区")

    // MARK: 卡片尺寸随卡片区高度自适应（Paste 的 Compact Mode 同口径）

    assertEqual(ClipboardCardGeometry.cardHeight(forCardAreaHeight: 400),
                400 - ClipboardCardGeometry.cardSlack, "卡片高 = 卡片区 − 留白")
    assertEqual(ClipboardCardGeometry.cardHeight(forCardAreaHeight: 120),
                ClipboardCardGeometry.minCardHeight, "卡片区过矮时卡片不缩到装不下卡头卡脚")
    assertEqual(ClipboardCardGeometry.cardHeight(forCardAreaHeight: 1000),
                ClipboardCardGeometry.maxCardHeight, "卡片区过高时卡片有上限")
    let defaultCard = ClipboardCardGeometry.cardSize(forCardAreaHeight:
        CGFloat(ClipboardPanelLayout.defaultPanelHeight - ClipboardPanelLayout.toolbarHeight))
    assertEqual(defaultCard.height, ClipboardCardGeometry.baseCardHeight,
                "默认档的卡片正好是设计基准卡（227×198，与 Paste 243×212 同量级）")
    assertEqual(defaultCard.width, ClipboardCardGeometry.baseCardWidth,
                "默认档的卡片宽度 = 基准宽（不再被上限截成竖卡）")
    // 宽度上限改成「反推高度」后，任何面板高度下比例都不失真：宽封顶 → 高也停住
    for cardAreaHeight in [180.0, 400.0, 1000.0] {
        let card = ClipboardCardGeometry.cardSize(forCardAreaHeight: CGFloat(cardAreaHeight))
        assertEqual(abs(card.width / card.height - ClipboardCardGeometry.aspectRatio) < 0.01, true,
                    "卡片区 \(cardAreaHeight) 下仍按基准比例等比（宽度封顶时高度一起停）")
        assertEqual(card.width <= ClipboardCardGeometry.maxCardWidth, true,
                    "卡片宽度不超过上限")
    }
    assertEqual(ClipboardCardGeometry.cardSize(forCardAreaHeight: 0).height,
                ClipboardCardGeometry.minCardHeight, "卡片区为 0 时也给出下限尺寸")

    // MARK: 高度夹紧

    assertEqual(ClipboardPanelLayout.clampedHeight(100), ClipboardPanelLayout.minPanelHeight,
                "低于下限抬到下限（否则整卡被裁）")
    assertEqual(ClipboardPanelLayout.clampedHeight(10_000), ClipboardPanelLayout.maxPanelHeight,
                "高于上限压到上限")
    assertEqual(ClipboardPanelLayout.clampedHeight(300), 300, "区间内原样返回")
    assertEqual(ClipboardPanelLayout.clampedHeight(0), ClipboardPanelLayout.defaultPanelHeight,
                "0（未设置）回落默认高度")

    // 默认高度下卡片区容得下整卡
    let defaultSections = ClipboardPanelLayout.sections(
        in: CGSize(width: 640, height: ClipboardPanelLayout.defaultPanelHeight))
    assertEqual(defaultSections.cards.height >= ClipboardCardGeometry.baseCardHeight, true,
                "默认高度下卡片区能露出整卡")


    print("✅ Clipboard detail strip & panel sections works")
}
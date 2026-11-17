import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 底部详情区（几何 / 内容 / 面板分段）

/// 详情区与面板分段的守门测试
///
/// 背景：悬停全文浮层下线后，完整内容常驻在面板底部。这里钉住三件事：
/// 1. 详情区高度恒定 —— 有没有选中、正文多长都不改高度，切条目时卡片区不跳；
/// 2. 内容口径 —— 文本给完整正文、图片给尺寸摘要、无选中给空态文案，元信息拼装不留空档；
/// 3. 面板分段 —— 四段在给定高度下首尾相接、加起来等于面板高，卡片区仍容得下整卡。
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

    // MARK: 面板分段

    assertEqual(ClipboardPanelLayout.minPanelHeight,
                32 + 198 + 6 + ClipboardDetailStrip.totalHeight + 24,
                "下限 = 工具条 + 整卡 + 留白 + 详情区 + 提示行")
    assertEqual(ClipboardPanelLayout.defaultPanelHeight, ClipboardPanelLayout.minPanelHeight,
                "默认高度等于下限：卡片区刚好容下整卡")

    let size = CGSize(width: 640, height: 400)
    let sections = ClipboardPanelLayout.sections(in: size)
    assertEqual(sections.toolbar.height, 32, "工具条 32pt")
    assertEqual(sections.footer.height, 24, "提示行 24pt")
    assertEqual(sections.detail.height, ClipboardDetailStrip.totalHeight, "详情区高度恒为详情区口径")
    assertEqual(sections.detail.minY, 400 - 24 - ClipboardDetailStrip.totalHeight,
                "详情区顶边 = 面板高 − 提示行 − 详情区")
    assertEqual(sections.footer.minY, 400 - 24, "提示行顶边贴面板底")
    assertEqual(sections.cards.minY, sections.toolbar.maxY, "卡片区紧跟工具条")
    assertEqual(sections.cards.maxY, sections.detail.minY, "卡片区底边贴详情区顶边（无缝隙）")
    assertEqual(sections.cards.height, 400 - 32 - ClipboardDetailStrip.totalHeight - 24, "卡片区为弹性段")
    assertEqual(sections.cards.minX, ClipboardPanelLayout.paddingX, "卡片区左右内缩")
    assertEqual(sections.toolbar.minX, 0, "工具条整宽（自己管内边距）")
    assertEqual(sections.detail.minX, 0, "详情区整宽（分隔线横贯面板）")

    // 四段首尾相接、无重叠
    assertEqual(sections.toolbar.maxY <= sections.cards.minY, true, "工具条与卡片区不重叠")
    assertEqual(sections.cards.maxY <= sections.detail.minY, true, "卡片区与详情区不重叠")
    assertEqual(sections.detail.maxY <= sections.footer.minY, true, "详情区与提示行不重叠")
    assertEqual(sections.footer.maxY, 400, "最后一段贴住面板底")

    // 面板层分隔线只有工具条底与提示行顶两条（详情区顶那条画在详情区自己身上）
    assertEqual(sections.separatorYs, [32, 376], "面板层分隔线：工具条底 / 提示行顶")

    // 高度只在卡片区变化：面板变高 100pt，详情区与提示行不动
    let taller = ClipboardPanelLayout.sections(in: CGSize(width: 640, height: 500))
    assertEqual(taller.detail.height, sections.detail.height, "面板变高不改详情区高度")
    assertEqual(taller.footer.minY, 476, "面板变高后提示行仍贴底")
    assertEqual(taller.cards.height, sections.cards.height + 100, "增量全部给卡片区")

    // MARK: 高度夹紧

    assertEqual(ClipboardPanelLayout.clampedHeight(100), ClipboardPanelLayout.minPanelHeight,
                "低于下限抬到下限（否则整卡被裁）")
    assertEqual(ClipboardPanelLayout.clampedHeight(10_000), ClipboardPanelLayout.maxPanelHeight,
                "高于上限压到上限")
    assertEqual(ClipboardPanelLayout.clampedHeight(420), 420, "区间内原样返回")
    assertEqual(ClipboardPanelLayout.clampedHeight(0), ClipboardPanelLayout.defaultPanelHeight,
                "0（未设置）回落默认高度")

    // 默认高度下卡片区容得下整卡
    let defaultSections = ClipboardPanelLayout.sections(
        in: CGSize(width: 640, height: ClipboardPanelLayout.defaultPanelHeight))
    assertEqual(defaultSections.cards.height >= ClipboardPanelLayout.cardHeight, true,
                "默认高度下卡片区能露出整卡 198pt")

    // MARK: 提示行列宽分配

    let footer = ClipboardPanelLayout.footerMetrics(width: 640, height: 400,
                                                    countWidth: 80, stackWidth: 60, permissionWidth: 90)
    assertEqual(footer.count.minX, ClipboardPanelLayout.paddingX, "计数贴左内边距")
    assertEqual(footer.stack.minX, footer.count.maxX + ClipboardPanelLayout.toolbarGap, "栈进度紧跟计数")
    assertEqual(footer.hint.minX, footer.stack.maxX + ClipboardPanelLayout.toolbarGap, "提示紧跟栈进度")
    assertEqual(footer.hint.maxX, footer.permission.minX - ClipboardPanelLayout.toolbarGap,
                "提示右边缘在权限入口左侧一个间距处")
    assertEqual(footer.permission.maxX, 640 - ClipboardPanelLayout.paddingX, "权限入口贴右内边距")
    assertEqual(footer.permission.minY, 400 - ClipboardPanelLayout.footerHeight
                + (ClipboardPanelLayout.footerHeight - ClipboardPanelLayout.footerTextHeight) / 2,
                "提示行文案在 24pt 行内垂直居中")
    assertEqual(footer.hint.width > 0, true, "常规宽度下提示有空间")

    // 最小面板宽（420）+ 权限入口带警示图标（120）时栈进度让位，计数与提示共享剩余空间
    let narrowFooter = ClipboardPanelLayout.footerMetrics(width: 420, height: 357,
                                                          countWidth: 160, stackWidth: 120,
                                                          permissionWidth: 120)
    assertEqual(narrowFooter.stack.width, 0, "窄面板 + 宽权限入口时栈进度让位")
    assertEqual(narrowFooter.count.width, 160, "计数不被压缩（上限 160）")
    assertEqual(narrowFooter.hint.minX, narrowFooter.count.maxX + ClipboardPanelLayout.toolbarGap,
                "让位后提示从计数右边缘起（不留空隙）")
    assertEqual(narrowFooter.hint.minX, narrowFooter.count.maxX + ClipboardPanelLayout.toolbarGap,
                "让位后提示从计数右边缘起")
    assertEqual(narrowFooter.hint.width > 0, true, "让位后提示仍有空间")

    // 计数与栈都隐藏时，提示直接从左边距起
    let emptyFooter = ClipboardPanelLayout.footerMetrics(width: 640, height: 400,
                                                         countWidth: 0, stackWidth: 0, permissionWidth: 90)
    assertEqual(emptyFooter.count.width, 0, "隐藏时计数宽 0")
    assertEqual(emptyFooter.hint.minX, ClipboardPanelLayout.paddingX, "都没有时提示贴左内边距")
    assertEqual(emptyFooter.permission.width, 90, "权限入口用实测宽")

    print("✅ Clipboard detail strip & panel sections works")
}
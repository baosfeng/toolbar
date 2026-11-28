import Foundation
import NetworkMonitorUI

// MARK: - 卡片几何与命中（自绘卡片的纯逻辑）

/// 自绘卡片的几何口径守卫：三段式卡片（卡头 / 卡身 / 卡脚）各区域的位置与命中结果
///
/// 背景：卡片从「8 个子视图」改成「一次 draw 画完」后，不再有子视图 frame 可依，
/// 星标 / 角标 / 卡头 / 卡身 / 卡脚的位置与「点哪算哪个区域」全部收敛到纯函数。
/// 本轮把版式改成对标 Paste 的三段式（卡头 26 / 卡身弹性 / 卡脚 34），
/// 这里钉住新的冻结值，并守住三条不变量：
/// 1. 三段纵向不重叠、不越界；
/// 2. 卡身高度足以容纳设计规定的正文行数；
/// 3. 命中区域按「星标 / 角标 → 卡头 → 卡脚 → 卡身」的优先级划分。
func runClipboardCardGeometryTests() {
    print("🧪 Testing clipboard card geometry & hit testing...")

    let bounds = CGRect(x: 0, y: 0, width: 176, height: 198)

    // 令牌
    assertEqual(ClipboardCardGeometry.headBandHeight, 26, "卡头带 26pt")
    assertEqual(ClipboardCardGeometry.bandPaddingX, 8, "卡头左右内边距 8")
    assertEqual(ClipboardCardGeometry.bandBodyGap, 6, "卡头与卡身留白 6")
    assertEqual(ClipboardCardGeometry.bandIconSize, 14, "卡头 App 图标 14")
    assertEqual(ClipboardCardGeometry.Metrics.standard.padding, 10, "左右与底部内边距 10")
    assertEqual(ClipboardCardGeometry.Metrics.standard.footerHeight, 34, "卡脚高 34")
    assertEqual(ClipboardCardGeometry.Metrics.standard.bodyGap, 6, "卡身与卡脚留白 6")
    assertEqual(ClipboardCardGeometry.Metrics.standard.starSize, 11, "收藏星 11")

    // 卡头带：贴顶、与卡同宽
    let band = ClipboardCardGeometry.headBandRect(in: bounds)
    assertEqual(band, CGRect(x: 0, y: 0, width: 176, height: 26), "卡头贴顶、与卡同宽")

    // 卡脚：贴底、与卡同宽
    let footer = ClipboardCardGeometry.footerRect(in: bounds)
    assertEqual(footer, CGRect(x: 0, y: 164, width: 176, height: 34), "卡脚贴底、与卡同宽")
    assertEqual(ClipboardCardGeometry.footerHairlineY(in: bounds), 164, "卡脚顶部发丝线在 164")

    // 卡身：卡头之下、卡脚之上，左右内缩 10
    let body = ClipboardCardGeometry.bodyRect(in: bounds)
    assertEqual(body, CGRect(x: 10, y: 32, width: 156, height: 126),
                "卡身 = (26 + 6) 到 (164 − 6)，左右内缩 10")
    assertEqual(ClipboardCardGeometry.thumbnailRect(in: bounds), body, "缩略图区 = 卡身")
    assertEqual(ClipboardCardGeometry.contentRect(in: bounds), body, "内容区 = 卡身")

    // 三段不重叠、不越界（设计不变量：改档位时最先坏的就是这条）
    assertEqual(band.maxY <= body.minY, true, "卡头与卡身不重叠")
    assertEqual(body.maxY <= footer.minY, true, "卡身与卡脚不重叠")
    assertEqual(footer.maxY <= bounds.maxY, true, "卡脚不越出卡片底边")
    assertEqual(body.height >= 120, true, "卡身至少容得下 5 行 24pt 行高的正文")

    // 卡脚两行
    let title = ClipboardCardGeometry.footerTitleRect(in: bounds)
    let source = ClipboardCardGeometry.footerSourceRect(in: bounds)
    assertEqual(title.minX, 10, "标题行左起点 = 内边距 10")
    assertEqual(title.maxX, 166, "标题行右边缘 = 卡宽 − 内边距")
    assertEqual(source.minY > title.minY, true, "来源行在标题行之下")
    assertEqual(source.maxY <= footer.maxY, true, "来源行不越出卡脚")

    // 收藏星：卡脚标题行最右，行内垂直居中
    let star = ClipboardCardGeometry.starRect(in: bounds)
    assertEqual(star.maxX, title.maxX, "星标贴标题行右边缘")
    assertEqual(star.midY >= title.minY && star.midY <= title.maxY, true, "星标落在标题行内")
    assertEqual(star.width, ClipboardCardGeometry.Metrics.standard.starSize, "星标边长取令牌")

    // 栈角标：贴卡身右上角
    let badge = ClipboardCardGeometry.badgeRect(in: bounds, badgeSize: CGSize(width: 30, height: 17))
    assertEqual(badge, CGRect(x: 136, y: 32, width: 30, height: 17), "角标贴卡身右上角")

    // ⌘N 文案只有 1…9
    assertEqual(ClipboardCardGeometry.shortcutText(number: 1), "⌘1", "1 → ⌘1")
    assertEqual(ClipboardCardGeometry.shortcutText(number: 9), "⌘9", "9 → ⌘9")
    assertEqual(ClipboardCardGeometry.shortcutText(number: 10), nil, "10 无 ⌘N 提示")
    assertEqual(ClipboardCardGeometry.shortcutText(number: nil), nil, "无序号不显示 ⌘N")
    assertEqual(ClipboardCardGeometry.shortcutText(number: 0), nil, "0 不是有效序号")

    // 命中区域：优先级 星标 / 角标 → 卡头 → 卡脚 → 卡身
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 88, y: 88), in: bounds, isImage: false),
                .body, "文本卡卡身 → body")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 88, y: 88), in: bounds, isImage: true),
                .thumbnail, "图片卡卡身 → thumbnail")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 88, y: 180), in: bounds, isImage: false),
                .meta, "卡脚 → meta")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: star.midX, y: star.midY), in: bounds,
                                            isImage: false),
                .star, "星标矩形内 → star")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 88, y: 12), in: bounds, isImage: false),
                .headBand, "卡头带 → headBand")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 140, y: 40), in: bounds,
                                            badgeSize: CGSize(width: 30, height: 17), isImage: false),
                .badge, "角标矩形内 → badge")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 500, y: 500), in: bounds, isImage: false),
                .body, "卡片外按 body 兜底（事件本就不会到这）")

    // 命中动作：星标单击是唯一例外（收藏切换），其余区域单击选中；双击与右键全区域一致
    let regions: [ClipboardCardHitRegion] = [.thumbnail, .star, .badge, .meta, .headBand, .body]
    for region in regions {
        let expectedClick: ClipboardCardHitAction = region == .star ? .togglePin : .select
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 1, isContextMenu: false),
                    expectedClick, "\(region) 单击 → \(expectedClick)")
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 2, isContextMenu: false),
                    .paste, "\(region) 双击 → 粘贴（星标上双击也是「就要这条」）")
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 1, isContextMenu: true),
                    .showMenu, "\(region) 右键 → 菜单")
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 2, isContextMenu: true),
                    .showMenu, "\(region) 右键优先于双击")
    }

    // 星标命中框：11pt 的星扩到 24pt 见方，且不越出卡脚（贴右边缘时向左收、不砍面积）
    let starHit = ClipboardCardGeometry.starHitRect(in: bounds)
    assertEqual(starHit.width, 24, "星标命中框 24pt 宽")
    assertEqual(starHit.height, 24, "星标命中框 24pt 高")
    assertEqual(starHit.midX, star.midX, "命中框与星标同心（未被卡脚边界挤压时）")
    assertEqual(starHit.midY, star.midY, "命中框与星标同心（纵向）")
    assertEqual(starHit.maxX <= bounds.maxX, true, "命中框不越出卡片右边缘")
    assertEqual(starHit.minY >= footer.minY, true, "命中框不越出卡脚上沿")

    // 卡片区留白：顶部 8 / 底部 24（底部那条带留给状态胶囊）
    assertEqual(ClipboardCardGeometry.cardInsetTop, 8, "卡片区顶部留白 8")
    assertEqual(ClipboardCardGeometry.cardInsetBottom, 24, "卡片区底部留白 24")
    assertEqual(ClipboardCardGeometry.cardSlack, 32, "上下留白合计 32")

    // 卡片尺寸：宽度由「卡高 × 比例」给出，1.15 的横卡比例必须在默认面板高度下真的生效
    let bigCard = ClipboardCardGeometry.cardSize(forCardAreaHeight: 332)
    assertEqual(bigCard.height, 300, "332pt 卡片区 − 32pt 留白 = 300pt 卡高")
    assertEqual(bigCard.width, 344, "300 × 1.146 取整 = 344pt 卡宽（不再被 260 截成竖卡）")
    assertEqual(bigCard.width > bigCard.height, true, "默认面板高度下是横卡，不是竖卡")
    let tinyCard = ClipboardCardGeometry.cardSize(forCardAreaHeight: 120)
    assertEqual(tinyCard.height, ClipboardCardGeometry.minCardHeight, "卡片区过矮时夹到卡高下限")
}

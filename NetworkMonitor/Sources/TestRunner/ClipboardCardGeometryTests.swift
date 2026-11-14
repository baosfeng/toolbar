import Foundation
import NetworkMonitorUI

// MARK: - 卡片几何与命中（自绘卡片的纯逻辑）

/// 自绘卡片的几何口径守卫：卡片内各区域的位置与命中结果
///
/// 背景：卡片从「8 个子视图」改成「一次 draw 画完」后，不再有子视图 frame 可依，
/// 星标 / 角标 / 缩略图 / meta 行的位置与「点哪算哪个区域」全部收敛到纯函数，
/// 这里把改造前视图树的实测口径逐项钉住（容器 176×198、内边距 10、meta 16、间距 6）。
func runClipboardCardGeometryTests() {
    print("🧪 Testing clipboard card geometry & hit testing...")

    let bounds = CGRect(x: 0, y: 0, width: 176, height: 198)

    // 令牌与改造前一致
    assertEqual(ClipboardCardGeometry.Metrics.standard.padding, 10, "内边距 10")
    assertEqual(ClipboardCardGeometry.Metrics.standard.metaHeight, 16, "meta 行高 16")
    assertEqual(ClipboardCardGeometry.Metrics.standard.bodyGap, 6, "正文与 meta 间距 6")
    assertEqual(ClipboardCardGeometry.Metrics.standard.typeIconSize, 14, "类型图标 14")
    assertEqual(ClipboardCardGeometry.Metrics.standard.metaGap, 6, "meta 内间距 6")
    assertEqual(ClipboardCardGeometry.Metrics.standard.starSize, 12, "收藏星 12")

    // 内容区 / 正文区 / meta 行
    let content = ClipboardCardGeometry.contentRect(in: bounds)
    assertEqual(content, CGRect(x: 10, y: 10, width: 156, height: 178), "内容区四边内缩 10")
    let body = ClipboardCardGeometry.bodyRect(in: bounds)
    assertEqual(body, CGRect(x: 10, y: 10, width: 156, height: 156), "正文区 = 内容区 − meta 16 − 间距 6")
    assertEqual(ClipboardCardGeometry.metaRowY(in: bounds), 172, "meta 行顶边 172")
    assertEqual(ClipboardCardGeometry.metaLeftX(in: bounds), 30, "meta 左起点 = 10 + 14 + 6")
    assertEqual(ClipboardCardGeometry.thumbnailRect(in: bounds), body, "缩略图区 = 正文区")

    // 收藏星：类型图标之后；有 ⌘N 时再让出（⌘N 宽 + 间距）
    let starWithoutShortcut = ClipboardCardGeometry.starRect(in: bounds, shortcutWidth: 0)
    assertEqual(starWithoutShortcut, CGRect(x: 30, y: 174, width: 12, height: 12),
                "无 ⌘N 时星标贴在类型图标后、meta 行内垂直居中")
    let starWithShortcut = ClipboardCardGeometry.starRect(in: bounds, shortcutWidth: 18.5)
    assertEqual(starWithShortcut.minX, 54.5, "有 ⌘N 时星标右移「⌘N 宽 + 间距」")
    assertEqual(starWithShortcut.minY, 174, "星标纵向位置不随 ⌘N 变化")

    // 栈角标：贴内容区右上角
    let badge = ClipboardCardGeometry.badgeRect(in: bounds, badgeSize: CGSize(width: 30, height: 17))
    assertEqual(badge, CGRect(x: 136, y: 10, width: 30, height: 17), "角标右上角对齐内容区")

    // ⌘N 文案只有 1…9
    assertEqual(ClipboardCardGeometry.shortcutText(number: 1), "⌘1", "1 → ⌘1")
    assertEqual(ClipboardCardGeometry.shortcutText(number: 9), "⌘9", "9 → ⌘9")
    assertEqual(ClipboardCardGeometry.shortcutText(number: 10), nil, "10 无 ⌘N 提示")
    assertEqual(ClipboardCardGeometry.shortcutText(number: nil), nil, "无序号不显示 ⌘N")
    assertEqual(ClipboardCardGeometry.shortcutText(number: 0), nil, "0 不是有效序号")

    // 命中区域
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 88, y: 88), in: bounds, isImage: false),
                .body, "文本卡正文区 → body")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 88, y: 88), in: bounds, isImage: true),
                .thumbnail, "图片卡正文区 → thumbnail")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 100, y: 180), in: bounds, isImage: false),
                .meta, "meta 行 → meta")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 36, y: 180), in: bounds, isImage: false),
                .star, "星标矩形内 → star")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 140, y: 15), in: bounds,
                                            badgeSize: CGSize(width: 30, height: 17), isImage: false),
                .badge, "角标矩形内 → badge")
    assertEqual(ClipboardCardHitTest.region(at: CGPoint(x: 500, y: 500), in: bounds, isImage: false),
                .body, "卡片外按 body 兜底（事件本就不会到这）")

    // 星标落在 meta 行纵向范围内（meta 行 172…188）
    assertEqual(starWithoutShortcut.minY >= 172 && starWithoutShortcut.maxY <= 188, true,
                "星标落在 meta 行纵向范围内")

    // 命中动作：所有区域口径一致 —— 单击选中 / 双击粘贴 / 右键菜单
    let regions: [ClipboardCardHitRegion] = [.thumbnail, .star, .badge, .meta, .body]
    for region in regions {
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 1, isContextMenu: false),
                    .select, "\(region) 单击 → 选中")
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 2, isContextMenu: false),
                    .paste, "\(region) 双击 → 粘贴")
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 1, isContextMenu: true),
                    .showMenu, "\(region) 右键 → 菜单")
        assertEqual(ClipboardCardHitTest.action(for: region, clickCount: 2, isContextMenu: true),
                    .showMenu, "\(region) 右键优先于双击")
    }
}

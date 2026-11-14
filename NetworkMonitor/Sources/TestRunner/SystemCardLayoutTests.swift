import Foundation
import NetworkMonitorUI

// MARK: - 系统页首屏五卡的排布口径

/// 断言「整卡自绘」的纯排布契约（视图只按这里算好的矩形画，卡内零视图）
///
/// 1. 卡头一行：标题贴左、附属件紧跟、说明右对齐且放不下时先让位、最右端块贴右；
/// 2. 卡高与内容区：内容高为 0 仍留卡头间距（磁盘卡只有卡头一行）；
/// 3. 读数条：组内 / 组间间距与宽度按展开顺序累加，行高取最高段；
/// 4. 堆叠条段宽：按 total 归一化，越界与非有限值一律夹到 0；
/// 5. 负载纵轴：下限核数 × 1.2、上限峰值 × 1.15、绝对值下限 1；
/// 6. 用户态 / 系统态：两段取整后必须凑得出总量。
///
/// 说明：DrawnReadoutRun 的横向排布全部委托 SystemCardLayout.readoutOffsets（可执行目标内，
/// TestRunner 无法 import），因此它的口径在这里被同一组断言覆盖。
func runSystemCardLayoutTests() {
    print("\n🧪 Testing SystemCardLayout...")

    // MARK: 卡头一行

    // 1. 只有标题：说明占满右边界，最右端块贴右
    let titleOnly = SystemCardLayout.head(width: 200,
                                          titleWidth: 60,
                                          accessoryWidth: 0,
                                          captionWidth: 0,
                                          trailingWidth: 0,
                                          gap: 8)
    assertEqual(titleOnly.titleX, 0, "标题贴左边界")
    assertEqual(titleOnly.accessoryX, 60, "无附属件时附属件起点紧接标题（不加间距）")
    assertEqual(titleOnly.trailingX, 200, "无最右端块时起点等于右边界")
    assertEqual(titleOnly.captionWidth, 0, "无说明时不占宽")

    // 2. 四件齐全：标题 → 附属件 → 说明右对齐 → 最右端块贴右
    let full = SystemCardLayout.head(width: 200,
                                     titleWidth: 60,
                                     accessoryWidth: 40,
                                     captionWidth: 30,
                                     trailingWidth: 16,
                                     gap: 8)
    assertEqual(full.accessoryX, 68, "附属件起点 = 标题宽 + 间距")
    assertEqual(full.trailingX, 184, "最右端块起点 = 右边界 − 其宽度")
    assertEqual(full.captionWidth, 30, "空间够时说明实得原宽")
    assertEqual(full.captionX, 184 - 8 - 30, "说明右对齐：右起点扣掉与最右端块的间距")

    // 3. 说明放不下：先让位（宁可省略号，也不压住标题与附属件）
    let squeezed = SystemCardLayout.head(width: 120,
                                         titleWidth: 60,
                                         accessoryWidth: 40,
                                         captionWidth: 60,
                                         trailingWidth: 16,
                                         gap: 8)
    // leftEdge = 68+40 = 108；rightEdge = 104-8 = 96 → 放不下
    assertEqual(squeezed.captionWidth, 0, "左侧已到右边界时说明实得 0 宽")
    assertEqual(squeezed.captionX, 96, "说明起点仍停在右侧让位后的位置")

    // 4. 非负保护：宽度小于最右端块时起点夹到 0
    let narrow = SystemCardLayout.head(width: 10,
                                       titleWidth: 60,
                                       accessoryWidth: 0,
                                       captionWidth: 0,
                                       trailingWidth: 16,
                                       gap: 8)
    assertEqual(narrow.trailingX, 0, "卡宽不足时最右端块起点夹到 0")

    // MARK: 卡高与内容区

    // 5. 内容高为 0 仍留卡头间距（磁盘卡：只有卡头一行）
    assertEqual(SystemCardLayout.cardHeight(contentHeight: 0,
                                            headHeight: 14,
                                            headSpacing: 4,
                                            paddingY: 4),
                4 + 14 + 4 + 0 + 4,
                "磁盘卡高度 = 上下内边距 + 卡头 + 卡头间距")

    // 6. 负内容高按 0 处理（不出现负高卡片）
    assertEqual(SystemCardLayout.cardHeight(contentHeight: -20,
                                            headHeight: 14,
                                            headSpacing: 4,
                                            paddingY: 4),
                26,
                "负内容高夹到 0")

    // 7. 内容区：flipped 坐标自上而下，宽度扣左右内边距
    let rect = SystemCardLayout.contentRect(width: 296,
                                            contentHeight: 100,
                                            headHeight: 14,
                                            headSpacing: 4,
                                            paddingX: 7,
                                            paddingY: 4)
    assertEqual(rect.origin.x, 7, "内容区左起点 = 左内边距")
    assertEqual(rect.origin.y, 4 + 14 + 4, "内容区顶起点 = 上内边距 + 卡头 + 卡头间距")
    assertEqual(rect.width, 296 - 14, "内容区宽 = 卡宽 − 左右内边距")
    assertEqual(rect.height, 100, "内容区高原样保留")

    // 8. 内容区非负：卡宽不足左右内边距时宽度夹到 0
    assertEqual(SystemCardLayout.contentRect(width: 4,
                                             contentHeight: 10,
                                             headHeight: 14,
                                             headSpacing: 4,
                                             paddingX: 7,
                                             paddingY: 4).width,
                0,
                "卡宽不足时内容区宽夹到 0")

    // MARK: 读数条

    let groups = [[SystemCardLayout.ReadoutPiece(width: 20, height: 10),
                   SystemCardLayout.ReadoutPiece(width: 30, height: 12)],
                  [SystemCardLayout.ReadoutPiece(width: 40, height: 8)]]
    // 组内 innerGap 2、组间 groupGap 8
    let offsets = SystemCardLayout.readoutOffsets(groups: groups, innerGap: 2, groupGap: 8)
    assertEqual(offsets, [0, 22, 60], "段起点 = 前序段宽 + 组内 / 组间间距")
    assertEqual(SystemCardLayout.readoutWidth(groups: groups, innerGap: 2, groupGap: 8),
                100,
                "总宽 = 各段宽 + 两个组内间距 + 一个组间间距（末段后不留间距）")
    assertEqual(SystemCardLayout.readoutHeight(groups: groups), 12, "行高取最高段")
    assertEqual(SystemCardLayout.readoutHeight(groups: []), 0, "空读数条行高 0")

    // 空组不产生额外间距（组间间距只在有内容的组之间）
    assertEqual(SystemCardLayout.readoutOffsets(groups: [[], [SystemCardLayout.ReadoutPiece(width: 5, height: 5)]],
                                               innerGap: 2,
                                               groupGap: 8),
                [8],
                "空组之后仍有组间间距，段起点 = 8")

    // MARK: 堆叠条段宽

    assertEqual(SystemCardLayout.segmentWidths(values: [1, 1, 2], total: 4, width: 100),
                [25, 25, 50],
                "段宽 = 整条宽 × 占比")
    assertEqual(SystemCardLayout.segmentWidths(values: [5, 0, -1], total: 4, width: 100),
                [100, 0, 0],
                "超界段夹到满宽、0 与负数段为 0")
    assertEqual(SystemCardLayout.segmentWidths(values: [1, 2], total: 0, width: 100),
                [0, 0],
                "总量为 0 时各段宽 0（不出现除零）")
    assertEqual(SystemCardLayout.segmentWidths(values: [Double.nan, 1], total: 2, width: 100),
                [0, 50],
                "非有限值段宽 0，其余段照常分配")

    // MARK: 负载纵轴

    assertEqual(SystemCardLayout.loadAxisMaximum(coreCount: 8, peak: 1), 9.6, "低负载时下限由核数决定（8 × 1.2）")
    assertEqual(SystemCardLayout.loadAxisMaximum(coreCount: 8, peak: 20), 23, "峰值更高时用峰值 × 1.15 用满高度")
    assertEqual(SystemCardLayout.loadAxisMaximum(coreCount: 0, peak: 0), 1, "两者都为 0 时下限为 1")
    assertEqual(SystemCardLayout.loadAxisMaximum(coreCount: 0, peak: Double.nan), 1, "非有限峰值按 0 处理")
    assertEqual(SystemCardLayout.loadAxisMaximum(coreCount: -4, peak: -3), 1, "负核数与负峰值不产生负量程")

    // MARK: 用户态 / 系统态取整

    let split = SystemCardLayout.usageSplitPercents(total: 0.29, system: 0.13)
    assertEqual(split.user + split.system, 29, "用户态 + 系统态 = 总量取整（29%）")
    assertEqual(split.system, 13, "系统态按四舍五入取整")
    assertEqual(split.user, 16, "用户态由总量反算得出，两段合计自洽")

    // 各段独立取整会凑不出总量的那一例：总量 29%、系统 14.5% → 系统 14% 时用户仍是 15%（合计 29%）
    let rounding = SystemCardLayout.usageSplitPercents(total: 0.29, system: 0.145)
    assertEqual(rounding.user + rounding.system, 29, "14.5% 的系统态也不破坏合计（29%）")

    let clampedSplit = SystemCardLayout.usageSplitPercents(total: 1.5, system: 2.0)
    assertEqual(clampedSplit.system, 100, "超出 1 的入参夹到 100%")
    assertEqual(clampedSplit.user, 0, "系统态吃满总量时用户态为 0（不出现负数）")

    let nanSplit = SystemCardLayout.usageSplitPercents(total: Double.nan, system: Double.nan)
    assertEqual(nanSplit.user + nanSplit.system, 0, "非有限入参一律按 0")
}

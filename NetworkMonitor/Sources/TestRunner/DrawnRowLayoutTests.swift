import Foundation
import NetworkMonitorUI

// MARK: - 自绘行规格与宽度分配

/// 断言自绘行列表的两条纯逻辑契约：宽度分配与内容总高
///
/// 1. 数值优先不被截断；
/// 2. 进度条不足 `minBarWidth` 时整条不画，宽度还给行名；
/// 3. 无进度条时行名吃掉全部剩余宽度；
/// 4. 内容总高 = N×行高 + (N-1)×行间空隙。
func runDrawnRowLayoutTests() {
    print("\n🧪 Testing DrawnRowLayout...")
    // 1. 无进度条：行名吃满剩余
    let noBar = DrawnRowLayout.metrics(rowWidth: 300,
                                      leadingInset: 8,
                                      trailingInset: 8,
                                      titleWidth: 120,
                                      valueWidth: 60,
                                      gap: 6,
                                      hasProgress: false,
                                      minBarWidth: 24)
    assertEqual(noBar.valueWidth, 60, "数值实测宽度原样保留")
    assertEqual(noBar.titleWidth, 120, "行名不会被无故压缩")
    assertEqual(noBar.showsBar, false, "无进度条时不画")

    // 2. 有进度条：名称 + 进度 + 数值三者在内容宽内排开（300-8-8 = 284）
    let withBar = DrawnRowLayout.metrics(rowWidth: 300,
                                         leadingInset: 8,
                                         trailingInset: 8,
                                         titleWidth: 80,
                                         valueWidth: 60,
                                         gap: 6,
                                         hasProgress: true,
                                         minBarWidth: 24)
    assertEqual(withBar.valueWidth, 60, "有进度条时数值仍不被截断")
    assertEqual(withBar.titleWidth, 80, "行名按实测宽度占位")
    assertEqual(withBar.showsBar, true, "剩余空间够时画进度条")
    assertEqual(withBar.barWidth, 284 - 80 - 6 - 60 - 6, "进度条宽度 = 内容宽 - 名称 - 两个间距 - 数值")

    // 3. 长标题把进度条挤到不足最小宽度：整条不画，标题占满剩余（行名优先）
    let squeezed = DrawnRowLayout.metrics(rowWidth: 120,
                                          leadingInset: 8,
                                          trailingInset: 8,
                                          titleWidth: 90,
                                          valueWidth: 40,
                                          gap: 6,
                                          hasProgress: true,
                                          minBarWidth: 24)
    assertEqual(squeezed.showsBar, false, "进度条不足最小宽度时整条不画")
    assertEqual(squeezed.titleWidth, 58, "标题占满剩余（104-40-6）")

    // 3b. 空间更紧：标题截断到剩余宽度，依旧不出现负值
    let noRoom = DrawnRowLayout.metrics(rowWidth: 120,
                                        leadingInset: 8,
                                        trailingInset: 8,
                                        titleWidth: 200,
                                        valueWidth: 70,
                                        gap: 6,
                                        hasProgress: true,
                                        minBarWidth: 24)
    assertEqual(noRoom.showsBar, false, "空间不足时不画进度条")
    assertEqual(noRoom.valueWidth, 70, "数值优先，不被进度条挤掉")
    assertEqual(noRoom.titleWidth, 28, "标题截断到剩余宽度（104-70-6）")

    // 3c. 标题短：剩余足够，进度条照常出现
    let roomy = DrawnRowLayout.metrics(rowWidth: 300,
                                       leadingInset: 8,
                                       trailingInset: 8,
                                       titleWidth: 60,
                                       valueWidth: 60,
                                       gap: 6,
                                       hasProgress: true,
                                       minBarWidth: 24)
    assertEqual(roomy.showsBar, true, "标题短时进度条正常出现")
    assertEqual(roomy.barWidth, 284 - 60 - 6 - 60 - 6, "进度条吃掉标题与数值之间的全部剩余")

    // 4. 极端窄：内容宽为负时全部归零，不产生负宽度
    let degenerate = DrawnRowLayout.metrics(rowWidth: 10,
                                           leadingInset: 8,
                                           trailingInset: 8,
                                           titleWidth: 100,
                                           valueWidth: 50,
                                           gap: 6,
                                           hasProgress: true,
                                           minBarWidth: 24)
    assertEqual(degenerate.titleWidth >= 0 && degenerate.valueWidth >= 0 && degenerate.barWidth >= 0,
                true, "任何情况下不出现负宽度")

    // 5. 内容总高
    assertEqual(DrawnRowLayout.contentHeight(rowCount: 0, rowHeight: 28, rowSpacing: 2), 0, "0 行高为 0")
    assertEqual(DrawnRowLayout.contentHeight(rowCount: 1, rowHeight: 28, rowSpacing: 2), 28, "1 行不含尾部空隙")
    assertEqual(DrawnRowLayout.contentHeight(rowCount: 3, rowHeight: 28, rowSpacing: 2), 88, "3 行 = 3×28 + 2×2")

    // 6. 行规格是值类型：可比较、默认值明确
    let a = DrawnRowSpec(title: "网络", value: "1.2 MB/s")
    let b = DrawnRowSpec(title: "网络", value: "1.2 MB/s")
    assertEqual(a, b, "同内容的两行相等")
    assertEqual(a.progress == nil, true, "默认不画进度条")
    assertEqual(a.isActionable, false, "默认不可点击")
    assertEqual(a.tone, DrawnRowSpec.Tone.normal, "默认常规语气")
    print("✅ DrawnRowLayout works")
}

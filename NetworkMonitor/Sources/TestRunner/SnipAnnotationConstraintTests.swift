import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - Shift 标注约束 / 样式解析 / 删除与选中（回归断言）

func runSnipAnnotationConstraintTests() {
    print("\n🧪 Testing Snip annotation constraint (Shift)...")

    // 矩形 → 正方形：取较长边，方向跟随终点（四个象限都要成立）
    let start = CGPoint(x: 100, y: 100)
    let square1 = SnipAnnotationConstraint.constrained(kind: .rectangle, start: start,
                                                      end: CGPoint(x: 180, y: 140), lockingShift: true)
    assertEqual(square1, CGPoint(x: 180, y: 180), "右下象限取较大边成正方形")
    let square2 = SnipAnnotationConstraint.constrained(kind: .rectangle, start: start,
                                                      end: CGPoint(x: 60, y: 80), lockingShift: true)
    assertEqual(square2, CGPoint(x: 60, y: 60), "左上象限同样成正方形")
    // 不按 Shift 时原样返回（约束只在按住时生效）
    assertEqual(SnipAnnotationConstraint.constrained(kind: .rectangle, start: start,
                                                     end: CGPoint(x: 180, y: 140), lockingShift: false),
                CGPoint(x: 180, y: 140), "未按 Shift 不约束")

    // 椭圆 → 圆：与矩形同一口径（包围盒正方）
    assertEqual(SnipAnnotationConstraint.constrained(kind: .ellipse, start: start,
                                                     end: CGPoint(x: 160, y: 120), lockingShift: true),
                CGPoint(x: 160, y: 160), "椭圆按 Shift 后包围盒变正方形")

    // 直线 / 箭头 → 水平·垂直·45°：接近整角时吸附，长度不变
    let horizontal = SnipAnnotationConstraint.constrained(kind: .line, start: start,
                                                          end: CGPoint(x: 200, y: 106), lockingShift: true)
    assertEqual(Int(horizontal.y.rounded()), 100, "接近水平的线吸附到 0°")
    assertEqual(Int((horizontal.x - start.x).rounded()), 100, "吸附后长度保持")
    let vertical = SnipAnnotationConstraint.constrained(kind: .arrow, start: start,
                                                        end: CGPoint(x: 104, y: 200), lockingShift: true)
    assertEqual(Int(vertical.x.rounded()), 100, "接近垂直的箭头吸附到 90°")
    // 45° 吸附：按对角方向拖时 x/y 位移相等
    let diagonal = SnipAnnotationConstraint.constrained(kind: .line, start: start,
                                                        end: CGPoint(x: 200, y: 194), lockingShift: true)
    assertEqual(abs((diagonal.x - start.x) - (diagonal.y - start.y)) < 0.5, true, "45° 吸附后 x/y 位移相等")
    // 远离整角时保持自由角度（不要什么角度都吸）
    let free = CGPoint(x: 180, y: 130)
    assertEqual(SnipAnnotationConstraint.constrained(kind: .line, start: start, end: free, lockingShift: true),
                free, "夹角不是整角时保持自由方向")

    // 折线与文字不受约束
    assertEqual(SnipAnnotationConstraint.constrained(kind: .polyline, start: start,
                                                     end: CGPoint(x: 180, y: 140), lockingShift: true),
                CGPoint(x: 180, y: 140), "折线不约束")
    assertEqual(SnipAnnotationConstraint.constrained(kind: .text, start: start,
                                                     end: CGPoint(x: 180, y: 140), lockingShift: true),
                CGPoint(x: 180, y: 140), "文字不约束")

    print("✅ Shift 标注约束测试通过")
}

func runSnipAnnotationStyleResolverTests() {
    print("\n🧪 Testing Snip annotation style resolver (偏好 → 初始样式)...")

    // 偏好齐全：按用户设置还原
    let style = SnipAnnotationStyleResolver.style(colorHex: "#2980F2", lineWidth: 8, dashed: true)
    assertEqual(style.lineWidth, 8, "线宽取偏好值")
    assertEqual(style.dashed, true, "线型取偏好值")
    assertEqual(SnipAnnotationColorHex.hex(style.color), "#2980F2", "颜色取偏好 hex")

    // 偏好缺失：回落默认红 + 默认线宽 + 实线
    let fallback = SnipAnnotationStyleResolver.style(colorHex: nil, lineWidth: nil, dashed: false)
    assertEqual(SnipAnnotationColorHex.hex(fallback.color), SnipAnnotationStyleResolver.defaultColorHex,
                "未设置颜色时回落默认红")
    assertEqual(fallback.lineWidth, SnipAnnotationStyleResolver.defaultLineWidth, "未设置线宽时回落默认值")

    // 非法值：夹取 / 回落，不崩
    assertEqual(SnipAnnotationStyleResolver.style(colorHex: "#XYZ", lineWidth: nil, dashed: false).color,
                SnipAnnotationColor.red, "非法 hex 回落默认红")
    assertEqual(SnipAnnotationStyleResolver.style(colorHex: nil, lineWidth: 200, dashed: false).lineWidth, 40,
                "过大线宽夹到 40")
    assertEqual(SnipAnnotationStyleResolver.style(colorHex: nil, lineWidth: 0, dashed: false).lineWidth, 1,
                "0 线宽夹到 1")

    // hex 往返：默认红原样回来（设置页与覆盖层格式一致，否则调色板高亮会落空）
    assertEqual(SnipAnnotationColorHex.hex(.red), SnipAnnotationStyleResolver.defaultColorHex,
                "默认红的 hex 与设置页同一取值")

    // 透明度派生：只改 alpha，不动 RGB
    let translucent = SnipAnnotationColor.blue.withAlpha(0.3)
    assertEqual(translucent.alpha, 0.3, "透明度按参数生效")
    assertEqual(SnipAnnotationColorHex.hex(translucent), SnipAnnotationColorHex.hex(.blue),
                "改透明度不影响 RGB")
    assertEqual(SnipAnnotationColor.blue.withAlpha(2).alpha, 1, "透明度上界夹到 1")
    assertEqual(SnipAnnotationColor.blue.withAlpha(-1).alpha, 0, "透明度下界夹到 0")

    print("✅ 标注默认样式解析测试通过")
}

func runSnipAnnotationSelectionTests() {
    print("\n🧪 Testing Snip annotation stack delete (Del 二次编辑)...")

    var stack = SnipAnnotationStack()
    let a = SnipAnnotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40))
    let b = SnipAnnotation(kind: .arrow, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 90, y: 70))
    stack.add(a)
    stack.add(b)
    assertEqual(stack.annotations.count, 2, "两条标注入栈")

    // Del 删除选中项（官方二次编辑最小集）：删完剩一条，且重做栈被清掉
    stack.remove(at: 1)
    assertEqual(stack.annotations.count, 1, "删除选中后剩一条")
    assertEqual(stack.annotations.first, a, "删的是选中的那条")
    assertEqual(stack.canRedo, false, "删除后重做栈清空")

    // 越界下标不崩（选中态可能失效）
    stack.remove(at: 5)
    assertEqual(stack.annotations.count, 1, "越界删除无副作用")

    // 轨迹类判据：画笔 / 折线不参与「点击选中」
    assertEqual(SnipAnnotationKind.freehand.isStroke, true, "画笔属于轨迹类")
    assertEqual(SnipAnnotationKind.polyline.isStroke, true, "折线属于轨迹类")
    assertEqual(SnipAnnotationKind.rectangle.isStroke, false, "矩形不是轨迹类")

    print("✅ 标注删除测试通过")
}

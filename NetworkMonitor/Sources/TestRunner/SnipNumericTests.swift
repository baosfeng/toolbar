import CoreGraphics
import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 数值任意可调（参数表 / 步进 / 意图 / 滚轮归一 / 读数 / 输入解析 / 图形缩放）

/// 覆盖「只能调固定档位」这件事的根因修复：
/// 1. 线宽过去吸附 [2,4,8]、字号 6 档、透明度 3 档 → 现在都是连续值，档位只是快捷项
/// 2. 调完不落盘 / 不改选中图形 → 现在只有一条写入路径
/// 3. 调完没反馈 → 读数气泡（文案与几何在此断言）
func runSnipNumericTests() {
    print("🧪 Testing snip numeric params...")

    // MARK: 参数表：范围 / 单位 / 默认值
    assertEqual(SnipNumericParam.lineWidth.range, 1...40, "线宽范围 1–40")
    assertEqual(SnipNumericParam.fontSize.range, 9...160, "字号范围 9–160")
    assertEqual(SnipNumericParam.opacity.range, 0...1, "透明度是 0…1 的规范化值")
    assertEqual(SnipNumericParam.lineWidth.defaultValue, 4, "线宽缺省 4")
    assertEqual(SnipNumericParam.opacity.defaultValue, 1, "透明度缺省不透明")
    assertEqual(SnipNumericParam.mosaicBlock.defaultValue, 14, "马赛克缺省与既有常量一致")
    assertEqual(SnipNumericParam.blurRadius.defaultValue, 14, "模糊缺省与既有常量一致")
    assertEqual(SnipNumericParam.magnifierZoom.defaultValue, 8, "放大镜缺省 8×（= 120 ÷ 15）")

    // MARK: 格式化：整数不带小数、透明度写百分比
    assertEqual(SnipNumericParam.lineWidth.format(12), "12 pt", "线宽整数格式")
    assertEqual(SnipNumericParam.lineWidth.format(12.5), "12.5 pt", "线宽半档格式")
    assertEqual(SnipNumericParam.opacity.format(0.6), "60%", "透明度按百分比显示")
    assertEqual(SnipNumericParam.mosaicBlock.format(14), "14 px", "马赛克单位 px")
    assertEqual(SnipNumericParam.magnifierZoom.format(8), "8 ×", "放大镜单位 ×")

    // MARK: 夹取与量化
    assertEqual(SnipNumericParam.lineWidth.clampValue(0), 1, "低于下限夹到 1")
    assertEqual(SnipNumericParam.lineWidth.clampValue(999), 40, "高于上限夹到 40")
    assertEqual(SnipNumericParam.lineWidth.clampValue(.nan), 4, "NaN 回落缺省值")
    assertEqual(SnipNumericParam.lineWidth.quantized(12.34), 12.5, "量化到半档")
    // 量化粒度是「最小单位的一半」：透明度最小单位 5% → 2.5%，故 0.63 落在 0.625
    assertEqual(SnipNumericParam.opacity.quantized(0.63), 0.625, "透明度量化到 2.5%")

    // MARK: 步进：三档意图 × 连续值
    assertEqual(SnipNumericStepper.step(4, param: .lineWidth, steps: 1), 5, "粗调一步 +1pt")
    assertEqual(SnipNumericStepper.step(4, param: .lineWidth, steps: -1), 3, "粗调一步 -1pt")
    assertEqual(SnipNumericStepper.step(4, param: .lineWidth, steps: 1, intent: .fast), 12,
                "快调一步 +8pt（2→40 不必滚 38 次）")
    assertEqual(SnipNumericStepper.step(4, param: .lineWidth, steps: 1, intent: .fine), 4.5,
                "精调一步 +0.5pt")
    assertEqual(SnipNumericStepper.step(40, param: .lineWidth, steps: 1), 40, "上界不再增长")
    assertEqual(SnipNumericStepper.step(1, param: .lineWidth, steps: -1), 1, "下界不再变小")
    // 关键回归：连续值不再吸附到 [2,4,8]
    assertEqual(SnipNumericStepper.step(3, param: .lineWidth, steps: 1), 4, "3pt 加一是 4pt（不是跳到 8）")
    assertEqual(SnipNumericStepper.step(5, param: .lineWidth, steps: 1), 6, "5pt 加一是 6pt（档位之外也能停）")
    assertEqual(SnipNumericStepper.step(13, param: .lineWidth, steps: -1), 12, "13pt 减一是 12pt")
    assertEqual(SnipNumericStepper.isAtLimit(40, param: .lineWidth), true, "40pt 已到上限")
    assertEqual(SnipNumericStepper.isAtLimit(39, param: .lineWidth), false, "39pt 未到上限")

    // MARK: 意图：全覆盖层唯一映射（⌘ 快 / ⌥ 精 / 其余粗）
    assertEqual(SnipNumericIntent.resolve(command: false, option: false), .coarse, "无修饰键 = 粗调")
    assertEqual(SnipNumericIntent.resolve(command: true, option: false), .fast, "⌘ = 快调")
    assertEqual(SnipNumericIntent.resolve(command: false, option: true), .fine, "⌥ = 精调")
    assertEqual(SnipNumericIntent.resolve(command: true, option: true), .fast,
                "⌘⌥ 同按时优先快调（用户意图是走完）")
    assertEqual(SnipNumericIntent.coarse.badge, nil, "粗调无角标")
    assertEqual(SnipNumericIntent.fine.badge, "精调", "精调有角标")
    assertEqual(SnipNumericIntent.fast.badge, "快调", "快调有角标")

    // MARK: 滚轮归一化：鼠标一格 = 1 步；触控板累加；惯性尾不消费
    var mouse = SnipScrollStepper()
    assertEqual(mouse.feed(delta: 1, hasPreciseDeltas: false, isMomentum: false), 1, "鼠标一格 = 1 步")
    assertEqual(mouse.feed(delta: -1, hasPreciseDeltas: false, isMomentum: false), -1, "反向一格 = -1 步")
    var trackpad = SnipScrollStepper()
    assertEqual(trackpad.feed(delta: 3, hasPreciseDeltas: true, isMomentum: false), 0,
                "触控板小幅不足阈值不消费（否则一碰就飞）")
    assertEqual(trackpad.feed(delta: 5, hasPreciseDeltas: true, isMomentum: false), 1,
                "累计 8px 走 1 步")
    assertEqual(trackpad.feed(delta: 40, hasPreciseDeltas: true, isMomentum: false), 5,
                "一次滑 40px = 5 步")
    assertEqual(trackpad.feed(delta: 3, hasPreciseDeltas: true, isMomentum: true), 0,
                "惯性尾不消费")
    var big = SnipScrollStepper()
    assertEqual(big.feed(delta: 500, hasPreciseDeltas: false, isMomentum: false), 8,
                "单次事件最多 8 步（不会一滚到顶）")

    // MARK: 读数气泡：文案与避让
    let hudLine = SnipNumericHUD.Entry(param: .lineWidth, value: 12, intent: .coarse)
    assertEqual(SnipNumericHUD.text(for: hudLine), "线宽 12 pt", "读数文案")
    let hudFine = SnipNumericHUD.Entry(param: .opacity, value: 0.6, intent: .fine)
    assertEqual(SnipNumericHUD.text(for: hudFine), "透明度 60% · 精调", "透明度读数带角标")
    let normalOrigin = SnipNumericHUD.origin(size: CGSize(width: 80, height: 24),
                                            cursor: CGPoint(x: 100, y: 100),
                                            bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
    assertEqual(normalOrigin.x > 100, true, "气泡默认在光标右侧")
    let edgeOrigin = SnipNumericHUD.origin(size: CGSize(width: 80, height: 24),
                                           cursor: CGPoint(x: 790, y: 590),
                                           bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
    assertEqual(edgeOrigin.x + 80 <= 800, true, "右侧放不下时翻到左侧")
    assertEqual(edgeOrigin.y + 24 <= 600, true, "下方放不下时翻到上方")

    // MARK: 精确输入：带单位 / 百分比 / 非法输入
    assertEqual(SnipNumericInput.parse("12pt", param: .lineWidth), 12, "带单位也能解析")
    assertEqual(SnipNumericInput.parse("12 px", param: .lineWidth), 12, "带空格单位")
    assertEqual(SnipNumericInput.parse("12.5", param: .lineWidth), 12.5, "小数")
    assertEqual(SnipNumericInput.parse("60%", param: .opacity), 0.6, "透明度写 60% → 0.6")
    assertEqual(SnipNumericInput.parse("60", param: .opacity), 0.6, "透明度写 60 也按百分比理解")
    assertEqual(SnipNumericInput.parse("0.6", param: .opacity), 0.6, "0…1 的直接写法")
    assertEqual(SnipNumericInput.parse("abc", param: .lineWidth), nil, "非数字返回 nil（保持原值）")
    assertEqual(SnipNumericInput.parse("", param: .lineWidth), nil, "空串返回 nil")
    assertEqual(SnipNumericInput.parse("999", param: .lineWidth), 40, "超上限夹到 40")

    // MARK: 图形整体缩放（⇧ + 滚轮）
    let rect = SnipAnnotation(kind: .rectangle,
                              start: CGPoint(x: 100, y: 100),
                              end: CGPoint(x: 200, y: 200))
    let (bigger, changed) = SnipAnnotationScaler.scaled(rect, steps: 1)
    assertEqual(changed, true, "放大生效")
    assertEqual(bigger.boundingRect.width > 100, true, "包围盒确实变大")
    assertEqual(bigger.boundingRect.midX, rect.boundingRect.midX, "以中心为锚，位置不跑")
    assertEqual(bigger.boundingRect.midY, rect.boundingRect.midY, "纵向同样以中心为锚")
    let (smaller, _) = SnipAnnotationScaler.scaled(rect, steps: -1)
    assertEqual(smaller.boundingRect.width < 100, true, "缩小生效")
    // 轨迹类不参与整体缩放（画笔整体缩放会让每一笔间距一起变）
    let stroke = SnipAnnotation(kind: .freehand,
                                start: CGPoint(x: 0, y: 0),
                                end: CGPoint(x: 10, y: 10),
                                points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
    assertEqual(SnipAnnotationScaler.scaled(stroke, steps: 1).changed, false, "轨迹类不整体缩放")
    assertEqual(SnipAnnotationScaler.scaled(rect, steps: 0).changed, false, "0 步不变")

    // MARK: 效果强度：马赛克与模糊各自独立且带在标注上
    var effectStyle = SnipAnnotationStyle()
    effectStyle.effect.mosaicBlock = 24
    assertEqual(effectStyle.effect.mosaicBlock, 24, "马赛克粒度可改")
    let mosaicAnnotation = SnipAnnotation(kind: .mosaic, start: .zero, end: CGPoint(x: 10, y: 10),
                                          style: effectStyle)
    assertEqual(mosaicAnnotation.style.effect.mosaicBlock, 24, "强度跟着标注走（画好的不会随后续调整变样）")
    assertEqual(effectStyle.effect.blurRadius, 14, "模糊仍是自己的默认值，两者互不影响")
    assertEqual(SnipEffectStyle.clampMosaic(1), 2, "马赛克下限 2")
    assertEqual(SnipEffectStyle.clampMosaic(999), 32, "马赛克上限 32")
    assertEqual(SnipEffectStyle.clampBlur(0), 1, "模糊下限 1")
    assertEqual(SnipEffectStyle.clampBlur(999), 40, "模糊上限 40")

    print("✅ 数值任意可调测试通过")
}

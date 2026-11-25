import CoreGraphics
import CoreText
import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 标注自定义（文字字号 / 字重 / 线宽连续值 / 取色器口径）

/// 覆盖「用户报的四类不支持」：
/// 1. 文字颜色与字号不能自定义 → SnipTextStyle 独立字号 + 渲染按族/字重取字
/// 2. 线框大小不能定义 → 线宽连续值 + 上限夹取
/// 3. 颜色只能从 7 档里挑 → HSV 取色器换算
/// 4. 颜色透明度不持久 → hex 带 alpha 编解码
func runSnipAnnotationCustomizationTests() {
    print("🧪 Testing snip annotation customization...")

    // MARK: 文字样式：字号与线宽解耦
    var style = SnipAnnotationStyle(lineWidth: 20)
    assertEqual(style.text.fontSize, nil, "缺省没有独立字号（老口径回落）")
    let fallback = SnipAnnotation(kind: .text, start: .zero, end: .zero, text: "A", style: style)
    assertEqual(fallback.fontSize, 100, "回落口径 = 线宽 × 5")

    style.text.fontSize = 16
    let small = SnipAnnotation(kind: .text, start: .zero, end: .zero, text: "A", style: style)
    assertEqual(small.fontSize, 16, "有独立字号时按字号走，不再受线宽影响")
    assertEqual(style.lineWidth, 20, "线宽本身不被字号改动")

    // fontScale 仍是临时缩放（选中后滚轮），与基准字号是两层
    var scaled = small
    scaled.fontScale = 2
    assertEqual(scaled.fontSize, 32, "临时缩放叠在基准字号上")

    // 夹取与步进
    assertEqual(SnipTextStyle.clampFontSize(3), 9, "下限夹到 9")
    assertEqual(SnipTextStyle.clampFontSize(999), 160, "上限夹到 160")
    assertEqual(SnipTextStyle.clampFontSize(.nan), 20, "NaN 回落默认值")
    let stepped = SnipTextStyle.steppedFontSize(from: 20, by: 1)
    assertEqual(stepped, 22, "20pt 放大一档 = +2（10% 步长）")
    assertEqual(SnipTextStyle.steppedFontSize(from: 20, by: -1), 18, "缩小一档 = -2")
    assertEqual(SnipTextStyle.steppedFontSize(from: 12, by: 1), 13, "小字最小步长 1pt")
    assertEqual(SnipTextStyle.steppedFontSize(from: 20, by: 0), 20, "delta 0 不变")

    // 字体族：都有中文名，且族名解析要么给族要么给 nil（系统默认）
    for family in SnipTextFamily.allCases {
        assertEqual(!family.displayName.isEmpty, true, "字体族有中文名：\(family.rawValue)")
    }
    assertEqual(SnipAnnotationRenderer.familyName(for: .system), nil, "默认族不指定族名")
    assertEqual(SnipAnnotationRenderer.familyName(for: .monospaced), "Menlo", "等宽族用 Menlo")

    // 字体本身：加粗与族不同都要能生成（CTFont 不会失败），且字号确实被应用
    let plain = SnipAnnotationRenderer.textFont(size: 20, style: SnipTextStyle())
    assertEqual(CTFontGetSize(plain), 20, "默认字体按请求字号创建")
    let bold = SnipAnnotationRenderer.textFont(size: 20, style: SnipTextStyle(bold: true))
    assertEqual(CTFontGetSize(bold), 20, "加粗字体同样按请求字号")
    // 加粗态与常规态必须不是同一个字形（否则「加粗」是空操作）
    let plainName = CTFontCopyPostScriptName(plain) as String
    let boldName = CTFontCopyPostScriptName(bold) as String
    assertEqual(plainName != boldName, true, "加粗切换真的换了字形")

    // MARK: 线宽连续值
    assertEqual(SnipLineWidthStepper.continuousStep(from: 3, by: 1), 4, "3 → 4（不吸附档位）")
    assertEqual(SnipLineWidthStepper.continuousStep(from: 5, by: -1), 4, "5 → 4")
    assertEqual(SnipLineWidthStepper.continuousStep(from: 13, by: 1), 14, "档位之外的 13 也能继续加")
    assertEqual(SnipLineWidthStepper.continuousStep(from: 40, by: 1), 40, "上限封顶")
    assertEqual(SnipLineWidthStepper.continuousStep(from: 1, by: -1), 1, "下限封底")
    assertEqual(SnipLineWidthStepper.step(from: 2, by: 1), 4, "档位步进（[ ] / 1 2）仍吸附")
    assertEqual(SnipLineWidthStepper.range.lowerBound, 1, "范围下界 1")
    assertEqual(SnipLineWidthStepper.range.upperBound, 40, "范围上界 40")

    // 解析器与 UI 共用同一份范围
    let clamped = SnipAnnotationStyleResolver.style(colorHex: "#FFFFFF", lineWidth: 999, dashed: false)
    assertEqual(clamped.lineWidth, 40, "解析器把超范围线宽夹到 40")

    // MARK: 颜色 hex 带 alpha
    let half = SnipAnnotationColor(red: 1, green: 0, blue: 0, alpha: 0.5)
    assertEqual(SnipAnnotationColorHex.hex(half), "#FF000080", "半透明编成 8 位")
    let opaque = SnipAnnotationColor(red: 1, green: 0, blue: 0, alpha: 1)
    assertEqual(SnipAnnotationColorHex.hex(opaque), "#FF0000", "不透明仍是 6 位（老偏好格式不变）")
    let roundTrip = SnipAnnotationStyleResolver.color(fromHex: SnipAnnotationColorHex.hex(half))
    assertEqual(roundTrip != nil, true, "8 位 hex 可解析回来")
    assertEqual(Int(((roundTrip?.alpha ?? 0) * 255).rounded()), 128, "alpha 往返误差在 1/255 内")
    assertEqual(SnipAnnotationStyleResolver.color(fromHex: "#12345"), nil, "非法长度返回 nil")
    assertEqual(SnipAnnotationStyleResolver.color(fromHex: "ZZZZZZ"), nil, "非法字符返回 nil")

    // MARK: 取色器 HSV 换算
    let red = SnipHSVColor(hue: 0, saturation: 1, brightness: 1)
    assertEqual(Int((red.rgb.red * 255).rounded()), 255, "H0 S1 V1 = 纯红")
    assertEqual(Int((red.rgb.green * 255).rounded()), 0, "纯红无绿分量")

    let green = SnipHSVColor(hue: 1.0 / 3, saturation: 1, brightness: 1).rgb
    assertEqual(Int((green.green * 255).rounded()), 255, "H1/3 = 纯绿")

    let back = SnipHSVColor(SnipAnnotationColor(red: 0.5, green: 0.25, blue: 0.125))
    let backRgb = back.rgb
    assertEqual(abs(backRgb.red - 0.5) < 0.01, true, "RGB → HSV → RGB 红分量往返")
    assertEqual(abs(backRgb.green - 0.25) < 0.02, true, "RGB → HSV → RGB 绿分量往返")
    assertEqual(abs(backRgb.blue - 0.125) < 0.02, true, "RGB → HSV → RGB 蓝分量往返")

    // 灰色：色相取 0（色相条停在最左，不随机跳）
    let gray = SnipHSVColor(SnipAnnotationColor(red: 0.5, green: 0.5, blue: 0.5))
    assertEqual(gray.hue, 0, "灰色色相取 0")
    assertEqual(gray.saturation, 0, "灰色饱和度为 0")

    // 色相按 1 取模（拖过右边界绕回，不越界）
    assertEqual(SnipHSVColor(hue: 1.25, saturation: 1, brightness: 1).hue, 0.25, "色相 1.25 绕回 0.25")
    assertEqual(SnipHSVColor(hue: -0.25, saturation: 1, brightness: 1).hue, 0.75, "负色相绕回 0.75")

    // 方块命中口径：左上 = 白（V=1,S=0），左下 = 黑（V=0）
    let topLeft = SnipColorPickerGeometry.saturationBrightness(atUnit: CGPoint(x: 0, y: 0))
    assertEqual(topLeft.saturation, 0, "左上饱和度为 0")
    assertEqual(topLeft.brightness, 1, "左上明度为 1")
    let bottomLeft = SnipColorPickerGeometry.saturationBrightness(atUnit: CGPoint(x: 0, y: 1))
    assertEqual(bottomLeft.brightness, 0, "左下明度为 0")
    let outside = SnipColorPickerGeometry.saturationBrightness(atUnit: CGPoint(x: -3, y: 5))
    assertEqual(outside.saturation, 0, "越界点夹到边界（x）")
    assertEqual(outside.brightness, 0, "越界点夹到边界（y）")
    assertEqual(SnipColorPickerGeometry.ratio(atX: 15, width: 30), 0.5, "横向比例换算")
    assertEqual(SnipColorPickerGeometry.ratio(atX: 15, width: 0), 0, "零宽不除零")
    let unit = SnipColorPickerGeometry.unitPoint(saturation: 0.25, brightness: 0.75)
    assertEqual(unit.x, 0.25, "选中环横坐标")
    assertEqual(unit.y, 0.25, "选中环纵坐标（明度反向）")

    // 面板几何：取色板放得下（宽等于方块 + 两倍内边距）
    let size = SnipColorPickerGeometry.panelSize
    assertEqual(size.width, SnipColorPickerGeometry.squareSide + SnipColorPickerGeometry.padding * 2,
                "取色板宽度口径")
    assertEqual(size.height > SnipColorPickerGeometry.squareSide, true, "取色板还要装得下两条滑条与底部")
    // 纵向顺序：方块 → 色相条 → 透明度条 → 底部，互不重叠且不越界
    let square = SnipColorPickerGeometry.squareRect(inPanelWithHeight: size.height)
    let hue = SnipColorPickerGeometry.hueRect(squareRect: square)
    let alpha = SnipColorPickerGeometry.alphaRect(hueRect: hue)
    let footer = SnipColorPickerGeometry.footerRect(alphaRect: alpha)
    assertEqual(hue.minY >= square.maxY, true, "色相条在方块下方")
    assertEqual(alpha.minY >= hue.maxY, true, "透明度条在色相条下方")
    assertEqual(footer.minY >= alpha.maxY, true, "底部在透明度条下方")
    assertEqual(footer.maxY <= size.height, true, "底部不越出面板")

    // 二级面板：文字盘条目数 = 字号档 + 加粗 + 字体族
    let textPanel = SnipPanelContent.textStyles(sizes: SnipTextStyle.fontSizePresets,
                                                bold: false,
                                                family: .system)
    assertEqual(textPanel.itemCount,
                SnipTextStyle.fontSizePresets.count + 1 + SnipTextFamily.allCases.count,
                "文字盘条目数")
    let colorPanel = SnipPanelContent.colors([.red, .blue])
    assertEqual(colorPanel.itemCount, 3, "颜色盘末尾多一格「自定义」（2 个固定色 + 1 格自定义）")
    assertEqual(colorPanel.itemTitle(at: 2), "自定义颜色…", "自定义格有名称")
    assertEqual(colorPanel.itemTitle(at: 0), "红色", "固定色仍按名称显示")

    // 画笔盘：线宽档之间插入了两个「−/+」，索引不能错位
    let stylePanel = SnipPanelContent.styles(widths: [2, 4], dashes: [false, true], alphas: [1])
    assertEqual(stylePanel.itemCount,
                2 + SnipPanelContent.stylesStepCount + 2 + 1 + SnipPanelContent.numericInputSlotCount,
                "画笔盘条目数（档位 + −/+ + 线型 + 透明度 + 输入）")
    assertEqual(stylePanel.itemTitle(at: 2), "线宽 −1", "档位之后第一格是减一")
    assertEqual(stylePanel.itemTitle(at: 3), "线宽 +1", "第二格是加一")
    assertEqual(stylePanel.itemTitle(at: 4), "实线", "线型排在加减之后")
    assertEqual(stylePanel.itemTitle(at: 6), "不透明", "透明度排在最后")
    assertEqual(stylePanel.itemTitle(at: 7), "输入数值…", "末格是精确输入")
    assertEqual(stylePanel.numericInputSlotIndex, 7, "输入格索引 = 条目数 - 1")

    print("✅ 标注自定义测试通过")
}

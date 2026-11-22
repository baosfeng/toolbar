import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 工具条三档明度与两级选中语言（A1 / A2 / A3）

/// 覆盖四条口径：选中 / 悬停 / 常态三档明度差、面板与一级的选中语言、
/// 当前色圆点恒带环、以及面板选中描边的宽度常量。
func runSnipBarToneTests() {
    print("🧪 Testing snip bar tone...")

    typealias Tone = SnipBarTone

    // ① 选中与悬停必须拉得开：差值 ≥0.15 才分得清「已选中」与「正悬停」
    // （旧值 0.22 / 0.14 只差 0.08，小尺寸按钮上肉眼无法区分，本条就是守它的）
    assertEqual(Tone.selectedFillAlpha >= Tone.hoverFillAlpha + 0.15, true,
                "选中填充比悬停至少亮 0.15（实测差 \(Tone.selectedFillAlpha - Tone.hoverFillAlpha)）")
    assertEqual(Tone.selectedFillAlpha > Tone.hoverFillAlpha + 0.14, true,
                "派工卡口径：选中 > 悬停 + 0.14")
    assertEqual(Tone.selectedFillAlpha >= 0.30, true, "选中填充不低于 0.30（整格反白的一档）")
    assertEqual(Tone.hoverFillAlpha <= 0.15, true, "悬停填充不高于 0.15（只是轻提示）")

    // ② 三档图标：常态压暗 → 悬停提亮 → 选中纯白
    assertEqual(Tone.iconAlpha(isSelected: false, isHovered: false), Tone.normalIconAlpha,
                "常态图标取压暗档")
    assertEqual(Tone.iconAlpha(isSelected: false, isHovered: true) > Tone.iconAlpha(isSelected: false, isHovered: false),
                true, "悬停图标比常态亮")
    assertEqual(Tone.iconAlpha(isSelected: false, isHovered: true) < 1, true,
                "悬停不是满白（仍是未选中）")
    assertEqual(Tone.iconAlpha(isSelected: true, isHovered: false), 1, "选中图标纯白")
    assertEqual(Tone.iconAlpha(isSelected: true, isHovered: true), 1, "选中且悬停时仍纯白")

    // 三档都落在合法 alpha 区间，绘制不会画出「越界透明」
    for value in [Tone.normalIconAlpha, Tone.hoverIconAlpha, Tone.selectedIconAlpha,
                  Tone.selectedFillAlpha, Tone.hoverFillAlpha, Tone.panelSelectedFillAlpha] {
        assertEqual(value >= 0 && value <= 1, true, "alpha \(value) 落在 0…1")
    }

    // ③ 填充档：两种状态都不成立时不画底；选中优先于悬停
    assertEqual(Tone.fillAlpha(isSelected: false, isHovered: false) == nil, true, "常态不画格底")
    assertEqual(Tone.fillAlpha(isSelected: false, isHovered: true), Tone.hoverFillAlpha, "悬停用悬停档")
    assertEqual(Tone.fillAlpha(isSelected: true, isHovered: true), Tone.selectedFillAlpha,
                "选中且悬停时以选中档为准（不能因为鼠标在上面就掉回悬停色）")

    // ④ 两级选中语言：面板描边、一级填充（两层选择不撞脸）
    assertEqual(Tone.selectionStyle(forPanel: true), .stroke, "二级面板用强调色描边")
    assertEqual(Tone.selectionStyle(forPanel: false), .fill, "一级工具条用整格填充")
    assertEqual(Tone.selectionStyle(forPanel: true) == Tone.selectionStyle(forPanel: false), false,
                "两层选中语言必须不同——这正是「面板与工具条撞脸」的回归点")
    assertEqual(Tone.selectionStrokeWidth > 0, true, "描边宽度为正")
    assertEqual(Tone.panelSelectedFillAlpha < Tone.selectedFillAlpha, true,
                "面板选中底比一级选中底更淡（选中感交给描边）")

    // ⑤ 当前色圆点恒带环：一级当前色 true、面板未选中色点 false
    assertEqual(Tone.colorDotRingVisible(isCurrentColor: true), true, "当前色带选中环")
    assertEqual(Tone.colorDotRingVisible(isCurrentColor: false), false, "未选中的色点不带环")

    print("✅ 工具条三档明度与选中语言测试通过")
}

import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 设置窗口骨架测试

/// 设置窗口骨架的三条不变量 —— 定稿度量、侧栏分组结构、页头胶囊三态
///
/// 为什么测得到：度量数值与分组表放在 `NetworkMonitorUI`（纯逻辑，无 AppKit），
/// App 侧 `SettingsTheme` 只做类型转发，因此这里断言的就是上屏用的那一份数据
/// （不是在测试里抄一份期望值）。
func runSettingsThemeTests() {
    print("\n🧪 Testing 设置窗口骨架（定稿度量 / 侧栏分组 / 页头胶囊）...")

    // MARK: 定稿度量表（逐项钉住，改错一个数就红）

    assertEqual(SettingsSkeletonMetrics.cardRadius, 9, "卡片圆角与面板 cardRadius 同档")
    assertEqual(SettingsSkeletonMetrics.cardPaddingX, 10, "卡片左右内边距")
    assertEqual(SettingsSkeletonMetrics.cardPaddingY, 6, "卡片上下内边距")
    assertEqual(SettingsSkeletonMetrics.rowHeight, 32, "行最小高（面板 28 上调一档）")
    assertEqual(SettingsSkeletonMetrics.rowPaddingY, 2, "行上下内边距")
    assertEqual(SettingsSkeletonMetrics.cardSpacing, 10, "卡片间距")
    assertEqual(SettingsSkeletonMetrics.groupSpacingTop, 12, "分组标题上方间距")
    assertEqual(SettingsSkeletonMetrics.groupSpacingBottom, 6, "分组标题下方间距")
    assertEqual(SettingsSkeletonMetrics.contentInset, 16, "内容区内边距")
    assertEqual(SettingsSkeletonMetrics.sidebarWidth, 168, "侧栏宽度")
    assertEqual(SettingsSkeletonMetrics.sidebarItemHeight, 30, "侧栏导航项高")
    assertEqual(SettingsSkeletonMetrics.statusBandHeight, 20, "状态带 / 胶囊高度")
    assertEqual(SettingsSkeletonMetrics.statusBandRadius, 6, "状态带 / 胶囊圆角")
    assertEqual(SettingsSkeletonMetrics.windowWidth, 760, "窗口宽")
    assertEqual(SettingsSkeletonMetrics.windowHeight, 540, "窗口高")

    // MARK: 侧栏三段分组

    let groups = SettingsSidebarLayout.groups
    assertEqual(groups.count, 3, "侧栏分三段")
    assertEqual(groups.map(\.segment), [.general, .feature, .system], "段序为 常规 → 功能 → 系统")
    assertEqual(groups.map { $0.segment.title }, ["常规", "功能", "系统"], "段头文案")

    let allItems = SettingsSidebarLayout.allItems
    assertEqual(allItems.count, 9, "九个分类全部进侧栏")
    assertEqual(Set(allItems).count, 9, "九个分类各出现一次（无重复、无遗漏）")
    assertEqual(allItems, SettingsSectionID.allCases, "侧栏顺序与分类顺序一致")
    for id in SettingsSectionID.allCases {
        assertNotNil(SettingsSidebarLayout.segment(of: id), "分类 \(id.rawValue) 必须属于某一段")
    }
    assertEqual(groups.first { $0.segment == .general }?.items, [.general, .appearance],
                "常规段 = 通用 + 外观")
    assertEqual(groups.first { $0.segment == .system }?.items, [.system, .about],
                "系统段 = 系统 + 关于")

    // MARK: 页头状态点三态

    assertEqual(SettingsStatusTone.allCases, [.ok, .warn, .muted], "状态点只有三种语义")
    assertEqual(SettingsStatusTone.ok.themeRole, .okInk, "达标 → okInk")
    assertEqual(SettingsStatusTone.warn.themeRole, .warnInk, "告警 → warnInk")
    assertEqual(SettingsStatusTone.muted.themeRole, .ghost, "中性 → ghost")

    // MARK: 胶囊文案拼接（正常 / 空值 / 超长）

    assertEqual(SettingsStatusChip.text(subject: "Apple", detail: "极致"), "Apple · 极致",
                "主语 + 细节用间隔号连接")
    assertEqual(SettingsStatusChip.text(subject: "已授权", detail: "386 条"), "已授权 · 386 条",
                "中英混排同样走间隔号")
    assertEqual(SettingsStatusChip.text(subject: "采样 1.0 s", detail: nil), "采样 1.0 s",
                "只有主语时不带孤立间隔号")
    assertEqual(SettingsStatusChip.text(subject: "", detail: "查询中"), "查询中",
                "只有细节时只显示细节")
    assertEqual(SettingsStatusChip.text(subject: "", detail: nil), "", "全空 → 空文案（页面据此不挂胶囊）")
    assertEqual(SettingsStatusChip.text(subject: "  ", detail: "   "), "", "全空白等价于全空")
    assertEqual(SettingsStatusChip.text(subject: " Apple ", detail: " 极致 "), "Apple · 极致",
                "两端空白被裁掉")

    let longDetail = String(repeating: "长", count: 60)
    let longText = SettingsStatusChip.text(subject: "额度", detail: longDetail)
    assertEqual(longText.count, SettingsStatusChip.maxLength, "超长文案截断到上限长度")
    assertEqual(longText.hasSuffix("…"), true, "超长文案以省略号收尾")
    assertEqual(longText.hasPrefix("额度 · 长"), true, "截断保留开头的主语")

    // 边界：上限内不截断 / 恰好等于上限不截断
    let exact = String(repeating: "a", count: SettingsStatusChip.maxLength)
    assertEqual(SettingsStatusChip.text(subject: exact, detail: nil), exact, "恰好等于上限不截断")

    assertEqual(SettingsStatusChip(subject: "系统", detail: "采样 1.0 s", tone: .muted).text,
                "系统 · 采样 1.0 s", "结构体便捷入口与纯函数同一口径")

    // MARK: 胶囊在七页里的实际文案形态（页面侧拼接，这里钉住纯函数产出）

    assertEqual(SettingsStatusChip(subject: "Apple", detail: "极致").tone, .ok,
                "不传 tone 时默认达标（外观页用默认档）")
    assertEqual(SettingsStatusChip(subject: "0 台在线").text, "0 台在线",
                "只有一个主语时（互传 / 系统页）不出现间隔号")
    assertEqual(SettingsStatusChip(subject: "已允许", detail: "386 个文件").text, "已允许 · 386 个文件",
                "剪贴板页：授权态 · 文件数")
    assertEqual(SettingsStatusChip(subject: "JPEG", detail: "质量 0.90").text, "JPEG · 质量 0.90",
                "截图页：输出格式 · JPEG 质量")
    assertEqual(SettingsStatusChip(subject: "已授权", detail: "音量 60%").text, "已授权 · 音量 60%",
                "通知与音效页：授权态 · 应用内音量")
    assertEqual(SettingsStatusChip(subject: "1 个已配置", detail: "查询中").text, "1 个已配置 · 查询中",
                "额度 Provider 页：实例数 · 查询态")

    // 边界：截断保留主语、maxLength ≤ 1 时只留省略号
    assertEqual(SettingsStatusChip.text(subject: "额度", detail: longDetail, maxLength: 3).count, 3,
                "自定义上限同样截断到上限长度")
    assertEqual(SettingsStatusChip.text(subject: "额度", detail: "长", maxLength: 1), "…",
                "上限为 1 时只保留省略号")

    // 状态点三档语义在页面侧只有这三种（不引入第四种颜色）
    assertEqual(Set(SettingsStatusTone.allCases.map(\.themeRole)).count, 3,
                "三种语义映射到三个不同主题角色，没有重复档")

    print("✅ 设置窗口骨架 works")
}

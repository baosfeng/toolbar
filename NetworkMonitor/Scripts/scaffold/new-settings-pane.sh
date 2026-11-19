#!/bin/bash
# 新增「设置分页」脚手架 —— 生成 SettingsPane 子类 + 打印必须人工改的 6 处
#
# 用法：
#   bash NetworkMonitor/Scripts/scaffold/new-settings-pane.sh <id> <中文名> [--dry-run] [--out <目录>] [--force]
#
# id 即 SettingsSection 的 case 名与 SettingsSectionID 的 rawValue，发布后不可变更
# （偏好顺序键与快照文件名都按它存）。

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

usage() {
    echo "用法：new-settings-pane.sh <id> <中文名> [选项]"
    echo ""
    echo "  id       小写字母 / 数字 / 连字符，如 network、disk-health"
    echo "  中文名   侧栏与页头标题，如「网络」"
    usage_common
}

POSITIONAL=()
parse_common_args "$@"

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
    usage >&2
    exit 2
fi

SECTION_ID="${POSITIONAL[0]}"
TITLE="${POSITIONAL[1]}"
require_id "${SECTION_ID}" "设置分类 id"

PASCAL="$(pascal_case "${SECTION_ID}")"
TARGET_DIR="${OUT_DIR:-${NM_DIR}/Sources/NetworkMonitor/Settings}"
PANE_PATH="${TARGET_DIR}/Settings${PASCAL}Pane.swift"

echo "设置分页脚手架：id=${SECTION_ID} / 中文名=${TITLE} / 类名=Settings${PASCAL}Pane"

render_pane() {
    sed -e "s/__PASCAL__/${PASCAL}/g" -e "s/__SECTION_ID__/${SECTION_ID}/g" -e "s|__TITLE__|${TITLE}|g" <<'SWIFT'
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - __TITLE__设置页

/// __TITLE__设置页 —— 由 Scripts/scaffold/new-settings-pane.sh 生成
///
/// 版式统一走 SettingsPaneView 的 page 栈：page.addCard(card, sectionTitle:) 追加卡片，
/// page.addNote(_:) 追加页尾说明；页头标题与副标题由 SettingsSection 提供，不要在本文件里再写一遍。
///
/// 两阶段接入（生成物可直接编译）：
/// 1. 现在：super.init 用 rawValue 回落到 .general，页头临时显示「通用」；
/// 2. 在 SettingsSection 加 __PASCAL__ = "__SECTION_ID__" case 后，把下面的 super.init 换成
///    super.init(section: .__PASCAL__) —— 人工步骤 1 里给了精确行号。
///
/// 文案 / 图标 / 页头副标题 / 快照后缀一律取 `SettingsSectionCatalog` 的描述符，
/// 本文件不写死标题（中文标题只在描述符里存一份）。
final class Settings__PASCAL__Pane: SettingsPaneView {

    // MARK: 行

    private let enabledRow = SettingsRowView(title: "启用",
                                             subtitle: "开关写入偏好即生效（禁止直读 UserDefaults，走 KeyValueStorage）")
    private let enabledSwitch = NSSwitch()

    // MARK: - 初始化

    init() {
        // 见类型注释「两阶段接入」：加完 SettingsSection 的 case 后改成 .__PASCAL__
        super.init(section: SettingsSection(rawValue: "__SECTION_ID__") ?? .general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 内容

    override func buildContent() {
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)
        enabledSwitch.setAccessibilityLabel("启用")
        enabledRow.trailingStack.addArrangedSubview(enabledSwitch)

        let card = SettingsCardView()
        card.addRow(enabledRow)
        page.addCard(card, sectionTitle: "__TITLE__")
        page.addNote("尚未接入真实配置：把这一行换成该页真正的设置项，并在 refresh() 里同步外部状态。")
    }

    /// 切到该页与窗口重新显示时调用 —— 用于同步权限 / 凭据 / 设备清单等外部状态
    override func refresh() {
        enabledSwitch.state = .off
    }

    // MARK: - 动作

    @objc private func enabledChanged() {
        // 写偏好 + 发 AppEvents（漏发事件的后果是「设置切了但界面没变」，见编码规范第 6 条）
    }
}
SWIFT
}

emit_file "${PANE_PATH}" "$(render_pane)"

print_step_header 6


echo ""
echo "1. 加枚举 case + 描述符（四个 switch 已由描述符取代）"
echo "   Sources/NetworkMonitor/Settings/SettingsSection.swift:11   enum SettingsSection: String, CaseIterable"
echo "     · 加 case ${PASCAL} = \"${SECTION_ID}\"（顺序即侧栏顺序；插到语义相邻处）"
echo "       —— case 名必须是合法标识符，这里用 PascalCase 并显式给出 rawValue 字符串（id 可带连字符）"
echo "     · title / symbolName / fileSuffix / subtitle 四个属性一律转发描述符，本文件不用补 switch"
echo "   Sources/NetworkMonitorUI/SettingsSectionDescriptor.swift:84  SettingsSectionCatalog.descriptors 追加一条"
echo "       SettingsSectionDescriptor(id: .${PASCAL}, title: \"${TITLE}\","
echo "                                 symbolName: <SF Symbols 名，禁止 emoji>,"
echo "                                 subtitle: <一句话说明这一页管什么>,"
echo "                                 fileSuffix: \"${SECTION_ID}\", group: <见步骤 3 的分段>)"
echo "     · 这一条是侧栏标题 / 图标 / 页头副标题 / 快照后缀 / 侧栏分段的唯一真源"
echo "     · 补完后把 Settings${PASCAL}Pane.swift 的 super.init 改成 .${PASCAL}"

echo ""
echo "2. 登记 UI 侧稳定 id（case 名与 App 侧一致，rawValue 是同一个 id 字符串）"
echo "   Sources/NetworkMonitorUI/SettingsSkeletonLogic.swift:81  SettingsSectionID 加 case ${PASCAL} = \"${SECTION_ID}\""

echo ""
echo "3. 进侧栏分组（唯一真源，且必须与描述符的 group 字段一致）"
echo "   Sources/NetworkMonitorUI/SettingsSkeletonLogic.swift:116-121  SettingsSidebarLayout.groups"
echo "     · 选一段塞进去：general（常规）/ feature（功能）/ system（系统）"
echo "     · 步骤 1 里描述符的 group 必须填同一段：两处不一致时 SettingsSectionCatalog.validate 判 groupMismatch"
echo "     · 漏这一步：分类存在但侧栏不显示，页也切不过去"

echo ""
echo "4. 挂工厂"
echo "   Sources/NetworkMonitor/AppCoordinator+Settings.swift:27  registerSettingsModules 加一条 register"
echo "       modules.register(SettingsModule(section: .${PASCAL}) { [weak self] in"
echo "           guard let self else { return Self.unavailable(.${PASCAL}) }"
echo "           return Settings${PASCAL}Pane()"
echo "       })"
echo "     · 新增分类只加这一条 register，不改任何既有条目（顺序由 SettingsSectionCatalog 决定）"
echo "     · 依赖缺失时返回占位页（Self.unavailable），不要让设置窗口打不开"

echo ""
echo "5. 测试（计数断言不再写死数字，通常不必改）"
echo "   Sources/TestRunner/SettingsThemeTests.swift:56/58  若塞进已有段，该段的 items 期望数组要更新"
echo "   Sources/TestRunner/ModuleRegistryTests.swift      描述符非空（标题 / 图标 / 副标题 / 后缀）由通用断言覆盖"
echo "     · 分类数量与顺序一律与 SettingsDescriptorRegistry 对表，不再有「11 → 12」这类硬编码"

echo ""
echo "6. 文档与测试登记"
echo "   AGENTS.md「统一设置窗口」行：十一分类 → 十二分类，写清这一页的口径"
echo "   Sources/TestRunner/TestSuites+Pane.swift  若新增测试文件，加 runXxxTests()"
echo "   规范出处：docs/开发指南/扩展点清单.md「设置分类」一节"

echo ""
echo "生成后可立刻编译（super.init 回落到 .general，页头临时显示「通用」）："
echo "  cd NetworkMonitor && swift build --disable-sandbox --build-system native"

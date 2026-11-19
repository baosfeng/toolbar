#!/bin/bash
# 新增「菜单面板分页」脚手架 —— 生成 Pane 文件 + 打印必须人工改的 7 处
#
# 用法：
#   bash NetworkMonitor/Scripts/scaffold/new-panel-tab.sh <id> <中文名> [--dry-run] [--out <目录>] [--force]
#
# id 同时用作：稳定 id（PanelTabCatalog.stableIDs）、描述符 id / 快照后缀 / 取证键
# （PaneModuleCatalog.descriptors 一行写全）、偏好顺序键元素 —— 发布后不可变更。

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

usage() {
    echo "用法：new-panel-tab.sh <id> <中文名> [选项]"
    echo ""
    echo "  id       小写字母 / 数字 / 连字符，如 weather、disk-health"
    echo "  中文名   分段条文字，如「天气」"
    usage_common
}

POSITIONAL=()
parse_common_args "$@"

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
    usage >&2
    exit 2
fi

TAB_ID="${POSITIONAL[0]}"
TITLE="${POSITIONAL[1]}"
require_id "${TAB_ID}" "分页 id"

PASCAL="$(pascal_case "${TAB_ID}")"
CAMEL="$(camel_case "${TAB_ID}")"
TARGET_DIR="${OUT_DIR:-${NM_DIR}/Sources/NetworkMonitor/MenuPanel}"
PANE_PATH="${TARGET_DIR}/${PASCAL}PaneView.swift"

echo "面板分页脚手架：id=${TAB_ID} / 中文名=${TITLE} / 类名=${PASCAL}PaneView"

render_pane() {
    sed -e "s/__PASCAL__/${PASCAL}/g" -e "s/__TAB_ID__/${TAB_ID}/g" -e "s|__TITLE__|${TITLE}|g" <<'SWIFT'
import AppKit

// MARK: - __TITLE__页

/// __TITLE__页 —— 菜单面板分页（稳定 id __TAB_ID__）
///
/// 由 Scripts/scaffold/new-panel-tab.sh 生成。版式与其余分页同一套骨架：
/// 页头（22pt，PaneHeaderRowView）→ 内容 → 页脚状态带（20pt，PaneStateBandView）。
/// 不要各画一遍页头页脚，几何与配色只取 PaneCardStyle。
///
/// 装配位置（生成器打印的人工步骤里逐条给了 file:line）：
/// - 描述符（文案 / 图标 / 快照后缀 / 取证标识）：PaneModuleDescriptor.swift 的 PaneModuleCatalog
/// - 枚举编号：MenuTabBarView.swift 的 MenuPanelTab
/// - 稳定 id：PanelTabCatalog.swift 的 stableIDs
/// - 装配件（造页 / 挂回调 / 首屏补数）：PaneModule.swift 的 makeModule(for:)
final class __PASCAL__PaneView: MenuPanelPaneView {

    // MARK: 子视图

    /// 页头行 —— 五页共用这一件
    private let headerView = PaneHeaderRowView(title: "__TITLE__")
    /// 页脚状态带 —— 五页共用这一壳
    private let stateBand = PaneStateBandView()
    /// 内容区占位（接入真实数据后替换）
    private let placeholderLabel = MenuPanelLabel.text("尚未接入数据源",
                                                      font: PaneCardStyle.metaFont,
                                                      color: PaneCardStyle.tertiaryText)

    // MARK: 状态

    /// 最近一帧状态文案（面板装配时由 update(statusText:) 注入）
    private(set) var statusText = "未启动"

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
        refreshBand()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 版式

    /// 骨架：页头 → 内容区 → 弹性空白 → 状态带（与其余分页同构）
    private func buildLayout() {
        let contentStack = NSStackView(views: [placeholderLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = PaneCardStyle.cardSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [headerView, contentStack, MenuPanelLabel.spacer(), stateBand])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PaneCardStyle.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    // MARK: - 数据入口

    /// 数据刷新入口 —— 由面板装配时调用（注册表里该页的 firstDisplay 闭包也会调一次）
    ///
    /// 只更新模型并重画，不在这里改写面板尺寸；内容高度变化时由调用方发
    /// menuPanelViewDidChangeContent（见额度页 / Token 页的装配写法）。
    func update(statusText: String) {
        guard self.statusText != statusText else { return }
        self.statusText = statusText
        refreshBand()
    }

    private func refreshBand() {
        stateBand.update(items: [("状态", statusText)])
    }
}
SWIFT
}

emit_file "${PANE_PATH}" "$(render_pane)"

print_step_header 7

echo ""
echo "1. 加描述符（文案 / 图标 / 快照后缀 / 取证标识一次写全）"
echo "   Sources/NetworkMonitorUI/PaneModuleDescriptor.swift:103  PaneModuleCatalog.descriptors 追加一条"
echo "       PaneModuleDescriptor(id: \"${TAB_ID}\", rawValue: <新编号>, title: \"${TITLE}\","
echo "                           symbolName: <SF Symbols 名，禁止 emoji>,"
echo "                           snapshotSuffix: \"${TAB_ID}\", evidenceKey: \"${TAB_ID}\", sortIndex: <末尾序>)"
echo "     · 这一条同时是分段条文案 / 图标 / 快照文件名后缀 / NM_SNAPSHOT_* 取证键的唯一真源，别再逐个 switch 抄"
echo "     · 顺序即默认顺序；追加在语义相邻处，sortIndex 与声明位置一致"

echo ""
echo "2. 加枚举 case（只登记编号，不再有 title / stableID / symbolName 三个 switch）"
echo "   Sources/NetworkMonitor/MenuPanel/MenuTabBarView.swift:15  enum MenuPanelTab: Int"
echo "     · 加 case ${CAMEL} = <新编号>（编号取未占用的最大值 +1，不复用已下线编号）"
echo "       —— case 名必须是合法标识符，所以用 camelCase；带连字符的 id 只出现在描述符里"
echo "     · title / stableID / symbolName / fileNameSuffix 一律由描述符转发，本文件不用改"

echo ""
echo "3. 登记稳定 id"
echo "   Sources/NetworkMonitorUI/PanelTabCatalog.swift:15  stableIDs 追加「${TAB_ID}」"
echo "     · 顺序即默认顺序，必须与描述符声明序（sortIndex）一致，否则注册表自洽断言判红"
echo "     · 若本次还要下线某个分页：id 移进 retiredIDs(:23)，并在 legacyRawValueToStableID(:30) 保留旧编号"

echo ""
echo "4. 加装配件分支（造页 / 挂回调 / 首屏补数三件事合并在这里）"
echo "   Sources/NetworkMonitor/MenuPanel/PaneModule.swift:119  makeModule(for:) 加一条 case"
echo "       case \"${TAB_ID}\":"
echo "           return PaneModule(descriptor: descriptor,"
echo "                             makePane: { ${PASCAL}PaneView() },"
echo "                             configure: { controller, pane in"
echo "                                 guard let pane = pane as? ${PASCAL}PaneView else { return }"
echo "                                 // 挂 onRefresh / onContentChanged 等回调（无回调就整段省略）"
echo "                             },"
echo "                             firstDisplay: { controller, pane in"
echo "                                 // 首屏不要停在 0 / 空态（无补数需求就整段省略）"
echo "                             })"
echo "     · 新增分页**只加这一条分支，不改任何既有分支**；标准装配按 id 逐条登记，其余页零改动"
echo "     · 未登记的 id 在开发期 assertionFailure、release 下该页不装配（不崩）"

echo ""
echo "5. 测试（注册表自洽断言会红，这是设计如此）"
echo "   Sources/TestRunner/ModuleRegistryTests.swift:31  期望数组追加一条（id / 编号 / 文案 / 图标 / 后缀逐项固定）"
echo "   Sources/TestRunner/PanelTabCatalogTests.swift     不必改数字：分页数一律与注册表对表"
echo "   Sources/TestRunner/PaneHeightBudgetTests.swift    不必改：预算判据是通用的（pane 458 / 内容 408pt），不按页枚举"
echo "     · 新页首屏实际高度超预算时，先收缩条数（PaneHeightBudget.rowLimit），不要放宽预算"

echo ""
echo "6. 登记测试入口（仅当新增了测试文件）"
echo "   Sources/TestRunner/TestSuites+Pane.swift  加 runXxxTests()"
echo "     · 忘登记不会编译报错，但 TestSuiteRegistrationTests 会把「定义了却没人调用」判红"

echo ""
echo "7. 文档"
echo "   AGENTS.md「面板视觉语言」行：五个 tab → 六个 tab，写清新分页口径"
echo "   规范出处：docs/开发指南/扩展点清单.md「面板分页」一节"

echo ""
echo "生成后可立刻编译：cd NetworkMonitor && swift build --disable-sandbox --build-system native"
echo "（上面 7 处人工步骤未做时：文件能编译，但分页不会出现、也切不过去）"

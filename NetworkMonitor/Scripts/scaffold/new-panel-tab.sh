#!/bin/bash
# 新增「菜单面板分页」脚手架 —— 生成 Pane 文件 + 打印必须人工改的 9 处
#
# 用法：
#   bash NetworkMonitor/Scripts/scaffold/new-panel-tab.sh <id> <中文名> [--dry-run] [--out <目录>] [--force]
#
# id 同时用作：稳定 id（PanelTabCatalog.stableIDs）、快照文件名后缀、
# NM_SNAPSHOT_* 取证键、偏好顺序键元素 —— 发布后不可变更。

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
/// - 枚举与分段条：MenuTabBarView.swift 的 MenuPanelTab
/// - 稳定 id：PanelTabCatalog.swift 的 stableIDs
/// - 懒装配：MenuPanelView+Panes.swift 的 ensurePaneLoaded
/// - 回调：MenuPanelController.swift 的 configure(pane:for:)
/// - 首屏补数：MenuPanelController+Actions.swift 的 refreshPaneFirstDisplay
/// - 快照 / 取证：MenuPanelSnapshot.swift 的 fileNameSuffix、MenuPanelEvidence.swift
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

    /// 数据刷新入口 —— 由面板装配时调用（首屏 refreshPaneFirstDisplay 也会调一次）
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

print_step_header 9

echo ""
echo "1. 加枚举 case（3 个 switch 一起加）"
echo "   Sources/NetworkMonitor/MenuPanel/MenuTabBarView.swift:14  enum MenuPanelTab: Int"
echo "     · 加 case ${CAMEL} = <新编号>（编号取未占用的最大值 +1，不复用已下线编号）"
echo "       —— case 名必须是合法标识符，所以用 camelCase；带连字符的 id 只出现在 stableID 字符串里"
echo "     · :22 title      → 「${TITLE}」"
echo "     · :36 stableID   → 「${TAB_ID}」（字符串，必须与 PanelTabCatalog.stableIDs 同源）"
echo "     · :47 symbolName → SF Symbols 名（禁止 emoji）"

echo ""
echo "2. 登记稳定 id"
echo "   Sources/NetworkMonitorUI/PanelTabCatalog.swift:15  stableIDs 追加「${TAB_ID}」"
echo "     · 顺序即默认顺序；追加在语义相邻处，不要打乱既有顺序"
echo "     · 若本次还要下线某个分页：id 移进 retiredIDs(:23)，并在 legacyRawValueToStableID(:30) 保留旧编号"

echo ""
echo "3. 懒装配 + 分派"
echo "   Sources/NetworkMonitor/MenuPanel/MenuPanelView+Panes.swift:35-43  追加"
echo "       var ${CAMEL}Pane: ${PASCAL}PaneView { loadedPane(.${CAMEL}) { ${PASCAL}PaneView() } }"
echo "   Sources/NetworkMonitor/MenuPanel/MenuPanelView+Panes.swift:49-57  ensurePaneLoaded 加"
echo "       case .${CAMEL}: return ${CAMEL}Pane"

echo ""
echo "4. 回调装配"
echo "   Sources/NetworkMonitor/MenuPanel/MenuPanelController.swift:221-260  configure(pane:for:) 加分支"
echo "       case .${CAMEL}:"
echo "           guard let pane = pane as? ${PASCAL}PaneView else { return }"
echo "           // 挂 onRefresh / onContentChanged 等回调；无回调就与 .network / .system 一样 break"

echo ""
echo "5. 首屏补数"
echo "   Sources/NetworkMonitor/MenuPanel/MenuPanelController+Actions.swift:106-126  refreshPaneFirstDisplay 加"
echo "       case .${CAMEL}:"
echo "           content.${CAMEL}Pane.update(statusText: ...)   // 首屏不要停在 0 / 空态"

echo ""
echo "6. 快照文件名与取证键"
echo "   Sources/NetworkMonitor/Debug/MenuPanelSnapshot.swift:253-264  fileNameSuffix 加"
echo "       case .${CAMEL}: return 「${TAB_ID}」"
echo "   Sources/NetworkMonitor/Debug/MenuPanelEvidence.swift:64-70  取证键映射加"
echo "       case 「${TAB_ID}」: return .${CAMEL}"

echo ""
echo "7. 测试（两处硬编码计数会红，这是设计如此）"
echo "   Sources/TestRunner/PanelTabCatalogTests.swift:21  stableIDs.count 递增"
echo "   Sources/TestRunner/PanelTabCatalogTests.swift:24  期望数组追加「${TAB_ID}」"
echo "   Sources/TestRunner/PanelTabCatalogTests.swift:44  legacyRawValueToStableID.count 若新增编号则 +1"
echo "   Sources/TestRunner/PanelTabCatalogTests.swift:49  冻结映射的在用 id 集合仍须等于 stableIDs"
echo "   Sources/TestRunner/PaneHeightBudgetTests.swift   新分页补一条高度预算（pane 恒 458pt）"

echo ""
echo "8. 登记测试入口"
echo "   Sources/TestRunner/TestSuites+Pane.swift  加 runXxxTests()"
echo "     · 忘登记不会编译报错，但 TestSuiteRegistrationTests 会把「定义了却没人调用」判红"

echo ""
echo "9. 文档"
echo "   AGENTS.md「面板视觉语言」行：五个 tab → 六个 tab，写清新分页口径"
echo "   规范出处：docs/开发指南/扩展点清单.md「面板分页」一节"

echo ""
echo "生成后可立刻编译：cd NetworkMonitor && swift build --disable-sandbox --build-system native"
echo "（上面 9 处人工步骤未做时：文件能编译，但分页不会出现、也切不过去）"

import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - Token 页页头（来源切换器 / 范围分段 / 刷新）

/// 页头的装配与同步 —— 从 `+Layout.swift` / `+Render.swift` / `+Interaction.swift` 摘出。
///
/// 这里是一个完整职责：页头这一条行怎么搭、每帧怎么同步、来源切换怎么落偏好。
/// 三处改动永远一起发生（改页头布局必改同步、改同步必改切换口径），拆开只会让
/// 「页头换了、四屏没换」这类不一致重新出现，所以收在一个文件里；
/// 别的文件只调 buildHeader / wireHeaderActions / syncHeader，不碰页头内部件。
extension TokenPaneView {

    /// 页头一行：来源切换器（页名位）→ 会话数 → 范围分段 → 刷新
    ///
    /// 走五页共用的 `PaneHeaderRowView`（22pt 高、页名 11pt 粗体、右侧动作槽由调用方填），
    /// 页头不再各页自己拼一条 NSStackView。
    func buildHeader() {
        // 时间口径必须写在界面上：自然日 / 自然周边界固定按 Asia/Shanghai 切分，
        // 不跟随系统时区。用户把 Mac 时区改到别的地区后「今日」与系统日历不是同一天，
        // 这个差异原本界面上没有任何说明——工具提示与读屏标签都补上（挂在页头视图上）。
        headerView.toolTip = TokenTimeZoneNote.text
        // 首帧渲染前口径文字为空串：先按 nil 收起，避免页头里留一个 0 宽的空标签。
        // updateMeta 会按「页名，口径」重设读屏标签，所以时区口径的读屏标签放在它之后设。
        headerView.updateMeta(nil)
        headerView.setAccessibilityLabel(TokenTimeZoneNote.text)
        // 页名位换成来源切换器：页头宽度预算只有 296pt，来源名放右侧会把范围分段挤走
        headerView.setTitleControl(sourceSelector)
        headerView.setTrailing([rangeControl, refreshRow])
        addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.topAnchor.constraint(equalTo: topAnchor),
        ])
        // 页头自身带着 22pt 高约束（PaneCardStyle.pageHeadHeight），这里不再重复给高度
        contentTopAnchor = headerView.bottomAnchor
    }

    /// 页头口径文字：Core 的 hostLabel 形如「Claude Code · 42 会话」或「全部 · 1,284 会话」，
    /// 来源名已由页头左侧切换器承担，原样贴到右侧会重复一遍，这里只保留「42 会话」。
    /// 前缀取自同一份模型（model.sourceLabel），切换来源时两处不会各说一个名字。
    /// 前缀对不上（Core 改了措辞）就原样透传，不静默丢信息。
    func headerMeta(from model: TokenPaneModel) -> String {
        let prefix = model.sourceLabel + " · "
        guard model.hostLabel.hasPrefix(prefix) else { return model.hostLabel }
        return String(model.hostLabel.dropFirst(prefix.count))
    }

    /// 每帧同步页头：来源切换器的选项与选中项、口径文字、读屏标签、范围分段
    ///
    /// 页名由页头左侧的来源切换器承担（单源时直接写该来源名），右侧口径只放会话数。
    func syncHeader(with model: TokenPaneModel, options: [TokenSourceID]) {
        sourceSelector.update(current: source, options: options)
        headerView.updateMeta(headerMeta(from: model))
        // 每次渲染都重设：页头视图的默认无障碍文案由页名 + 口径文字拼成，
        // 只在装配时设一次会被后续 updateMeta 覆盖掉，读屏就听不到时区口径了
        headerView.setAccessibilityLabel(model.hostLabel + "。" + TokenTimeZoneNote.text)
        rangeControl.select(range.rawValue, notify: false)
    }

    /// 页头接线：来源切换器选中某一项后写偏好并重渲（四屏 / 二级页走同一条 render）
    func wireHeaderActions() {
        sourceSelector.onSelect = { [weak self] id in self?.selectSource(id) }
    }

    // MARK: - 来源切换

    /// 切换来源：写偏好 → 重渲（全在一条路径上，避免「页头换了、四屏没换」）
    ///
    /// 二级页开着时先返回主面板：两个来源的数值不能拼在一屏里「半新半旧」。
    /// 持久化走 `TokenSourcePreferences`（禁止散字符串键）。
    func selectSource(_ id: TokenSourceID?) {
        guard source != id else { return }
        source = id
        TokenSourcePreferences.setSelectedSource(id, storage: storage)
        guard snapshot != nil else { return }
        if isShowingDetail {
            closeDetail()
        } else {
            applyStateMachine()
        }
    }
}

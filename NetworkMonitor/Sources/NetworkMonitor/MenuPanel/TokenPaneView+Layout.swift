import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 页布局装配（TokenPaneView 扩展）

/// 页头一行（主机 + 范围 + 刷新）→ 屏切换条 → 当前屏内容栈；
/// 二级页容器覆盖在最上层，与主内容互斥显示。
/// 从 TokenPaneView.swift 拆出（单文件体积门禁）。
extension TokenPaneView {

    /// 页头一行：DSH · 会话数（口径文字）→ 范围分段 → 刷新
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

    /// 页头口径文字：Core 的 hostLabel 形如「DSH · 1866 会话」，页名「DSH」已由页头左侧承担，
    /// 原样贴到右侧会把 DSH 重复一遍，这里只保留「1866 会话」。
    /// 前缀对不上（Core 改了措辞）就原样透传，不静默丢信息。
    ///
    /// 跨文件（+Render.swift）调用故为 internal。
    func headerMeta(from hostLabel: String) -> String {
        let prefix = TokenPaneView.pageTitle + " · "
        guard hostLabel.hasPrefix(prefix) else { return hostLabel }
        return String(hostLabel.dropFirst(prefix.count))
    }

    func buildSections() {
        buildFamilyGrid()
        buildHourCard()
        buildTrendCard()
        buildCompareCard()
        buildOverviewTrendCard()
        screenFrames = buildScreenFrames()

        dataStack.orientation = .vertical
        dataStack.alignment = .leading
        dataStack.spacing = PaneCardStyle.cardSpacing
        // 屏切换条固定在第一行，其下四个屏栈按契约顺序排列，渲染时只显示当前屏
        dataStack.addArrangedSubview(screenControl)
        screenControl.widthAnchor.constraint(equalTo: dataStack.widthAnchor).isActive = true
        for frame in screenFrames {
            dataStack.addArrangedSubview(frame)
            frame.widthAnchor.constraint(equalTo: dataStack.widthAnchor).isActive = true
        }
        dataStack.isHidden = true
        loadingView.isHidden = true
        emptyView.isHidden = true
        unavailableView.isHidden = true

        let root = NSStackView(views: [indexLabel, dataStack, loadingView, emptyView, unavailableView])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 4
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: contentTopAnchor ?? topAnchor, constant: 3),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in [indexLabel, dataStack, loadingView, emptyView, unavailableView] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        indexLabel.isHidden = true

        // 二级页覆盖层（同一 Pane 内切换，不新开窗口）
        detailPane.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailPane)
        NSLayoutConstraint.activate([
            detailPane.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailPane.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailPane.topAnchor.constraint(equalTo: topAnchor),
            detailPane.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        detailPane.isHidden = true
    }

    // MARK: - 屏装配

    /// 四个屏的外框（顺序 = TokenScreen.allCases）
    ///
    /// 概览 / 用量：按 TokenScreen.blocks 契约逐块装配（switch 无 default，漏接即编译不过）；
    /// 缓存 / 排行：整块视图自带内容栈，页脚分别是口径说明卡与状态带。
    /// 外框高度统一给死（screenHeight），页脚固定屏底，超高内容走屏内滚动。
    private func buildScreenFrames() -> [TokenScreenFrameView] {
        var frames: [TokenScreenFrameView] = []
        for screen in TokenScreen.allCases {
            let content: NSStackView
            let footer: NSView
            switch screen {
            case .overview, .usage:
                content = makeBlockStack(for: screen)
                footer = band(for: screen)
            case .cache:
                content = cacheScreen
                footer = cacheScreen.footerView
            case .ranking:
                content = rankScreen
                footer = band(for: screen)
            }
            frames.append(TokenScreenFrameView(content: content, footer: footer,
                                               height: Self.screenHeight))
        }
        return frames
    }

    private func makeBlockStack(for screen: TokenScreen) -> NSStackView {
        let stack = NSStackView()
        for block in TokenScreen.blocks(for: screen) {
            for view in blockViews(block) {
                stack.addArrangedSubview(view)
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return stack
    }

    /// 屏页脚：概览 / 用量 / 排行各用一个状态带实例（一个视图不能挂两处）
    private func band(for screen: TokenScreen) -> NSView {
        switch screen {
        case .overview: return overviewBand
        case .usage: return usageBand
        case .ranking: return rankingBand
        case .cache: return cacheScreen.footerView
        }
    }

    /// 区块 → 视图；缓存屏与排行屏的区块在各自屏视图内部，故返回空
    private func blockViews(_ block: TokenScreenBlock) -> [NSView] {
        switch block {
        case .hero: return [heroView]
        case .familyCards: return [familyGrid]
        case .cacheHit: return [cacheHitStrip]
        case .overviewTrend: return [overviewTrendCard]
        case .compare: return [compareCard]
        case .hourChart: return [hourCard]
        case .trend: return [trendCard]
        case .cacheRing, .cacheTrend, .cacheCompare, .cacheStats, .distroBar, .distroRows:
            return []
        }
    }

    /// 概览屏的「近 14 天 · 固定」迷你走势卡（40pt 高，整卡可点开天趋势明细）
    private func buildOverviewTrendCard() {
        let headRow = NSStackView(views: [overviewTrendTitle, MenuPanelLabel.spacer(), overviewTrendMeta])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        overviewTrendTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        overviewTrendMeta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for row in [headRow, overviewTrendSpark] {
            overviewTrendCard.body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: overviewTrendCard.body.widthAnchor).isActive = true
        }
        setAccessibilityLabel(overviewTrendCard, "近 14 天走势卡，可点击查看 30 天明细")
    }

    // MARK: - 区块装配

    private func buildFamilyGrid() {
        let topRow = NSStackView(views: [familyCards[0], familyCards[1]])
        let bottomRow = NSStackView(views: [familyCards[2], familyCards[3]])
        for row in [topRow, bottomRow] {
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = PaneCardStyle.cardSpacing
        }
        familyGrid.orientation = .vertical
        familyGrid.alignment = .leading
        familyGrid.spacing = PaneCardStyle.cardSpacing
        familyGrid.addArrangedSubview(topRow)
        familyGrid.addArrangedSubview(bottomRow)
        topRow.widthAnchor.constraint(equalTo: familyGrid.widthAnchor).isActive = true
        bottomRow.widthAnchor.constraint(equalTo: familyGrid.widthAnchor).isActive = true
    }

    private func buildHourCard() {
        let headRow = NSStackView(views: [hourTitle, MenuPanelLabel.spacer(), daySegment])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        hourTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let metaRow = NSStackView(views: [hourMeta, MenuPanelLabel.spacer(), viewAction, hourAction])
        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        metaRow.spacing = 4

        for row in [headRow, metaRow, hourBars, hourAxis, hourLegend] {
            hourCard.body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: hourCard.body.widthAnchor).isActive = true
        }
        hourBars.heightAnchor.constraint(equalToConstant: TokenPaneStyle.usageChartHeight).isActive = true
        setAccessibilityLabel(hourCard, "按小时图表卡，可点击查看明细")
    }

    private func buildTrendCard() {
        let headRow = NSStackView(views: [trendTitle, MenuPanelLabel.spacer(), trendMeta, trendAction])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        trendTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trendMeta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for row in [headRow, trendSpark] {
            trendCard.body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: trendCard.body.widthAnchor).isActive = true
        }
        setAccessibilityLabel(trendCard, "天趋势卡，可点击查看 30 天明细")
    }

    private func buildCompareCard() {
        let headRow = NSStackView(views: [MenuPanelLabel.text("今日 vs 昨日同期",
                                                              font: TokenPaneStyle.cardHeadTitleFont,
                                                              color: TokenPaneStyle.secondaryText),
                                          MenuPanelLabel.spacer(), compareTotal, compareDelta])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        for row in [headRow, compareCurrentRow, comparePreviousRow] {
            compareCard.body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: compareCard.body.widthAnchor).isActive = true
        }
        compareCard.onClick = nil
    }

    /// 卡片无障碍角色统一（读屏把整卡当按钮）
    private func setAccessibilityLabel(_ view: NSView, _ label: String) {
        view.setAccessibilityLabel(label)
        view.setAccessibilityRole(.button)
    }
}

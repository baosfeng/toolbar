import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - Token 页布局装配（TokenPaneView 扩展）

/// 页头一行（来源 + 会话数 + 范围 + 刷新）→ 屏切换条 → 当前屏内容栈；
/// 二级页容器覆盖在最上层，与主内容互斥显示。
/// 从 TokenPaneView.swift 拆出（单文件体积门禁）。
extension TokenPaneView {

    func buildSections() {
        buildFamilyGrid()
        buildHourCard()
        buildCompareCard()
        screenFrames = buildScreenFrames()

        dataStack.orientation = .vertical
        dataStack.alignment = .leading
        dataStack.spacing = PaneCardStyle.cardSpacing
        // 屏切换条固定在第一行，其下两个屏栈按契约顺序排列，渲染时只显示当前屏
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

        let root = NSStackView(views: [dataStack, loadingView, emptyView, unavailableView])
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
        for view in [dataStack, loadingView, emptyView, unavailableView] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

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

    /// 两个屏的外框（顺序 = TokenScreen.allCases）
    ///
    /// 两屏都按 TokenScreen.blocks 契约逐块装配（switch 无 default，漏接即编译不过），
    /// 页脚一律是状态带。外框高度统一给死（screenHeight），页脚固定屏底，
    /// 超高内容走屏内滚动；两屏内容都按「填满 385pt 内容预算」定高，不留尾巴。
    private func buildScreenFrames() -> [TokenScreenFrameView] {
        TokenScreen.allCases.map { screen in
            TokenScreenFrameView(content: makeBlockStack(for: screen),
                                 footer: band(for: screen),
                                 height: Self.screenHeight)
        }
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

    /// 屏页脚：两屏各用一个状态带实例（一个视图不能挂两处）
    private func band(for screen: TokenScreen) -> NSView {
        switch screen {
        case .overview: return overviewBand
        case .distro: return distroBand
        }
    }

    /// 区块 → 视图
    private func blockViews(_ block: TokenScreenBlock) -> [NSView] {
        switch block {
        case .hero: return [heroView]
        case .familyCards: return [familyGrid]
        case .cacheHit: return [cacheHitStrip]
        case .hourChart: return [hourCard]
        case .distro: return [rankScreen]
        case .compare: return [compareCard]
        }
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

    /// 总览屏主图卡：卡头（标题 + 今日/昨日分段）→ meta 行（累计 + 三个切换）→ 柱 → 轴 → 图例
    ///
    /// 天趋势入口（14 天 ›）收进 meta 行：两屏收敛后没有独立的「用量」屏，
    /// 但天趋势二级页仍要在一步之内可达，不能藏进主图的点击手势里。
    private func buildHourCard() {
        let headRow = NSStackView(views: [hourTitle, MenuPanelLabel.spacer(), daySegment])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        hourTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let metaRow = NSStackView(views: [hourMeta, MenuPanelLabel.spacer(),
                                          viewAction, hourAction, trendAction])
        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        // 图标按钮之间 4pt（文字态时 6pt 是为了不让「切：A 切：B」粘成一句；
        // 图标本来就有留白，4pt 已经分得开，再宽就白占 meta 行）
        metaRow.spacing = 4

        for row in [headRow, metaRow, hourBars, hourAxis, hourLegend] {
            hourCard.body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: hourCard.body.widthAnchor).isActive = true
        }
        hourBars.heightAnchor.constraint(equalToConstant: TokenPaneStyle.usageChartHeight).isActive = true
        setAccessibilityLabel(hourCard, "按小时图表卡，可点击查看明细")
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

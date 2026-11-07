import AppKit
import NetworkMonitorCore

// MARK: - Token 页布局装配（TokenPaneView 扩展）

/// 页头与各分区装配 —— 从 TokenPaneView.swift 拆出（单文件体积门禁）
///
/// 版式：页头（主机 + 实时 + 时间）→ 范围条（今日/7/30 + 合计 + 刷新）→
/// 四族卡 2×2 → 主图卡 → 天趋势卡 → 缓存环卡 → 项目/模型双栏 → 对比条 → 状态带；
/// 二级页容器覆盖在最上层（与主面板互斥显示）。
extension TokenPaneView {

    /// 页头一行：主机 + 会话数 → 范围分段 → 刷新
    ///
    /// r3：字号上调后原来「页头 + 范围条」两行合并成一行（实时时间与总量都搬进 Hero），
    /// 省下的 ~18pt 高度全部给首屏内容；范围分段与刷新仍是可键盘聚焦的行。
    func buildHeader() {
        hostLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // 时间口径必须写在界面上：自然日 / 自然周边界固定按 Asia/Shanghai 切分，
        // 不跟随系统时区。用户把 Mac 时区改到别的地区后，「今日」与系统日历不是同一天，
        // 而这个差异在界面上原本没有任何说明——工具提示与读屏标签都补上，
        // 免得用户以为是统计错了（运行期数字不动，只把口径说清楚）。
        hostLabel.toolTip = TokenTimeZoneNote.text
        hostLabel.setAccessibilityLabel(TokenTimeZoneNote.text)
        let headRow = NSStackView(views: [hostLabel, MenuPanelLabel.spacer(), rangeControl, refreshRow])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 6
        headRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headRow)
        NSLayoutConstraint.activate([
            headRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            headRow.topAnchor.constraint(equalTo: topAnchor),
            headRow.heightAnchor.constraint(equalToConstant: PaneCardStyle.pageHeadHeight),
        ])
        contentTopAnchor = headRow.bottomAnchor
    }

    func buildSections() {
        buildFamilyGrid()
        buildHourCard()
        buildTrendCard()
        buildCacheCard()
        buildDistroCards()
        buildCompareCard()

        let duoRow = NSStackView(views: [projectCard, modelCard])
        duoRow.orientation = .horizontal
        duoRow.alignment = .top
        duoRow.distribution = .fillEqually
        duoRow.spacing = PaneCardStyle.cardSpacing

        dataStack.orientation = .vertical
        dataStack.alignment = .leading
        dataStack.spacing = PaneCardStyle.cardSpacing
        // 顺序即首屏优先级：Hero → 四族卡 → 24h → 缓存环 → 项目/模型 必须在 520pt 内一次看全；
        // 天趋势 / 对比条 / 状态带是次要块，排在其后由面板滚动承载
        let sections: [NSView] = [heroView, familyGrid, hourCard, cacheCard,
                                  duoRow, trendCard, compareCard, stateBand]
        for view in sections { dataStack.addArrangedSubview(view) }
        for view in sections {
            view.widthAnchor.constraint(equalTo: dataStack.widthAnchor).isActive = true
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

    // MARK: - 分区装配

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
        hourBars.heightAnchor.constraint(equalToConstant: TokenPaneStyle.bucketChartHeight).isActive = true
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

    /// 缓存卡：环 + 标题 + 说明成一行，图例独占第二行（字号提到 10pt 后宽度放不下三行结构）
    private func buildCacheCard() {
        let headRow = NSStackView(views: [cacheRing,
                                          MenuPanelLabel.text("缓存命中率",
                                                              font: TokenPaneStyle.cardHeadTitleFont,
                                                              color: TokenPaneStyle.secondaryText),
                                          MenuPanelLabel.spacer(), cacheMeta])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 6
        cacheLegend.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for row in [headRow, cacheLegend] {
            cacheCard.body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: cacheCard.body.widthAnchor).isActive = true
        }
        setAccessibilityLabel(cacheCard, "缓存命中率卡，可点击查看命中明细")
    }

    private func buildDistroCards() {
        func assemble(card: TokenCardRow, title: String, meta: NSTextField,
                      bar: TokenStackBarView, rows: [TokenDistroRowView], accessibility: String) {
            let titleLabel = MenuPanelLabel.text(title,
                                                 font: TokenPaneStyle.cardTitleFont,
                                                 color: TokenPaneStyle.secondaryText)
            let headRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), meta])
            headRow.orientation = .horizontal
            headRow.alignment = .centerY
            headRow.spacing = 3
            var views: [NSView] = [headRow, bar]
            views.append(contentsOf: rows)
            for view in views {
                card.body.addArrangedSubview(view)
                view.widthAnchor.constraint(equalTo: card.body.widthAnchor).isActive = true
            }
            setAccessibilityLabel(card, accessibility)
        }
        // 无障碍文案写死「累计」会与「按项目/按模型已跟随范围」互相打脸：文案由 Core 按范围派生，
        // 装配时先按当前范围给一份，之后每次渲染再随范围刷新（见 TokenPaneView+Render.swift）
        assemble(card: projectCard, title: "按项目", meta: projectMeta, bar: projectBar, rows: projectRows,
                 accessibility: TokenDistroDimension.projects.cardAccessibility(range: range))
        assemble(card: modelCard, title: "按模型", meta: modelMeta, bar: modelBar, rows: modelRows,
                 accessibility: TokenDistroDimension.models.cardAccessibility(range: range))
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

    /// 页头右侧「实时」圆点着色 + 无障碍标签统一设置
    private func setAccessibilityLabel(_ view: NSView, _ label: String) {
        view.setAccessibilityLabel(label)
        view.setAccessibilityRole(.button)
    }
}
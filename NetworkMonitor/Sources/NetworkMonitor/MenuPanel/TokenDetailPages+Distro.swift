import AppKit
import NetworkMonitorCore

// MARK: - 二级页：缓存 / 按项目 / 按模型

extension TokenDetailPaneView {

    // MARK: 缓存命中

    /// 缓存命中页 —— 每一块都跟随主面板当前范围（今日 / 近 7 天 / 近 30 天）
    ///
    /// 本页曾写死「主数值今日 / 走势与均值固定 30 天 / 逐桶固定今日 24 桶」，用户把主面板
    /// 切到近 7 天后仍是今日 + 30 天的混合数据，反馈「我选择 7 天就只展示 7 天的」。
    /// 现在数值与文案全部由 Core 的 `TokenDerive.cachePage` 按当前范围派生，
    /// 视图只做透传（算式分散在视图里就测不到，且会与主面板悄悄分叉）。
    func buildCache(model: TokenPaneModel) -> [NSView] {
        let page = model.cachePage
        overrideCrumb("/ 缓存命中", meta: page.crumbMeta)

        let ring = TokenRingView()
        ring.update(rate: page.ringFraction, text: page.ringText, accessibility: page.ringAccessibility)
        let ringColumn = twoColumn([
            keyRow("缓存读", page.cacheReadText, color: TokenPaneStyle.cacheInk),
            keyRow("未缓存输入", page.uncachedText),
            keyRow(page.saveRatioLabel, page.saveRatioText),
            keyRow("输出", page.outputText),
        ])
        let ringRow = NSStackView(views: [ring, ringColumn])
        ringRow.orientation = .horizontal
        ringRow.alignment = .centerY
        ringRow.spacing = 8
        ringColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let ringCard = TokenBoxView()
        ringCard.setRows([ringRow])

        let spark = TokenSparkView(height: 44, stroke: TokenPaneStyle.cacheColor,
                                   fill: TokenPaneStyle.cacheColor)
        spark.update(values: page.series, accessibility: page.trendAccessibility,
                    baseline: page.seriesFloor)
        let trendCard = TokenBoxView()
        trendCard.setRows([
            head(page.trendTitle, meta: page.trendMeta),
            spark,
            axisView(page.axisLabels),
        ])

        // 本周期 vs 上一周期：两条横条按两者较大值归一（比值不溢出），
        // 上一周期没数据时不画条、数值给「—」，不拿 0% 冒充「命中率 0」
        let currentRow = compareRow(name: page.currentLabel, text: page.currentRateText,
                                    fraction: page.currentFraction,
                                    color: TokenPaneStyle.cacheColor)
        let previousRow = compareRow(name: page.previousLabel, text: page.previousRateText,
                                     fraction: page.hasPrevious ? page.previousFraction : 0,
                                     color: TokenPaneStyle.ghostColor)
        let compareCard = TokenBoxView()
        compareCard.setRows([
            head(page.compareTitle, meta: page.compareMeta),
            currentRow, previousRow,
        ])

        let statCard = TokenBoxView()
        statCard.setRows([
            twoColumn([
                keyRow(page.currentLabel + "命中", page.currentRateText),
                keyRow(page.previousLabel + "命中", page.previousRateText),
                keyRow(page.deltaLabel, page.deltaText,
                       color: page.hasPrevious ? (page.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk)
                                               : TokenPaneStyle.secondaryText),
                keyRow("样本量", page.sampleText),
            ]),
        ])

        return [hero(page.heroValue, unit: page.heroUnit, sub: page.heroSub),
                ringCard, trendCard, compareCard, statCard,
                note(page.note)]
    }

    // MARK: 按项目

    func buildProjects(model: TokenPaneModel) -> [NSView] {
        // 文案全部来自 Core（TokenDistroCopy），本页只透传，不在这里拼口径字符串
        let copy = model.distroCopy
        overrideCrumb("/ 按项目", meta: copy.projectsCrumbMeta)
        let rows = model.projects
        let bar = TokenStackBarView(height: 8)
        bar.update(shares: rows.map { $0.share },
                   colors: rows.map { TokenPaneStyle.distroColor($0.colorIndex) },
                   accessibility: copy.projectsBarAccessibility,
                   tip: TokenDerive.stackBarTip(rows))
        let barCard = TokenBoxView()
        barCard.setRows([
            bar,
            legend(Array(rows.prefix(3)),
                   colors: rows.prefix(3).map { TokenPaneStyle.distroColor($0.colorIndex) }),
        ])

        let listRows: [NSView] = rows.map { row in
            let line = TokenDistroRowView(height: TokenPaneStyle.distroDetailRowHeight, stacked: false)
            line.update(row: row)
            return line
        }
        let listCard = TokenBoxView()
        if listRows.isEmpty {
            listCard.setRows([keyRow("项目", "暂无数据")])
        } else {
            listCard.setRows([head("项目", meta: "tok · 占比")] + listRows)
        }

        let sessionCard = TokenBoxView()
        sessionCard.setRows([
            twoColumn([
                keyRow("有记录项目", "\(model.projectCount)"),
                keyRow("会话数合计", "\(rows.reduce(0) { $0 + sessionCount($1.sub) })"),
            ]),
        ])

        return [hero("\(model.projectCount)", unit: "个有记录的项目",
                     sub: copy.projectsHeroSub),
                barCard, listCard, sessionCard,
                note(copy.projectsNote)]
    }

    // MARK: 按模型

    func buildModels(model: TokenPaneModel) -> [NSView] {
        let copy = model.distroCopy
        overrideCrumb("/ 按模型", meta: copy.modelsCrumbMeta)
        let rows = model.models
        let bar = TokenStackBarView(height: 8)
        bar.update(shares: rows.map { $0.share },
                   colors: rows.map { TokenPaneStyle.distroColor($0.colorIndex + 1) },
                   accessibility: copy.modelsBarAccessibility,
                   tip: TokenDerive.stackBarTip(rows))
        let barCard = TokenBoxView()
        barCard.setRows([
            bar,
            legend(Array(rows.prefix(3)),
                   colors: rows.prefix(3).map { TokenPaneStyle.distroColor($0.colorIndex + 1) }),
        ])

        let listRows: [NSView] = rows.map { row in
            let line = TokenDistroRowView(height: TokenPaneStyle.distroDetailRowHeight, stacked: false)
            line.update(row: row)
            return line
        }
        let listCard = TokenBoxView()
        if listRows.isEmpty {
            listCard.setRows([keyRow("模型", "暂无数据")])
        } else {
            listCard.setRows([head("模型", meta: "tok · 占比 · provider")] + listRows)
        }

        // 单行放不下「模型名 107.3pt + provider/占比/命中率 227.9pt + 间距」（卡内实宽 278pt），
        // 逐行改堆叠排法：模型名一行、说明一行，两行各自完整（文案仍取 Core 的 row.sub，不改口径）
        let subRows: [NSView] = rows.prefix(3).map { row in
            keyRow(row.name, row.sub, color: TokenPaneStyle.tertiaryText, stacked: true)
        }
        let subCard = TokenBoxView()
        subCard.setRows([head("命中率与 provider", meta: copy.hitCardMeta)] + subRows)

        return [hero("\(model.modelCount)", unit: "个 provider+model",
                     sub: copy.modelsHeroSub),
                barCard, listCard, subCard,
                note(copy.modelsNote)]
    }

    // MARK: 小组件

    /// 图例（色块 + 标题 + 数值）
    ///
    /// 296pt 宽里长模型名必然被截断，全名与 provider 只能靠悬停看到；
    /// 这里直接把同一个分布行的 `row.tip` 挂到对应图例项上，
    /// 不依赖渲染层事后遍历子树补文案（那条路径会漏掉重渲染后的新项）。
    private func legend(_ rows: [TokenDistroRow], colors: [NSColor]) -> NSView {
        let view = TokenLegendRowView()
        view.update(items: rows.enumerated().map { index, row in
            TokenLegendItem(color: colors[safe: index], title: row.name,
                            value: row.amount, tip: row.tip)
        })
        return view
    }

    /// 从「会话 38 · 占 41.2%」这类说明里取会话数
    private func sessionCount(_ text: String) -> Int {
        let digits = text.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}

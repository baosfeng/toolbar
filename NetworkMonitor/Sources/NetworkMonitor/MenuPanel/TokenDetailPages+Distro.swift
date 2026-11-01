import AppKit
import NetworkMonitorCore

// MARK: - 二级页：缓存 / 按项目 / 按模型

extension TokenDetailPaneView {

    // MARK: 缓存命中

    func buildCache(snapshot: HarnessUsageSnapshot) -> [NSView] {
        let today = TokenDerive.sum(TokenDerive.todayBuckets(snapshot))
        let yesterday = TokenDerive.sum(TokenDerive.yesterdayBuckets(snapshot))
        let week = TokenDerive.sum(TokenDerive.dailyBuckets(snapshot, days: 7))
        let monthBuckets = TokenDerive.dailyBuckets(snapshot, days: 30)
        let rates = monthBuckets.map { TokenDerive.hitRate($0) * 100 }
        let rate = TokenDerive.hitRate(today) * 100
        overrideCrumb("/ 缓存命中", meta: "今日")

        let ring = TokenRingView()
        ring.update(rate: TokenDerive.hitRate(today),
                    text: String(format: "%.1f", rate),
                    accessibility: "今日缓存命中率 " + String(format: "%.1f", rate) + "%")
        let ringColumn = twoColumn([
            keyRow("缓存读", TokenFormatting.tokens(today.cache), color: TokenPaneStyle.cacheInk),
            keyRow("未缓存输入", TokenFormatting.tokens(today.uncached)),
            keyRow("节省比例", String(format: "%.1f", rate) + "%"),
            keyRow("输出", TokenFormatting.tokens(today.output)),
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
        spark.update(values: rates, accessibility: "近 30 天缓存命中率走势")
        let trendCard = TokenBoxView()
        trendCard.setRows([
            head("命中率走势 · 固定 30 天",
                 meta: String(format: "%.1f", rates.min() ?? 0) + "% – "
                     + String(format: "%.1f", rates.max() ?? 0) + "%"),
            spark,
        ])

        let bucketRates = TokenDerive.todayBuckets(snapshot).map { TokenDerive.hitRate($0) * 100 }
        let bucketBars = TokenSparkView(height: 36, stroke: TokenPaneStyle.cacheColor)
        bucketBars.update(values: bucketRates, accessibility: "今日逐桶命中率")
        let bucketCard = TokenBoxView()
        bucketCard.setRows([
            head("逐桶命中率 · 今日 24 桶",
                 meta: "高 " + String(format: "%.1f", bucketRates.max() ?? 0) + "% · 低 "
                     + String(format: "%.1f", bucketRates.min() ?? 0) + "%"),
            bucketBars,
            axisView(["0 时", "6 时", "12 时", "18 时", "23 时"]),
        ])

        let averageRate = rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)
        let statCard = TokenBoxView()
        statCard.setRows([
            twoColumn([
                keyRow("今日命中", String(format: "%.1f", rate) + "%"),
                keyRow("昨日命中", String(format: "%.1f", TokenDerive.hitRate(yesterday) * 100) + "%"),
                keyRow("本周命中", String(format: "%.1f", TokenDerive.hitRate(week) * 100) + "%"),
                keyRow("30 天均值", String(format: "%.1f", averageRate) + "%"),
            ]),
        ])

        return [hero(String(format: "%.1f", rate), unit: "% · 今日命中",
                     sub: "缓存读 ÷（缓存读 + 未缓存输入）· 主数值固定「今日」口径，不随主面板范围切换；下面三块各自标口径"),
                ringCard, trendCard, bucketCard, statCard,
                note("口径：命中率只看「缓存读」与「未缓存输入」两项，输出不进分母（输出不可能被缓存）。主数值今日、走势与均值固定 30 天、逐桶命中率跟随主面板范围，不共用同一个数。没有单价表，所以不给金额折算。")]
    }

    // MARK: 按项目

    func buildProjects(model: TokenPaneModel) -> [NSView] {
        overrideCrumb("/ 按项目", meta: "累计口径")
        let rows = model.projects
        let bar = TokenStackBarView(height: 8)
        bar.update(shares: rows.map { $0.share },
                   colors: rows.map { TokenPaneStyle.distroColor($0.colorIndex) },
                   accessibility: "按项目累计占比条")
        let barCard = TokenBoxView()
        barCard.setRows([
            bar,
            legend(rows.prefix(3).map { ($0.name, TokenPaneStyle.distroColor($0.colorIndex), $0.amount) }),
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
                     sub: "累计 tok · 会话数 · 排名 · 项目维度只有累计口径，不能按今日/近 7 天过滤"),
                barCard, listCard, sessionCard,
                note("口径：项目来自会话 cwd 归属，按内容键去重后累计；同一项目的多版本会话文件已合并。要「某项目今天用了多少」需要给索引加项目 × 天的二级聚合——现在没有，所以这里不画走势。")]
    }

    // MARK: 按模型

    func buildModels(model: TokenPaneModel) -> [NSView] {
        overrideCrumb("/ 按模型", meta: "累计口径")
        let rows = model.models
        let bar = TokenStackBarView(height: 8)
        bar.update(shares: rows.map { $0.share },
                   colors: rows.map { TokenPaneStyle.distroColor($0.colorIndex + 1) },
                   accessibility: "按模型累计占比条")
        let barCard = TokenBoxView()
        barCard.setRows([
            bar,
            legend(rows.prefix(3).map { ($0.name, TokenPaneStyle.distroColor($0.colorIndex + 1), $0.amount) }),
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

        let subRows: [NSView] = rows.prefix(3).map { row in
            keyRow(row.name, row.sub)
        }
        let subCard = TokenBoxView()
        subCard.setRows([head("命中率与 provider", meta: "累计")] + subRows)

        return [hero("\(model.modelCount)", unit: "个 provider+model",
                     sub: "provider + model 二元组 · 累计 tok 与命中率"),
                barCard, listCard, subCard,
                note("口径：模型维度同样只有累计口径；命中率按该模型的缓存读 ÷（缓存读 + 未缓存输入）逐模型算。同 provider 不同 model 分行，不合并。")]
    }

    // MARK: 小组件

    private func legend(_ items: [(String, NSColor, String)]) -> NSView {
        let row = TokenLegendRowView()
        row.update(items: items.map { (color: Optional($0.1), title: $0.0, value: $0.2) })
        return row
    }

    /// 从「会话 38 · 占 41.2%」这类说明里取会话数
    private func sessionCount(_ text: String) -> Int {
        let digits = text.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}

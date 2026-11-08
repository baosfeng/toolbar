import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 屏内容构建（屏与二级页共用同一套卡片组件）

/// 共享卡片组件 —— 缓存屏 / 排行屏 / 三个二级页全部从这里取
///
/// 为什么单独抽出来：改前「缓存命中 / 按项目 / 按模型」是二级页里的一套卡片构建，
/// 主面板又自己写了一套环 / 占比条 / 分布行；同一份数据两条渲染路径，口径迟早分叉。
/// 现在组件只在这里定义一次，二级页（TokenDetailPages+Components 转发）与屏共用。
@MainActor
enum TokenContentKit {

    /// 大数字 + 单位 + 副标题（二级页顶部）
    static func hero(_ value: String, unit: String, sub: String) -> NSView {
        let valueLabel = MenuPanelLabel.text(value, font: TokenPaneStyle.heroFont,
                                             color: TokenPaneStyle.secondaryText)
        let unitLabel = MenuPanelLabel.text(unit, font: TokenPaneStyle.heroUnitFont,
                                            color: TokenPaneStyle.tertiaryText)
        let row = NSStackView(views: [valueLabel, unitLabel])
        row.orientation = .horizontal
        row.alignment = .lastBaseline
        row.spacing = 3
        row.setAccessibilityLabel(value + " " + unit)

        let subLabel = MenuPanelLabel.text(sub, font: TokenPaneStyle.noteFont,
                                           color: TokenPaneStyle.tertiaryText)
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 0
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [row, subLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        subLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// 卡头：标题 + 弹簧 + 说明
    static func head(_ title: String, meta: String) -> NSView {
        let head = TokenCardHead(title: title)
        head.update(meta: meta)
        return head
    }

    /// 键值行；stacked = 标题与数值分两行排（标题 + 长说明单行放不下时用）
    static func keyRow(_ title: String, _ value: String,
                       color: NSColor = TokenPaneStyle.secondaryText,
                       stacked: Bool = false) -> NSView {
        let row = TokenKeyRowView(stacked: stacked)
        row.update(title: title, value: value, color: color)
        return row
    }

    static func axisView(_ labels: [String]) -> NSView {
        let axis = TokenAxisView()
        axis.update(labels: labels)
        return axis
    }

    /// 两列键值栅格（按行优先填两列）
    static func twoColumn(_ rows: [NSView]) -> NSView {
        var left: [NSView] = []
        var right: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index % 2 == 0 { left.append(row) } else { right.append(row) }
        }
        func column(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            return stack
        }
        let stack = NSStackView(views: [column(left), column(right)])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    /// 口径说明卡
    static func note(_ text: String) -> NSView {
        let card = TokenBoxView()
        let noteView = TokenNoteView()
        noteView.update(text)
        card.setRows([noteView])
        return card
    }

    /// 对照行（名称 + 横条 + 数值）
    static func compareRow(name: String, text: String, fraction: Double, color: NSColor) -> NSView {
        let row = TokenCompareRowView()
        row.update(name: name, text: text, fraction: fraction, color: color)
        return row
    }

    /// 单桶三段占比（缓存读 / 未缓存 / 输出）
    static func splitShares(_ bucket: TokenBucket) -> [Double] {
        guard bucket.total > 0 else { return [0, 0, 0] }
        return [Double(bucket.cache) / Double(bucket.total),
                Double(bucket.uncached) / Double(bucket.total),
                Double(bucket.output) / Double(bucket.total)]
    }
}

// MARK: - 缓存屏

/// 缓存屏：大命中环 + 四行拆分 / 命中率趋势 / 本周期 vs 上一周期 / 样本统计 + 口径说明
///
/// 块顺序与 TokenScreen.blocks(for: .cache) 一致。每块数值都取自 Core 的 TokenCachePage
/// （同一份派生同时喂给主面板缓存数与 TestRunner），视图不重算比例、不拼口径字符串。
@MainActor
final class TokenCacheScreenView: NSStackView {

    // MARK: 环 + 四行拆分

    private let ringCard = TokenBoxView(spacing: 3)
    private let ringHead = TokenCardHead(title: "缓存命中率")
    private let ring = TokenRingView(size: PaneCardStyle.bigRingSize,
                                     lineWidth: PaneCardStyle.bigRingWidth)
    private let ringRows = (0..<4).map { _ in TokenKeyRowView() }

    // MARK: 命中率趋势

    private let trendCard = TokenBoxView(spacing: 3)
    private let trendHead = TokenCardHead(title: "")
    private let trendSpark = TokenSparkView(height: 46, stroke: TokenPaneStyle.cacheColor,
                                            fill: TokenPaneStyle.cacheColor)
    private let trendAxis = TokenAxisView()

    // MARK: 本周期 vs 上一周期

    private let compareCard = TokenBoxView(spacing: 3)
    private let compareHead = TokenCardHead(title: "")
    private let compareCurrent = TokenCompareRowView()
    private let comparePrevious = TokenCompareRowView()

    // MARK: 样本统计（口径说明是屏页脚，由外框固定屏底）

    private let statsCard = TokenBoxView(spacing: 3)
    private let statRows = (0..<4).map { _ in TokenKeyRowView() }
    private let noteCard = TokenBoxView()
    private let noteView = TokenNoteView()

    /// 屏页脚：口径说明卡（TokenScreenFrameView 把它钉在屏底，不随内容滚动）
    var footerView: NSView { noteCard }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = PaneCardStyle.cardSpacing
        setAccessibilityRole(.group)
        buildCards()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 环在左、四行键值在右；环是 72pt 大环，「缓存读 / 未缓存 / 节省比例 / 输出」逐行给全
    ///
    /// 卡内只放环 + 四行：分母口径与公式已由「样本量」和屏页脚的口径说明给全，
    /// 再挂一行副标题会把屏撑到必须滚动（固定屏高下每 1pt 都要留给数据）。
    private func buildCards() {
        let column = NSStackView(views: ringRows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        for row in ringRows { row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        column.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let ringRow = NSStackView(views: [ring, column])
        ringRow.orientation = .horizontal
        ringRow.alignment = .centerY
        ringRow.spacing = 10

        ringCard.setRows([ringHead, ringRow])

        trendCard.setRows([trendHead, trendSpark, trendAxis])
        compareCard.setRows([compareHead, compareCurrent, comparePrevious])
        statsCard.setRows([TokenContentKit.twoColumn(statRows)])
        noteCard.setRows([noteView])

        for card in [ringCard, trendCard, compareCard, statsCard] {
            addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }

    // MARK: 渲染

    /// 只做「Core 派生值 → 控件」的搬运
    func update(page: TokenCachePage) {
        ringHead.update(title: "缓存命中率", meta: page.rangeTitle + " · " + page.bucketUnitText)
        ring.update(rate: page.ringFraction, text: page.ringText, accessibility: page.ringAccessibility)
        let keys: [(String, String, NSColor)] = [
            ("缓存读", page.cacheReadText, TokenPaneStyle.cacheInk),
            ("未缓存输入", page.uncachedText, TokenPaneStyle.secondaryText),
            (page.saveRatioLabel, page.saveRatioText, TokenPaneStyle.secondaryText),
            ("输出", page.outputText, TokenPaneStyle.secondaryText),
        ]
        for (index, row) in ringRows.enumerated() where index < keys.count {
            row.update(title: keys[index].0, value: keys[index].1, color: keys[index].2)
        }
        trendHead.update(title: page.trendTitle, meta: page.trendMeta)
        // 空缺桶（无会话的小时）给 nil：图在此断开，不连到 0、不落底
        trendSpark.update(points: page.series, accessibility: page.trendAccessibility,
                          baseline: page.seriesFloor)
        trendAxis.update(labels: page.axisLabels)

        // 上一周期没数据时不画条、数值给「—」，不拿 0% 冒充「命中率 0」
        compareHead.update(title: page.compareTitle, meta: page.compareMeta)
        compareCurrent.update(name: page.currentLabel, text: page.currentRateText,
                              fraction: page.currentFraction, color: TokenPaneStyle.cacheColor)
        comparePrevious.update(name: page.previousLabel, text: page.previousRateText,
                               fraction: page.hasPrevious ? page.previousFraction : 0,
                               color: TokenPaneStyle.ghostColor)

        let stats: [(String, String, NSColor)] = [
            (page.currentLabel + "命中", page.currentRateText, TokenPaneStyle.secondaryText),
            (page.previousLabel + "命中", page.previousRateText, TokenPaneStyle.secondaryText),
            (page.deltaLabel, page.deltaText,
             page.hasPrevious ? (page.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk)
                              : TokenPaneStyle.secondaryText),
            ("样本量", page.sampleText, TokenPaneStyle.secondaryText),
        ]
        for (index, row) in statRows.enumerated() where index < stats.count {
            row.update(title: stats[index].0, value: stats[index].1, color: stats[index].2)
        }
        noteView.update(page.note)
        // 副标题（分母口径）从卡面移到读屏文案：卡面留给环与四行，信息不丢
        setAccessibilityLabel("缓存命中屏，" + page.rangeTitle + "命中率 " + page.ringText
            + "。" + page.heroSub)
    }

    /// 键盘可达：缓存屏全是只读卡片，没有可聚焦行（焦点留在屏切换条上）
    var focusableRows: [MenuPanelRow] { [] }
}

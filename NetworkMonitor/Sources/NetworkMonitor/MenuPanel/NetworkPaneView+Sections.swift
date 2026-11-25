import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 网络页区块装配（从 NetworkPaneView.swift 拆出：单文件体积门禁）

/// 网络页各区块的构建与内容填充 — 主文件只保留属性声明、初始化顺序与数据入口
///
/// 拆出理由：五页统一骨架后主文件已过 15 KiB 上限。这里放「怎么搭」，
/// 主文件放「什么时候更新」，两侧通过 internal 成员相接（成员注释已写明放宽原因）。
extension NetworkPaneView {

    // MARK: 区块装配

    /// 速率区：下行一行、上行一行，各占整行宽
    ///
    /// 改前是「下行左列 / 上行右列」两列并排 + 中间弹性 spacer，两条折线各 84pt：
    /// 面板内容宽 296pt 时折线只占最左/最右一小段，中间空出约 200pt
    /// （用户口径「实时线条太短、中间大量空白」）。现在每行 = 文本列（固定宽）+ 折线（吃满剩余），
    /// 宽度口径在 NetworkMonitorUI 的 NetworkHeroLayout，视图只按它给的常量建约束。
    func makeHeroRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            makeSpeedRow(title: "实时下行",
                         value: downValueLabel, unit: downUnitLabel, sparkline: downSparkline),
            makeSpeedRow(title: "上行",
                         value: upValueLabel, unit: upUnitLabel, sparkline: upSparkline),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        // 两行之间不再留间距：两行化本身让 Hero 高了约 13pt（实测面板需求高 511 → 524pt，
        // 超过 520pt 外框上限会出滚动条）。间距 2→0 与文本列内 2→0 合计让回 6pt，
        // 实测落回 518pt；间距改用「标签与数值本来就分开写」的层级来区分，不靠留白
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    /// 单行速率：左侧「分区标签 + 数值 + 单位」文本列（固定宽），右侧折线吃满剩余宽度
    ///
    /// 文本列固定宽而不是自适应：数值每秒刷新（"999 KB/s" ↔ "1.0 MB/s"）宽度会变，
    /// 自适应会让折线左边界每秒跳一次。固定宽取值见 NetworkHeroLayout.textColumnWidth。
    func makeSpeedRow(title: String,
                      value: NSTextField,
                      unit: NSTextField,
                      sparkline: MenuPanelSparklineView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let textColumn = NSStackView(views: [
            MenuPanelLabel.section(title),
            NSStackView(views: [value, unit]),
        ])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        // 标签与数值紧贴（见上方 spacing 的说明：两行化后要省下 6pt 才不顶出 520pt 外框）
        textColumn.spacing = 0
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        // 数值行水平：大数字与单位基线对齐
        (textColumn.arrangedSubviews.last as? NSStackView)?.alignment = .lastBaseline
        (textColumn.arrangedSubviews.last as? NSStackView)?.spacing = 2

        row.addSubview(textColumn)
        row.addSubview(sparkline)
        let minimumWidth = sparkline.widthAnchor.constraint(
            greaterThanOrEqualToConstant: NetworkHeroLayout.minimumSparklineWidth)
        minimumWidth.priority = NSLayoutConstraint.Priority.defaultHigh
        NSLayoutConstraint.activate([
            textColumn.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textColumn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textColumn.widthAnchor.constraint(equalToConstant: NetworkHeroLayout.textColumnWidth),

            sparkline.leadingAnchor.constraint(equalTo: textColumn.trailingAnchor,
                                               constant: NetworkHeroLayout.gap),
            sparkline.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            sparkline.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            // 最小宽度用 750：面板极窄时宁可让文本列被压缩，也不让这条约束和两侧定位打架
            minimumWidth,

            row.heightAnchor.constraint(greaterThanOrEqualTo: textColumn.heightAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualTo: sparkline.heightAnchor),
        ])
        return row
    }

    /// 今日流量卡片：两行数值 + 两条占比轨道
    func makeTodayBox() -> NSView {
        let box = MenuPanelCardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        // 卡片内边距走令牌（原 8/8 是这一页独有的取值，与额度 / Token 的 7/4 对不上）
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor,
                                           constant: MenuPanelCardView.contentInsetX),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                            constant: -MenuPanelCardView.contentInsetX),
            stack.topAnchor.constraint(equalTo: box.topAnchor,
                                       constant: MenuPanelCardView.contentInsetY),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor,
                                          constant: -MenuPanelCardView.contentInsetY),
        ])

        stack.addArrangedSubview(makeTodayRow(title: "今日下行", value: todayDownLabel,
                                              share: todayDownShareLabel))
        stack.addArrangedSubview(downTrack)
        stack.addArrangedSubview(makeTodayRow(title: "今日上行", value: todayUpLabel,
                                              share: todayUpShareLabel))
        stack.addArrangedSubview(upTrack)
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return box
    }

    /// 今日流量单行：标题 + 数值 + 占比说明
    func makeTodayRow(title: String, value: NSTextField, share: NSTextField) -> NSView {
        let row = NSStackView(views: [MenuPanelLabel.section(title), value,
                                      MenuPanelLabel.spacer(), share])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    /// 活跃进程区：表头 + Top5 列表 + 空态
    func makeProcessSection() -> NSView {
        processEmptyLabel.isHidden = false
        // 空态统一 18pt 行高（此前被 NSStackView 拉伸显得偏大）
        processEmptyLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true
        // 榜本身是一个自绘视图：无数据时整块隐藏，空态文案顶上来
        processList.isHidden = true

        let section = NSStackView(views: [processHeader, processList, processEmptyLabel])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4
        for subview in section.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    /// 近 6 日柱状图区
    func makeChartSection() -> NSView {
        let section = NSStackView(views: [chartHeader, barsView])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        for subview in section.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    // MARK: 页脚状态带

    /// 页脚状态带 — 今日总量 / 进程数 / 采样口径
    ///
    /// 与其余四页同为「键 + 值」横排；值取本帧真实数据，缺数据的项直接不出现
    /// （不写 0 冒充读数）。进程条数由 updateProcesses 回填后重新渲染。
    func updateBand(todayRx: UInt64, todayTx: UInt64) {
        let total = todayRx + todayTx
        stateBand.update(items: [
            (key: "今日总量", value: total > 0 ? formatBytesFull(total) : nil),
            (key: "进程", value: processCountText),
            (key: "采样", value: "5s"),
        ])
    }

    /// 图表数值文案（GB/MB 自适应，数字短，不占宽）
    func shortBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fG", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.0fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", value / 1_000)
        default:
            return "\(bytes)"
        }
    }
}

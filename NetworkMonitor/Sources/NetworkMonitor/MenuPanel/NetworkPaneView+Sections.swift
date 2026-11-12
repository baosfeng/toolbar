import AppKit
import NetworkMonitorCore

// MARK: - 网络页区块装配（从 NetworkPaneView.swift 拆出：单文件体积门禁）

/// 网络页各区块的构建与内容填充 — 主文件只保留属性声明、初始化顺序与数据入口
///
/// 拆出理由：五页统一骨架后主文件已过 15 KiB 上限。这里放「怎么搭」，
/// 主文件放「什么时候更新」，两侧通过 internal 成员相接（成员注释已写明放宽原因）。
extension NetworkPaneView {

    // MARK: 区块装配

    /// 速率区：左侧大数字（下行）+ 右侧次数字（上行），各带一条折线
    func makeHeroRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let downColumn = NSStackView()
        downColumn.orientation = .vertical
        downColumn.alignment = .leading
        downColumn.spacing = 2

        downColumn.addArrangedSubview(MenuPanelLabel.section("实时下行"))
        let downValueRow = NSStackView()
        downValueRow.orientation = .horizontal
        downValueRow.alignment = .lastBaseline
        downValueRow.spacing = 2
        downValueRow.addArrangedSubview(downValueLabel)
        downValueRow.addArrangedSubview(downUnitLabel)
        downColumn.addArrangedSubview(downValueRow)
        downColumn.addArrangedSubview(downSparkline)

        let upColumn = NSStackView()
        upColumn.orientation = .vertical
        upColumn.alignment = .trailing
        upColumn.spacing = 2
        upColumn.addArrangedSubview(MenuPanelLabel.section("上行"))
        let upValueRow = NSStackView()
        upValueRow.orientation = .horizontal
        upValueRow.alignment = .lastBaseline
        upValueRow.spacing = 2
        upValueRow.addArrangedSubview(upValueLabel)
        upValueRow.addArrangedSubview(upUnitLabel)
        upColumn.addArrangedSubview(upValueRow)
        upColumn.addArrangedSubview(upSparkline)

        let row = NSStackView(views: [downColumn, MenuPanelLabel.spacer(), upColumn])
        row.orientation = .horizontal
        row.alignment = .bottom
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
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
        processStack.orientation = .vertical
        processStack.alignment = .leading
        processStack.spacing = 0
        processEmptyLabel.isHidden = false
        // 空态统一 18pt 行高（此前被 NSStackView 拉伸显得偏大）
        processEmptyLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let section = NSStackView(views: [processHeader, processStack, processEmptyLabel])
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

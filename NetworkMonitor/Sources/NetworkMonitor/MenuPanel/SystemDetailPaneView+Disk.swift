import AppKit
import NetworkMonitorCore

// MARK: - 磁盘详情页

/// 磁盘详情 — 已用/总量（28pt）+ 已用比例与可用容量 + 容量条 + 读写双列曲线 + IOPS / 繁忙度
///
/// 首屏下沉回这里的是读写速率曲线与 IOPS / 繁忙度明细；「忙」仍走磁盘族石墨（与读同色），
/// 琥珀只给写序列。「卷名」在本机没有采集路径（statfs 只给容量），故不出现该行，
/// 改在脚注里写明「本机未采集」，不留空行。
final class SystemDiskDetailView: NSView {

    private let hero = SystemMetricValueView(fontSize: 28, unitFontSize: 10)
    private let subtitle: NSTextField
    private let capacityCard: SystemDetailCardView
    private let capacityTrack: MenuPanelTrackView
    private let capacityFacts = SystemDetailFactGrid(rows: 4)
    private let ioCard: SystemDetailCardView
    private let ioPair = SystemIORatePairView(height: 34)
    private let factsCard: SystemDetailCardView
    private let facts = SystemDetailFactGrid(rows: 4)
    private let note = SystemDetailNoteView()

    init() {
        let wash = SystemPalette.wash(.disk)
        subtitle = MenuPanelLabel.text("",
                                       font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                       color: SystemPalette.meta)
        capacityCard = SystemDetailCardView(wash: wash)
        capacityTrack = MenuPanelTrackView(fillColor: SystemPalette.disk, height: 8)
        ioCard = SystemDetailCardView(title: "读写速率", meta: "近 60 秒", wash: wash)
        factsCard = SystemDetailCardView(wash: wash)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        capacityCard.addContent(capacityTrack)
        capacityCard.addContent(capacityFacts)
        ioCard.addContent(ioPair)
        factsCard.addContent(facts)
        factsCard.addContent(note)
        note.update("繁忙度 =（Total Time Read + Total Time Write）÷ 采样间隔；"
            + "与字节速率同一次 IOBlockStorageDriver 调用取回。卷名本机未采集（statfs 只给容量）。")

        let stack = NSStackView(views: [hero, subtitle, capacityCard, ioCard, factsCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in [capacityCard, ioCard, factsCard] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("磁盘详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 刷新
    func update(_ context: SystemDetailContext) {
        guard let disk = context.snapshot?.disk, disk.total > 0 else {
            hero.reset(color: SystemPalette.meta)
            subtitle.stringValue = "已用比例 · 容量读数不可得"
            capacityTrack.fraction = 0
            capacityFacts.update(unavailableCapacityFacts(), keyColor: SystemPalette.diskInk)
            ioPair.update(primary: [], secondary: [], primaryText: SystemPaneFormat.placeholder,
                          secondaryText: SystemPaneFormat.placeholder)
            facts.update(unavailableFacts(context.sampleInterval), keyColor: SystemPalette.diskInk)
            return
        }
        let ratio = SystemMetricsFormatting.capacityRatio(used: disk.used, total: disk.total)
        let available = SystemDetailFormatting.availableBytes(used: disk.used, total: disk.total)
        hero.update(value: SystemDetailFormatting.gigabyteValueText(disk.used),
                    color: SystemPalette.diskInk,
                    unit: "GB / " + SystemDetailFormatting.byteCountText(disk.total))
        subtitle.stringValue = "已用 " + SystemDetailFormatting.compactPercentText(ratio)
            + " · 可用 " + SystemDetailFormatting.byteCountText(available)

        capacityTrack.fraction = ratio
        let used = SystemDetailFormatting.byteCountParts(Double(disk.used))
        let free = SystemDetailFormatting.byteCountParts(Double(available))
        let total = SystemDetailFormatting.byteCountParts(Double(disk.total))
        capacityFacts.update([
            .init(label: "已用", value: used.value, unit: used.unit, isKey: true),
            .init(label: "可用", value: free.value, unit: free.unit, isKey: false),
            .init(label: "总量", value: total.value, unit: total.unit, isKey: false),
            .init(label: "繁忙度", value: percentValue(disk.busyFraction), unit: percentUnit(disk.busyFraction),
                  isKey: false),
        ], keyColor: SystemPalette.diskInk)

        ioPair.update(primary: context.diskReadHistory, secondary: context.diskWriteHistory,
                      primaryText: SystemPaneFormat.rate(disk.readBytesPerSecond),
                      secondaryText: SystemPaneFormat.rate(disk.writeBytesPerSecond))

        let sample = SystemDetailPaneView.sampleIntervalParts(context.sampleInterval)
        facts.update([
            .init(label: "读 IOPS", value: iopsValue(disk.readIOPS), unit: disk.readIOPS == nil ? nil : "op/s",
                  isKey: false),
            .init(label: "写 IOPS", value: iopsValue(disk.writeIOPS), unit: disk.writeIOPS == nil ? nil : "op/s",
                  isKey: false),
            .init(label: "繁忙度", value: percentValue(disk.busyFraction),
                  unit: percentUnit(disk.busyFraction), isKey: false),
            .init(label: "采样", value: sample.value, unit: sample.unit, isKey: false),
        ], keyColor: SystemPalette.diskInk)
    }

    /// 百分比数值（nil → 「—」）
    private func percentValue(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return SystemPaneFormat.placeholder }
        return SystemDetailFormatting.percentNumberText(fraction)
    }

    /// 百分比单位（不可得时连单位一起撤，避免「— %」）
    private func percentUnit(_ fraction: Double?) -> String? {
        guard let fraction, fraction.isFinite else { return nil }
        return "%"
    }

    /// IOPS 数值（nil → 「—」）
    private func iopsValue(_ iops: Double?) -> String {
        guard let iops, iops.isFinite else { return SystemPaneFormat.placeholder }
        return String(format: "%.0f", max(0, iops))
    }

    private func unavailableCapacityFacts() -> [SystemDetailFactGrid.Item] {
        [
            .init(label: "已用", value: SystemPaneFormat.placeholder, unit: nil, isKey: true),
            .init(label: "可用", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "总量", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "繁忙度", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
        ]
    }

    private func unavailableFacts(_ sample: Double?) -> [SystemDetailFactGrid.Item] {
        let sampleParts = SystemDetailPaneView.sampleIntervalParts(sample)
        return [
            .init(label: "读 IOPS", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "写 IOPS", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "繁忙度", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "采样", value: sampleParts.value, unit: sampleParts.unit, isKey: false),
        ]
    }
}

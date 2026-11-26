import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 安装进度区

/// 安装进度区 —— 阶段清单 + 下载进度条 + 一行详情
///
/// 形态：整行宽（与「新版本说明」行同构），不用 `SettingsRowView` ——
/// 行是「左标题 + 右控件」的单行结构，进度区要占满宽度并在内部纵向排三块。
///
/// 高度恒定（`SettingsTheme.progressAreaHeight`）：数字位数变化（"9.9 MB" → "10.2 MB"）
/// 不能让整张卡跳高跳低；`idle` 时整块隐藏（`isHidden`，高度不占位）。
final class SettingsAboutProgressRow: NSView {

    private let stepsLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                                 color: SettingsTheme.textSecondary)
    private let percentLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueStrongFont,
                                                   color: SettingsTheme.accent)
    private let detailLabel = MenuPanelLabel.text("", font: SettingsTheme.noteFont,
                                                  color: SettingsTheme.textTertiary)
    private let bar = NSProgressIndicator()
    private let detailRow = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        stepsLabel.translatesAutoresizingMaskIntoConstraints = false
        stepsLabel.maximumNumberOfLines = 0
        stepsLabel.lineBreakMode = .byWordWrapping
        stepsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.alignment = .right
        // 定宽：百分比从 "9%" 到 "100%" 位数变化会推着标签左右挪，视觉上像在抖
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setAccessibilityLabel("下载进度")

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailRow.orientation = .horizontal
        detailRow.alignment = .firstBaseline
        detailRow.spacing = 8
        detailRow.distribution = .fill
        detailRow.translatesAutoresizingMaskIntoConstraints = false
        detailRow.addArrangedSubview(percentLabel)
        detailRow.addArrangedSubview(detailLabel)
        detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [stepsLabel, bar, detailRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor,
                                           constant: SettingsTheme.cardPaddingX),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor,
                                            constant: -SettingsTheme.cardPaddingX),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bar.heightAnchor.constraint(equalToConstant: SettingsTheme.progressBarHeight),
            detailRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            // 下限而不是定值：字号或换行把内容撑高时不该被裁；正常情况下就是 progressAreaHeight
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsTheme.progressAreaHeight),
        ])
        // 读屏按 group 上报：三块是同一件事（进度），逐行念会把阶段清单拆得很碎
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("安装进度")
        // 默认隐藏：首次 update 之前不该占位（idle 态的安装卡只有「安装」一行）
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 按安装状态刷新
    ///
    /// - Parameters:
    ///   - state: 安装状态（含下载进度与失败阶段）
    ///   - subStep: 展开阶段子步骤（安装器上报；nil = 不在展开段）
    func update(state: UpdateInstallState, subStep: UpdateUnpackStep?) {
        let items = UpdateInstallProgressText.steps(stage: state.stage,
                                                    subStep: subStep,
                                                    failedAt: state.failedAt)
        guard !items.isEmpty else {
            isHidden = true
            setAccessibilityValue(nil)
            return
        }
        isHidden = false
        stepsLabel.attributedStringValue = Self.stepsText(items)

        let progress = state.progress
        // 不定态只在「没有分母且还在跑」时用：给假百分比比转圈更糟（用户会拿它算剩余时间）；
        // 失败时既不转圈也不清零 —— 停在失败那一刻的位置，用户才知道下到了多少
        let indeterminate = UpdateInstallProgressText.isIndeterminate(progress) && state.stage != .failed
        bar.isIndeterminate = indeterminate
        if indeterminate {
            bar.startAnimation(nil)
        } else {
            bar.stopAnimation(nil)
            bar.doubleValue = progress?.fraction ?? 0
        }

        percentLabel.stringValue = UpdateInstallProgressText.percentText(progress) ?? ""
        percentLabel.isHidden = percentLabel.stringValue.isEmpty

        var detail = UpdateInstallProgressText.detailText(progress) ?? ""
        if let stepDetail = UpdateInstallProgressText.stepDetail(stage: state.stage, subStep: subStep) {
            detail = detail.isEmpty ? stepDetail : stepDetail + " · " + detail
        }
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty
        setAccessibilityValue(stepsLabel.stringValue
                               + (percentLabel.isHidden ? "" : " " + percentLabel.stringValue)
                               + (detail.isEmpty ? "" : " " + detail))
    }

    // MARK: 私有

    /// 阶段清单压成一行可换行的富文本：完成 ✓ 绿、当前 ▸ 强调、未到 · 三级、失败 ✕ 告警
    ///
    /// 为什么不用 5 行竖排：关于页已经溢出约 290pt，竖排要多占 90pt；
    /// 而这五段是线性流程，横排一行读「在哪一段」反而更快。
    private static func stepsText(_ items: [UpdateInstallStepItem]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ›  ", attributes: [
                    .font: SettingsTheme.noteFont,
                    .foregroundColor: SettingsTheme.ghost,
                ]))
            }
            let mark: String
            let color: NSColor
            switch item.state {
            case .done:
                mark = "✓ "
                color = SettingsTheme.okInk
            case .current:
                mark = "▸ "
                color = SettingsTheme.accent
            case .pending:
                mark = "· "
                color = SettingsTheme.textTertiary
            case .failed:
                mark = "✕ "
                color = SettingsTheme.warnInk
            }
            let font = item.state == .current ? SettingsTheme.rowSubtitleStrongFont
                                              : SettingsTheme.rowSubtitleFont
            result.append(NSAttributedString(string: mark + item.kind.title, attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
        }
        return result
    }

    #if DEBUG
    /// 取证：进度区当前可见文本（离屏快照读不到内嵌 label 的真值）
    var debugProbeText: String {
        "hidden=\(isHidden) steps=\(stepsLabel.stringValue)"
            + " percent=\(percentLabel.isHidden ? "—" : percentLabel.stringValue)"
            + " detail=\(detailLabel.isHidden ? "—" : detailLabel.stringValue)"
            + " bar=\(bar.isIndeterminate ? "indeterminate" : String(format: "%.3f", bar.doubleValue))"
    }
    #endif
}

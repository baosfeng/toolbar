import AppKit
import NetworkMonitorCore

// MARK: - Token 页底部状态行与口径说明（从 TokenRowViews.swift 拆出：单文件体积门禁）
//
// 状态带本身已收敛到五页共用的 `PaneStateBandView`（底 / 高度 / 内边距 / 圆角 / 键值字号
// 全部走 `PaneBandChrome`），本文件只剩 Token 页独有的两件：语气色映射与口径说明段。

// MARK: - 状态带语气色（TokenStateItem.Tone → 四族墨色）

/// 状态带数值的语气色 —— 未缓存 / 缓存 / 请求数各取四族墨色，普通项用次级文字色
///
/// 映射放在视图层：Core 不依赖 AppKit，`NSColor` 只能在 UI 侧解析；
/// 取色与页面其它区块同源（`PaneCardStyle`），不另写一份色值。
extension TokenStateItem {

    @MainActor
    var toneColor: NSColor {
        switch tone {
        case .plain: return PaneCardStyle.secondaryText
        case .accent: return PaneCardStyle.uncachedInk
        case .cache: return PaneCardStyle.cacheInk
        case .request: return PaneCardStyle.requestInk
        }
    }
}

/// 口径说明段（二级页底部 / 缓存屏页脚 / 排行屏卡底）
///
/// - Parameter maxLines: 0 = 不限行数（二级页 / 缓存屏页脚）；N > 0 = 最多 N 行、尾部省略，
///   完整文案挂到悬停与读屏（排行屏卡底要给 3 行：全展开会把 4 行压到 35pt，单行又太省）。
final class TokenNoteView: NSView {

    private let label = MenuPanelLabel.text("", font: TokenPaneStyle.noteFont,
                                            color: TokenPaneStyle.tertiaryText)
    private let truncated: Bool

    init(maxLines: Int = 0) {
        truncated = maxLines > 0
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 多行必须走 byWordWrapping：byTruncatingTail 会让 field 只算一行高（实测只剩一行）
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = max(maxLines, 0)
        label.usesSingleLineMode = maxLines == 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(_ text: String) {
        label.stringValue = text
        // 限行时正文会被省略，完整口径靠悬停与读屏补全
        if truncated {
            label.toolTip = text
            setAccessibilityLabel(text)
        }
    }
}

extension Array {
    /// 越界安全的取下标（图表配色数组与数据长度不一致时不崩）
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

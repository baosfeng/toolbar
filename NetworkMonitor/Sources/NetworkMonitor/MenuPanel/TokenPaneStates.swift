import AppKit
import NetworkMonitorCore

// MARK: - 状态页（加载 / 空 / 数据源不可用）

/// 首轮索引中的加载态 —— 骨架条 + 进度文案（索引完成靠事件刷新，不阻塞面板）
final class TokenLoadingView: NSView {

    private let progressLabel = MenuPanelLabel.text("正在聚合会话日志…", font: TokenPaneStyle.metaFont,
                                                    color: TokenPaneStyle.secondaryText)
    private let hintLabel = MenuPanelLabel.text("首轮索引较慢，完成后自动刷新",
                                                font: TokenPaneStyle.metaFont,
                                                color: TokenPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let heroSkeleton = TokenSkeletonView(height: 64)
        let midSkeleton = TokenSkeletonView(height: 32)
        let lineSkeleton = TokenSkeletonView(height: 12)
        let shortSkeleton = TokenSkeletonView(height: 12)
        let wideSkeleton = TokenSkeletonView(height: 100)
        stack.addArrangedSubview(heroSkeleton)
        stack.addArrangedSubview(midSkeleton)
        stack.addArrangedSubview(lineSkeleton)
        stack.addArrangedSubview(shortSkeleton)
        stack.addArrangedSubview(wideSkeleton)
        // 骨架条本身没有固有宽度：加入排列后再与容器等宽（先加视图再激活，避免无共同祖先）
        for skeleton in [heroSkeleton, midSkeleton, lineSkeleton, wideSkeleton] {
            skeleton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(progressLabel)
        stack.addArrangedSubview(hintLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            shortSkeleton.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.66),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新进度文案（进度未知时显示「正在聚合会话日志…」）
    func update(progress: HarnessIndexProgress?) {
        if let progress, progress.totalFiles > 0 {
            progressLabel.stringValue = "索引中 \(progress.completedFiles)/\(progress.totalFiles) · 已完成 \(progress.parsedSessions) 会话"
        } else {
            progressLabel.stringValue = "正在聚合会话日志…"
        }
    }
}

/// 骨架条
final class TokenSkeletonView: NSView {

    init(height: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }
}

/// 空态 —— 没有任何可统计的会话
final class TokenEmptyView: NSView {

    /// 默认空态文案（索引正常但确实还没有会话）
    private static let defaultTitle = "还没有可统计的会话"
    private static let defaultNote = "运行一次 DSH 会话后，这里会出现 token 消耗。\n数据来自 ~/.dsh/sessions 下的会话日志。"

    /// 「重新扫描」按钮行（键盘可达）
    let retryRow: MenuPanelRow
    private let titleLabel: NSTextField
    private let noteLabel: NSTextField

    init(onRetry: @escaping () -> Void) {
        retryRow = MenuPanelRow(height: 24, onClick: onRetry)
        // 标题与说明在 super.init 之前建好：失败态要复用同一套视图换文案，
        // 而不是再叠一个几乎一样的「失败态」视图
        titleLabel = MenuPanelLabel.text(Self.defaultTitle, font: TokenPaneStyle.stateBodyFont,
                                         color: TokenPaneStyle.secondaryText)
        noteLabel = NSTextField(labelWithString: Self.defaultNote)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        retryRow.contentStack.spacing = 0
        let retryLabel = MenuPanelLabel.text("重新扫描", font: TokenPaneStyle.stateNoteFont,
                                             color: TokenPaneStyle.secondaryText)
        retryLabel.alignment = .center
        retryRow.widthAnchor.constraint(equalToConstant: 96).isActive = true
        retryRow.contentStack.addArrangedSubview(retryLabel)
        retryRow.setAccessibilityLabel("重新扫描 DSH 会话")

        let title = titleLabel
        let note = noteLabel
        note.font = TokenPaneStyle.stateNoteFont
        note.textColor = TokenPaneStyle.tertiaryText
        note.alignment = .center
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 0
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [title, note, retryRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 切换空态文案：`reason` 非空表示「索引失败」而不是「还没有数据」
    ///
    /// 失败态曾经完全落到空态这一支，用户看到「还没有可统计的会话」，
    /// 而真实原因是索引不可用（数据库未就绪 / zstd 缺失 / 扫描抛错），
    /// 界面既不显示原因也没有区分「坏了」与「没数据」。
    func update(reason: String?) {
        guard let reason, !reason.isEmpty else {
            titleLabel.stringValue = Self.defaultTitle
            noteLabel.stringValue = Self.defaultNote
            retryRow.setAccessibilityLabel("重新扫描 DSH 会话")
            return
        }
        titleLabel.stringValue = "Token 索引失败"
        noteLabel.stringValue = reason + "\n可点「重新扫描」重试。"
        retryRow.setAccessibilityLabel("重新扫描 DSH 会话（上次失败：" + reason + "）")
    }
}

/// 数据源不可用态（zstd 缺失 / 会话目录缺失）
final class TokenUnavailableView: NSView {

    private let messageLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let title = MenuPanelLabel.text("Token 统计不可用", font: TokenPaneStyle.stateBodyFont,
                                        color: TokenPaneStyle.secondaryText)
        messageLabel.font = TokenPaneStyle.stateNoteFont
        messageLabel.textColor = TokenPaneStyle.tertiaryText
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [title, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新降级原因
    func update(message: String) {
        messageLabel.stringValue = message
    }
}
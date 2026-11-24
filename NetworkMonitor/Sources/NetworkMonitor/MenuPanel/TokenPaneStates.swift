import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

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
    ///
    /// 不绑定单一来源：七家来源（DSH / Claude Code / Codex / Gemini CLI / Copilot CLI /
    /// OpenCode / Zed）都已接入，只写 DSH 会让另外六家的用户以为这里收不到自己的数据。
    private static let defaultTitle = "还没有可统计的会话"
    private static let defaultNote = "运行一次会话后，这里会出现 token 消耗。\n"
        + "数据来自各来源的会话日志；目录可在「设置 → Token 用量」里指定。"

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
        retryRow.setAccessibilityLabel("重新扫描会话日志")

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
            retryRow.setAccessibilityLabel("重新扫描会话日志")
            return
        }
        titleLabel.stringValue = "Token 索引失败"
        noteLabel.stringValue = reason + "\n可点「重新扫描」重试。"
        retryRow.setAccessibilityLabel("重新扫描会话日志（上次失败：" + reason + "）")
    }
}

/// 数据源不可用态（zstd 缺失 / 会话目录缺失 / 目录不可读）
///
/// 三类问题的处置不同，所以除了原因文案还给一条动作行：
/// - 找不到目录 → 去设置里指定会话目录
/// - 目录不可读 → 去设置里修权限，或改到别的目录
/// - 缺 zstd → 重扫没有意义，只能去设置看清探测链（包内自带 / 绝对路径 / PATH / 登录 shell）
final class TokenUnavailableView: NSView {

    private let titleLabel = MenuPanelLabel.text("Token 统计不可用", font: TokenPaneStyle.stateBodyFont,
                                                 color: TokenPaneStyle.secondaryText)
    private let messageLabel = NSTextField(labelWithString: "")
    /// 动作行（跨文件访问：TokenPaneView 装配时挂 onClick）
    let actionRow: MenuPanelRow
    private let actionLabel: NSTextField

    init() {
        actionRow = MenuPanelRow(height: 24, onClick: {})
        actionLabel = MenuPanelLabel.text("去设置", font: TokenPaneStyle.stateNoteFont,
                                          color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = TokenPaneStyle.stateNoteFont
        messageLabel.textColor = TokenPaneStyle.tertiaryText
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        actionRow.contentStack.spacing = 0
        actionLabel.alignment = .center
        actionRow.widthAnchor.constraint(equalToConstant: 96).isActive = true
        actionRow.contentStack.addArrangedSubview(actionLabel)
        actionRow.setAccessibilityLabel("打开 Token 用量设置")

        let stack = NSStackView(views: [titleLabel, messageLabel, actionRow])
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

    /// 更新降级原因（带诊断时按「哪一类问题」给出标题与可执行动作）
    func update(message: String, diagnostics: HarnessSourceDiagnostics? = nil) {
        messageLabel.stringValue = message
        guard let kind = diagnostics?.failureKind else {
            titleLabel.stringValue = "Token 统计不可用"
            setAction("去设置", accessibility: "打开 Token 用量设置")
            return
        }
        titleLabel.stringValue = kind.title
        switch kind {
        case .directoryMissing:
            setAction("去设置", accessibility: "打开 Token 用量设置，指定会话目录")
        case .directoryUnreadable:
            setAction("去设置", accessibility: "打开 Token 用量设置，检查目录权限或改到别的目录")
        case .zstdMissing:
            // 包里已自带 zstd，走到这里说明「包内自带 + 绝对路径 + PATH + 登录 shell」全落空，
            // 能修的只有设置页：那里能看到探测链与当前目录。动作文案与其余两类对齐。
            setAction("打开设置", accessibility: "打开 Token 用量设置，查看 zstd 探测链与数据目录")
        }
    }

    private func setAction(_ title: String, accessibility: String) {
        actionLabel.stringValue = title
        actionRow.setAccessibilityLabel(accessibility)
    }
}
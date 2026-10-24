import AppKit
import NetworkMonitorCore

// MARK: - Token 页布局装配（TokenPaneView 扩展）

/// 页头与各分区视图装配 —— 从 `TokenPaneView.swift` 拆出（原文件超单文件体积上限）
///
/// 跨文件访问的成员在主页统一放宽为 internal，同模块内无其他调用方。
extension TokenPaneView {

    func buildHeader() {
        let titleLabel = MenuPanelLabel.text("Token 消耗", font: TokenPaneStyle.pageTitleFont)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        let headRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), rangeControl, refreshRow])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 6
        headRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headRow)
        NSLayoutConstraint.activate([
            headRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            headRow.topAnchor.constraint(equalTo: topAnchor),
        ])
        headRow.heightAnchor.constraint(equalToConstant: 22).isActive = true
        // 分区容器挂在页头下方
        contentTopAnchor = headRow.bottomAnchor
    }

    /// 页头下方的内容起点（buildHeader 里赋值为页头底边）
    func buildSections() {
        let hourStack = NSStackView(views: [hourHeader, hourChart, hourAxis, hourLegend])
        hourStack.orientation = .vertical
        hourStack.alignment = .leading
        hourStack.spacing = 4
        pinWidth([hourHeader, hourChart, hourAxis, hourLegend], to: hourStack)

        let miniStack = NSStackView(views: [reuseCard, requestCard])
        miniStack.orientation = .vertical
        miniStack.alignment = .leading
        miniStack.spacing = 6
        pinWidth([reuseCard, requestCard], to: miniStack)

        dataStack.orientation = .vertical
        dataStack.alignment = .leading
        dataStack.spacing = 8
        // 下半部分按「用户新增需求」做成手风琴：默认折叠，标题行摘要可点开
        for section in [trendSection, modelSection, projectSection, totalsSection] {
            section.onToggle = { [weak self] in self?.onContentChanged?() }
        }
        let sections: [NSView] = [hero, hourStack, chips, miniStack,
                                  trendSection, modelSection, projectSection, totalsSection, footer]
        for view in sections { dataStack.addArrangedSubview(view) }
        // 图表类视图没有固有宽度：显式与容器等宽，否则 NSStackView 只会右对齐成内容宽度
        pinWidth(sections, to: dataStack)
        dataStack.isHidden = true
        loadingView.isHidden = true
        emptyView.isHidden = true
        unavailableView.isHidden = true

        let root = NSStackView(views: [indexLabel, dataStack, loadingView, emptyView, unavailableView])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: contentTopAnchor ?? topAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        pinWidth([indexLabel, dataStack, loadingView, emptyView, unavailableView], to: root)
        indexLabel.isHidden = true
    }
}

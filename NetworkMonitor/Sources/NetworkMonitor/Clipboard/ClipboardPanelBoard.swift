import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 新建板弹窗（AppKit 层）

/// 新建板弹窗 —— 面板内就地输入名称 + 选色，不另起窗口
///
/// 放在控制器扩展里而不是协调器里：协调器只管状态机（可单测），弹窗属 AppKit 视图层。
/// 颜色档位与标签行同源（BoardColorPalette），选中的档位只在建板时决定新板的展示色。
extension ClipboardPanelController {

    /// 弹「新建板」输入框；确认后落库并切到新板，取消与失败都不改选中板
    func presentCreateBoardDialog(anchor: NSRect) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        field.placeholderString = "板名称"
        field.setAccessibilityLabel("新板名称")

        let palette = NSSegmentedControl(labels: BoardColorPalette.selectableNames,
                                         trackingMode: .selectOne, target: nil, action: nil)
        palette.selectedSegment = boards.boards.count % BoardColorPalette.selectableCount
        palette.setAccessibilityLabel("板颜色")

        let accessory = NSStackView(views: [field, palette])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.frame = NSRect(x: 0, y: 0, width: 240, height: 56)

        let alert = NSAlert()
        alert.messageText = "新建板"
        alert.informativeText = "板内条目永不过期，也不参与超限清理。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = accessory
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // 色档已在弹窗里可选，但仓储的建板接口不接受 colorIndex（按板数轮转给色），
        // 这里不另开写入口，选中档位留待「改板色」能力落地后再落库。
        boards.createBoard(name: field.stringValue)
        applyFilter(preferredID: nil)
        content.focusSearchField()
    }
}

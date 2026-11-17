import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 板标签的状态机（切板 / 建板 / 按板过滤）

/// 板标签的业务侧 —— 新逻辑单独成文件，控制器只保留三处最小接线
///
/// 选中板只活在这里（内存状态，不落库）：它是「这次看哪块板」的瞬时视图状态，
/// 与「条目属于哪块板」（clipboard_items.board_id）是两回事。
@MainActor
final class ClipboardBoardCoordinator {

    /// 板列表与切板结果变化时回调（视图据此重排标签行）
    var onChange: (([ClipboardBoard], UUID?) -> Void)?
    /// 需要人看见的提示（建板失败 / 建成），控制器接到提示行
    var onHint: ((String) -> Void)?

    /// 板仓储：数据库未就绪或注入缺失时为 nil（此时标签行只有「全部」，不崩、不假装有板）
    private let repository: (any ClipboardBoardRepository)?
    private let logger: LoggingService
    /// 全部板（按展示顺序）
    private(set) var boards: [ClipboardBoard] = []
    /// 当前选中板（nil = 「全部」）
    private(set) var selectedBoardID: UUID?

    init(repository: (any ClipboardBoardRepository)?, logger: LoggingService = AppContext.shared.logger) {
        self.repository = repository
        self.logger = logger
    }

    /// 重读板列表；选中板已被删掉时回落到「全部」
    func reload() {
        boards = repository?.fetchBoards() ?? []
        if let selectedBoardID, !boards.contains(where: { $0.id == selectedBoardID }) {
            self.selectedBoardID = nil
        }
        onChange?(boards, selectedBoardID)
    }

    /// 切板（nil = 全部）：只改选中态，不写库
    func select(_ boardID: UUID?) {
        guard boardID != selectedBoardID else { return }
        selectedBoardID = boardID
        onChange?(boards, boardID)
    }

    /// ⌘← / ⌘→：在「全部 + 各板」里前后环回（口径见 ClipboardBoardCycle）
    func cycle(_ step: Int) {
        select(ClipboardBoardCycle.next(current: selectedBoardID,
                                        boardIDs: boards.map(\.id), step: step))
    }

    /// 当前选中板下的条目（nil = 全部，不过滤）
    func scoped(_ items: [ClipboardItem]) -> [ClipboardItem] {
        guard selectedBoardID != nil else { return items }
        return items.filter {
            ClipboardBoardFilter.matches(itemBoardID: $0.boardID, selected: selectedBoardID)
        }
    }

    // MARK: 新建板

    /// 落库一块新板并切过去（弹窗已由控制器收走名称与颜色档）
    ///
    /// 建板失败给提示行文案、不改选中板；成功先重读列表再切到新板。
    @discardableResult
    func createBoard(name: String) -> ClipboardBoard? {
        guard let board = repository?.createBoard(name: name) else {
            onHint?("新建板失败（数据库未就绪）")
            return nil
        }
        logger.info("剪贴板新建板：\(board.name)")
        boards = repository?.fetchBoards() ?? []
        selectedBoardID = board.id
        onChange?(boards, selectedBoardID)
        onHint?("已新建「\(board.name)」")
        return board
    }
}

// MARK: - 面板接线（视图出口 → 协调器 → 重排）

/// 面板控制器里的板标签接线 —— 动作体都在本文件，控制器只留一行 wireBoardRow() 与两处调用点
extension ClipboardPanelController {

    /// 接上两个出口：点标签切板、点「＋」弹新建板；协调器变化回写视图
    func wireBoardRow() {
        content.onSelectBoard = { [weak self] boardID in
            self?.selectBoard(boardID)
        }
        content.onRequestCreateBoard = { [weak self] anchor in
            self?.presentCreateBoardDialog(anchor: anchor)
        }
        boards.onChange = { [weak self] list, selected in
            self?.content.updateBoards(list, selectedBoardID: selected)
        }
        boards.onHint = { [weak self] text in self?.content.showHint(text) }
    }

    /// 切板 → 重排（选中板变化会触发 onChange 回写视图）
    func selectBoard(_ boardID: UUID?) {
        guard boardID != boards.selectedBoardID else { return }
        boards.select(boardID)
        applyFilter(preferredID: nil)
    }
}

import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 页状态机与二级页入口（TokenPaneView 扩展）

/// 从 TokenPaneView.swift 拆出（主文件贴近单文件 15 KiB 上限）
///
/// 状态判据：数据源不可用 → 索引首轮加载 → 空 → 有数据（失败仍保留已有数据）；
/// 二级页只改显隐与状态，不碰数据，返回时按当前状态重渲染主面板。
extension TokenPaneView {

    // MARK: - 数据更新

    /// 注入一帧快照（数据入口：面板 updateToken 与重扫回执都走这里）
    func update(_ snapshot: HarnessUsageSnapshot) {
        self.snapshot = snapshot
        noteIndexingWindow(for: snapshot)
        // 有内容的一帧直接留档：下一帧若为空（重扫清了索引）就拿它顶住整屏
        if !TokenComparison.isEmpty(snapshot) { retainedSnapshot = snapshot }
        applyStateMachine()
    }

    /// 维护「本轮索引开始时刻」：从非索引 → 索引时记一次，索引结束就清掉
    ///
    /// 延迟显示「索引中 …」按这个时刻算（见 `TokenPaneDisplayPolicy`），
    /// 否则索引一开跑就显形，快速索引时会看到文字闪一下。
    private func noteIndexingWindow(for snapshot: HarnessUsageSnapshot) {
        if snapshot.indexingState.isIndexing {
            if indexingStartedAt == nil { indexingStartedAt = Date() }
        } else {
            indexingStartedAt = nil
        }
    }

    // MARK: - 状态切换

    func applyStateMachine() {
        // 索引把快照推成空帧（重扫先清索引）时，先用上一帧内容顶住：
        // 否则一秒内会经历「内容 → 骨架 → 内容」两次整屏跳变，正是用户说的「闪一下」。
        // 顶住时仍带上新的索引状态，页头照常写「索引中 …」，信息不丢。
        if let current = snapshot,
           TokenPaneDisplayPolicy.prefersRetainedFrame(isEmpty: TokenComparison.isEmpty(current),
                                                       isIndexing: current.indexingState.isIndexing,
                                                       hasRetainedContent: retainedSnapshot != nil),
           let retained = retainedSnapshot {
            snapshot = retained.with(indexingState: current.indexingState)
        }
        // 按来源报状态：未安装 / 目录不可读 / 无会话由收窄后的快照自己给出，
        // 不合并成一句「暂无数据」
        guard let snapshot = scopedSnapshot else { return }
        let available = snapshot.sourceAvailability.isAvailable
        let empty = TokenComparison.isEmpty(snapshot)
        let indexing = snapshot.indexingState.isIndexing
        let progress: HarnessIndexProgress? = {
            if case .indexing(let progress) = snapshot.indexingState { return progress }
            return nil
        }()

        unavailableView.isHidden = available
        guard available else {
            // 带上诊断：不可用态要区分「找不到目录 / 目录不可读 / 缺 zstd」，处置完全不同
            unavailableView.update(message: snapshot.sourceAvailability.displayMessage,
                                   diagnostics: snapshot.sourceDiagnostics)
            hideContentForState()
            onContentChanged?()
            return
        }

        // 首轮索引尚未产出任何数据：显示带进度的加载态，不阻塞面板
        if empty && (indexing || snapshot.indexingState == .idle) {
            loadingView.update(progress: progress)
            loadingView.isHidden = false
            dataStack.isHidden = true
            emptyView.isHidden = true
            // 重扫时索引被清空 → 数据为空 → 落到这一支；临时提示（过程 / 回执）仍要显示，
            // 否则用户点了刷新看不到任何反应（旧实现正是在这里把标签一律收起来）
            if durableNote == nil { clearIndexNote() }
            resetDetail()
            onContentChanged?()
            return
        }

        loadingView.isHidden = true
        dataStack.isHidden = empty
        emptyView.isHidden = !empty
        if empty {
            // 失败态也落到这一支（没有缓存数据时 empty 必然为 true）：
            // 之前它显示的是「还没有可统计的会话」，把「索引坏了」说成「你没数据」
            if case .failed(let message) = snapshot.indexingState {
                emptyView.update(reason: message)
            } else {
                emptyView.update(reason: nil)
            }
            clearIndexNote()
            resetDetail()
            onContentChanged?()
            return
        }
        // 有数据但索引失败：保留数据，同时把失败原因挂到页头 meta 位，不让错误静默
        if case .failed(let message) = snapshot.indexingState {
            setIndexNote("索引失败：\(message)", isWarning: true)
        } else if durableNote != nil {
            // 常驻提示（重扫过程 / 回执）优先：它在下一轮索引开始时才被清掉
            applyDurableNote()
        } else if indexing, let progress,
                  TokenPaneDisplayPolicy.showsIndexNote(isIndexing: indexing,
                                                        startedAt: indexingStartedAt,
                                                        now: Date()) {
            // 延迟 1s 才把会话数改写成进度：快速索引时页头那一格一个字都不该变
            setIndexNote("索引中 \(progress.completedFiles)/\(progress.totalFiles)"
                + " · " + String(progress.linesRead) + " 行", isWarning: false)
        } else {
            clearIndexNote()
        }
        render()
    }

    // MARK: - 二级页

    func openDetail(_ kind: TokenDetailKind, selection: TokenBucketSelection? = nil) {
        guard let snapshot = scopedSnapshot, let model = lastModel else { return }
        self.detailKind = kind
        self.selection = selection
        detailPane.update(kind: kind, model: model, snapshot: snapshot,
                          selection: selection, hourScope: hourScope)
        detailPane.isHidden = false
        dataStack.isHidden = true
        onContentChanged?()
    }

    /// 是否正处在二级页（面板根视图据此把 Esc 解释为「返回」而不是「收起面板」）
    var isShowingDetail: Bool { detailKind != nil }

    func closeDetail() {
        guard detailKind != nil else { return }
        resetDetail()
        dataStack.isHidden = false
        render()
    }

    // MARK: - 内部

    /// 收起主内容（数据源不可用时只留不可用页）
    private func hideContentForState() {
        dataStack.isHidden = true
        loadingView.isHidden = true
        emptyView.isHidden = true
        clearIndexNote()
        resetDetail()
    }

    /// 复位二级页状态并恢复主内容显隐
    private func resetDetail() {
        detailKind = nil
        selection = nil
        detailPane.isHidden = true
    }
}
import AppKit
import NetworkMonitorCore

// MARK: - Token 页状态机与二级页入口（TokenPaneView 扩展）

/// 从 TokenPaneView.swift 拆出（主文件贴近单文件 15 KiB 上限）
///
/// 状态判据：数据源不可用 → 索引首轮加载 → 空 → 有数据（失败仍保留已有数据）；
/// 二级页只改显隐与状态，不碰数据，返回时按当前状态重渲染主面板。
extension TokenPaneView {

    // MARK: - 状态切换

    func applyStateMachine() {
        guard let snapshot else { return }
        let available = snapshot.sourceAvailability.isAvailable
        let empty = TokenComparison.isEmpty(snapshot)
        let indexing = snapshot.indexingState.isIndexing
        let progress: HarnessIndexProgress? = {
            if case .indexing(let progress) = snapshot.indexingState { return progress }
            return nil
        }()

        unavailableView.isHidden = available
        guard available else {
            unavailableView.update(message: snapshot.sourceAvailability.displayMessage)
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
            indexLabel.isHidden = true
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
            indexLabel.isHidden = true
            resetDetail()
            onContentChanged?()
            return
        }
        // 有数据但索引失败：保留数据，同时把失败原因挂到索引标签上，不让错误静默
        if case .failed(let message) = snapshot.indexingState {
            indexLabel.isHidden = false
            indexLabel.stringValue = "索引失败：\(message)"
        } else {
            indexLabel.isHidden = !indexing
            if indexing, let progress {
                indexLabel.stringValue = "索引中 \(progress.completedFiles)/\(progress.totalFiles) · 完成后自动刷新"
            }
        }
        render()
    }

    // MARK: - 二级页

    func openDetail(_ kind: TokenDetailKind, selection: TokenBucketSelection? = nil) {
        guard let snapshot, let model = lastModel else { return }
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
        indexLabel.isHidden = true
        resetDetail()
    }

    /// 复位二级页状态并恢复主内容显隐
    private func resetDetail() {
        detailKind = nil
        selection = nil
        detailPane.isHidden = true
    }
}

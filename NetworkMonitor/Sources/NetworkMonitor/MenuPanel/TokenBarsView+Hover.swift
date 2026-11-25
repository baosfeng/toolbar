import AppKit
import NetworkMonitorCore

// MARK: - 主图悬停通道（从 TokenChartViews.swift 拆出：单文件体积门禁）

/// 柱形 / 折线的悬停：追踪区 + 列命中 + 文案 + 提亮
///
/// 用户原话：「鼠标放上去也没任何的反应，也没提示等信息」。主图改前只有点击通道
/// （点柱开单桶页），悬停完全无反馈；同类图表的额度页直方图（`BillingChartBarsView`）
/// 早就有这一套，这里是补齐而不是新造。
///
/// 分工：**列号与文案都在 Core 的 `TokenHoverTips` 里**（纯函数，TestRunner 直接断言），
/// 本文件只做「鼠标坐标 → 问纯函数 → 挂 toolTip + 重画」三件事。
extension TokenBarsView {

    // MARK: - 追踪区

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    // MARK: - 鼠标

    override func mouseMoved(with event: NSEvent) {
        guard !buckets.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let plot = plotRect
        let index = TokenHoverTips.columnIndex(x: Double(point.x),
                                               plotMinX: Double(plot.minX),
                                               plotWidth: Double(plot.width),
                                               count: buckets.count)
        applyHover(index)
    }

    override func mouseExited(with event: NSEvent) {
        applyHover(nil)
    }

    /// 设悬停列 + 对应 toolTip；列没变就不重画（鼠标在同一列里移动是高频事件）
    ///
    /// 非 `private`：DEBUG 取证入口（`forceHoverForSnapshot`）要用同一个写入口，
    /// 两处各自改状态会出现「截图上亮的是第 2 根、toolTip 写第 3 根」。
    func applyHover(_ index: Int?) {
        let clamped: Int? = index.flatMap { $0 >= 0 && $0 < buckets.count ? $0 : nil }
        guard clamped != hoveredIndex else { return }
        hoveredIndex = clamped
        if let clamped {
            toolTip = TokenHoverTips.bucketTip(buckets[clamped], index: clamped,
                                               count: buckets.count, isHour: isHourBuckets)
        } else {
            toolTip = nil
        }
        needsDisplay = true
    }

    /// 单列坐标（绘制与提亮共用，避免两处各算一套列宽）
    func columnRect(index: Int, gap: CGFloat, columnWidth: CGFloat) -> NSRect {
        let x = plotRect.minX + CGFloat(index) * (columnWidth + gap)
        return NSRect(x: x, y: plotRect.minY, width: columnWidth, height: plotRect.height)
    }
}

#if DEBUG
extension TokenBarsView {

    /// 快照自证（仅 DEBUG）：强制悬停某列，导出该列 toolTip
    ///
    /// 走 `applyHover` 而不是直接写 hoveredIndex：取证要证明的正是
    /// 「鼠标落在这一列时用户看到的那句文案」，绕过写入口就证明不了。
    func forceHoverForSnapshot(_ index: Int?) -> String? {
        hoveredIndex = nil
        applyHover(index)
        return toolTip
    }

    /// 快照自证（仅 DEBUG）：当前列数（取证按「首列 / 中间列 / 末列」逐条导出悬停文案）
    var bucketCountForSnapshot: Int { buckets.count }
}
#endif

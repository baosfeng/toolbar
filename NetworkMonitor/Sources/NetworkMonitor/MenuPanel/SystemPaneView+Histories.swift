import AppKit
import NetworkMonitorCore

// MARK: - 曲线历史注入（拆出主文件）

// 搬移原因：更新入口 + 十二组历史赋值占 ~2.5 KB，主文件同时还要容纳详情页导航，
// 一并放置会越过单文件 15360 字节上限。纯搬移，方法体与原版一致。

extension SystemPaneView {

    /// 注入 CPU 历史（60 点 1 秒采样；空数组 = 清空曲线）
    func updateHistory(_ history: [Double]) {
        updateHistories(cpu: history)
    }

    /// 注入各图表历史 — 未传入的序列保持原样
    ///
    /// CPU 两段必须同时注入才算「双序列」：只给 `cpu` 时面积图退回单序列画法
    /// （叠加层长度不等会被忽略，曲线照常显示，不会错位成假曲线）。
    func updateHistories(cpu: [Double]? = nil,
                         cpuSystem: [Double]? = nil,
                         gpu: [Double]? = nil,
                         memory: [Double]? = nil,
                         memoryWired: [Double]? = nil,
                         memoryActive: [Double]? = nil,
                         memoryCompressed: [Double]? = nil,
                         diskRead: [Double]? = nil,
                         diskWrite: [Double]? = nil,
                         loadShort: [Double]? = nil,
                         loadMedium: [Double]? = nil,
                         loadLong: [Double]? = nil) {
        if let cpu {
            let points = SystemChartDrawing.sanitized(cpu)
            cpuHistory = points
            cpuTile.update(history: points)
            cpuArea.values = points
        }
        if let cpuSystem {
            cpuSystemHistory = SystemChartDrawing.sanitized(cpuSystem)
            cpuArea.overlayValues = cpuSystemHistory
        }
        if let gpu {
            let points = SystemChartDrawing.sanitized(gpu)
            gpuHistory = points
            gpuTile.update(history: points)
            gpuSparkline.values = points
        }
        if let memory {
            memoryHistory = SystemChartDrawing.sanitized(memory)
            memoryTile.update(history: memoryHistory)
        }
        if let memoryWired {
            memoryWiredHistory = SystemChartDrawing.sanitized(memoryWired)
        }
        if let memoryActive {
            memoryActiveHistory = SystemChartDrawing.sanitized(memoryActive)
        }
        if let memoryCompressed {
            memoryCompressedHistory = SystemChartDrawing.sanitized(memoryCompressed)
        }
        if let diskRead {
            diskReadHistory = SystemChartDrawing.sanitized(diskRead)
        }
        if let diskWrite {
            diskWriteHistory = SystemChartDrawing.sanitized(diskWrite)
        }
        if let loadShort {
            loadShortHistory = SystemChartDrawing.sanitized(loadShort)
            loadChart.shortValues = loadShortHistory
        }
        if let loadMedium {
            loadMediumHistory = SystemChartDrawing.sanitized(loadMedium)
            loadChart.mediumValues = loadMediumHistory
        }
        if let loadLong {
            loadLongHistory = SystemChartDrawing.sanitized(loadLong)
            loadChart.longValues = loadLongHistory
        }
        if loadShort != nil || loadMedium != nil || loadLong != nil {
            refreshLoadAxis()
        }
        syncDetailIfNeeded()
    }

    /// 把最近一帧快照与历史推给详情页（只在详情页打开时执行）
    func syncDetailIfNeeded() {
        guard currentDetail != nil else { return }
        detailPane.update(SystemDetailContext(snapshot: lastSnapshot,
                                              sampleInterval: sampleIntervalSeconds,
                                              cpuHistory: cpuHistory,
                                              cpuSystemHistory: cpuSystemHistory,
                                              gpuHistory: gpuHistory,
                                              memoryHistory: memoryHistory,
                                              memoryWiredHistory: memoryWiredHistory,
                                              memoryActiveHistory: memoryActiveHistory,
                                              memoryCompressedHistory: memoryCompressedHistory,
                                              diskReadHistory: diskReadHistory,
                                              diskWriteHistory: diskWriteHistory,
                                              loadShortHistory: loadShortHistory,
                                              loadMediumHistory: loadMediumHistory,
                                              loadLongHistory: loadLongHistory))
    }
}

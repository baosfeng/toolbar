import Foundation
import NetworkMonitorCore

// MARK: - 按天清理 → 重新扫描的自证（人工触发，不参与默认测试流程）
//
// 用法：TestRunner --harness-purge-probe <含 libzstd 的目录> <days>
// 判据：清理删掉的条数与预览一致；重扫后事件数回到总数（证明扫描记录同事务删除，没有假清空）。

/// 收据盒子（并发闭包里回传结果）
private final class PurgeProbeBox: @unchecked Sendable {
    var receipt: HarnessRebuildReceipt?
}

func runHarnessPurgeProbe(resourcesDirectory: String, days: Int) {
    let streamer = HarnessZstdLineStreamer(executableCandidates: ["/nonexistent/zstd"],
                                           searchPath: nil,
                                           bundledDirectory: resourcesDirectory,
                                           loginShellLookup: false,
                                           logger: ConsoleLogger())
    print("purge_availability = " + streamer.availability.displayMessage)
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let scanner = HarnessSessionScanner(streamer: streamer)
    let service = HarnessUsageService(scanner: scanner, store: store, logger: ConsoleLogger())

    func rebuild(scope: HarnessRebuildScope?) -> HarnessRebuildReceipt? {
        let done = DispatchSemaphore(value: 0)
        let box = PurgeProbeBox()
        service.rebuildIndex(scope: scope) { receipt in
            box.receipt = receipt
            done.signal()
        }
        _ = done.wait(timeout: .now() + 600)
        return box.receipt
    }

    print("--- 1. 初次全量索引 ---")
    _ = rebuild(scope: nil)
    let total = store.harnessEventCount()
    print("initial_events = " + String(total))
    print("initial_sessions = " + String(store.harnessScanRecords().count))

    print("--- 2. 按 " + String(days) + " 天清理的预览（二次确认里显示的那个数） ---")
    let preview = store.harnessPurgePreview(scope: .sinceDays(days), now: Date())
    print("purge_preview_events = " + String(preview))

    print("--- 3. 按范围清理 + 重新扫描 ---")
    let receipt = rebuild(scope: .sinceDays(days))
    print("purge_receipt = " + (receipt?.summaryText ?? "<nil>"))
    print("events_deleted = " + String(receipt?.eventsDeleted ?? -1))
    print("events_after_rescan = " + String(store.harnessEventCount()))
    print("sessions_after_rescan = " + String(store.harnessScanRecords().count))

    // 判据：重扫后的事件数必须回到「初值量级」（>= 初值）。
    // 不用严格相等：索引期间 DSH 会话文件仍在追加写入，重扫后的条数只会更多；
    // 而「假清空」的表现是停在 initial - preview 附近（只删不重扫），差一个量级。
    let after = store.harnessEventCount()
    let fakeEmptyThreshold = total - preview
    let restored = after >= total
    print("fake_empty_threshold = " + String(fakeEmptyThreshold))
    print("data_restored_after_rescan = " + String(restored))
    print(restored ? "✅ 按天清理后重新扫描数据完整（无假清空）" : "❌ 清理后数据未完整恢复")
}

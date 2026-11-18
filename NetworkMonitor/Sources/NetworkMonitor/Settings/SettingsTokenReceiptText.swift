import Foundation
import NetworkMonitorCore

// MARK: - 维护回执文案

/// 设置页「维护」行的一行回执文案
///
/// 为什么单独成文件：这一行的可用宽度只有约 360pt，把完整的 `summaryText`
/// （含扫描 / 跳过 / 失败等六段）塞进去会被截成「…跳过」，
/// 而「删了多少 / 索引了多少」才是用户点完清理想看到的两件事。
/// 拆成独立纯函数文件，也顺带避免把 SettingsTokenPane 族顶过门禁基线。
enum SettingsTokenReceiptText {

    /// 一行回执：清理范围与条数 → 索引条数 → 耗时（有失败会话才追加失败数）
    static func compact(_ receipt: HarnessRebuildReceipt) -> String {
        var parts: [String] = []
        if let scope = receipt.scope {
            parts.append("已清理" + scope.displayName + " " + String(receipt.eventsDeleted) + " 条")
        }
        parts.append("索引 " + String(receipt.eventsIndexed) + " 条")
        parts.append(String(format: "耗时 %.1fs", receipt.elapsed))
        if receipt.sessionsFailed > 0 {
            parts.append("失败 " + String(receipt.sessionsFailed) + " 个会话")
        }
        return parts.joined(separator: " · ")
    }
}

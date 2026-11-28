import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 关于页：行值格式 / 版本 / 取证
//
// 从 SettingsAboutPane.swift 拆出（单文件 15 KiB 门禁）；主类只保留卡片装配与状态刷新。
// 跨文件访问的成员在主文件里由 private 放宽为 internal —— 同一类、只是文件不同，
// 放宽范围仍是本模块内，不构成对外 API。

extension SettingsAboutPane {

    // MARK: - 行值格式

    /// 发布时间文案（本地时区，yyyy-MM-dd；nil → "—"，不猜「刚刚」）
    static func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 安装包文案（包名 · 大小 · SHA-256 前 8 位）—— 大小与摘要都来自静态清单
    ///
    /// 摘要只显示前 8 位：整串 64 位在 200pt 宽的行值里会被压成省略号，
    /// 全文挂在 tooltip 上（「校验过的是什么」这类追问再展开）。
    static func packageText(_ package: UpdatePackageTarget) -> String {
        var parts = [package.name]
        if let byteCount = package.byteCount, byteCount > 0 {
            parts.append(ByteFormatting.fullDecimal(UInt64(byteCount)))
        }
        if let sha = package.sha256, sha.count >= 8 {
            parts.append("SHA-256 " + sha.prefix(8) + "…")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 版本

    static var shortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    static var buildVersion: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    // MARK: - 取证
}
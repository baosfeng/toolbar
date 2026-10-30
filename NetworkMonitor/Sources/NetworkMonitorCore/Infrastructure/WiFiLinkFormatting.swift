import Foundation

// MARK: - Wi-Fi 链路展示口径（纯逻辑）
//
// 采样与分档已在 `WiFiLinkCalculations` 定稿；本文件只负责「怎么把快照写成面板上的字」。
// 下沉到 Core 的理由：UI 层只做布局，文本与档位判定要能被 TestRunner 直接断言。
//
// **界面只出现数值 / 单位 / ≤4 字标签**，口径说明一律由 UI 放进 toolTip。
// **nil 不是 0**：Wi-Fi 关闭 / 未连接 / 无接口时快照整体为 nil，此处一律给占位符，
// 绝不产出「0 dBm」或「极佳」这类假读数。

/// Wi-Fi 链路展示口径 — 网络页链路条与系统页状态带共用
public enum WiFiLinkFormatting {

    /// 不可用占位（与系统页 `SystemPaneFormat.placeholder` 同字符）
    public static let placeholder = "—"

    // MARK: 数值

    /// RSSI 文本（含负号，不含单位）
    ///
    /// 用排版减号 U+2212 而非 ASCII 连字符：等宽字体下更窄，且不会与下一个数字粘连；
    /// 与面板既有负数写法（原型 `−65`）一致。
    ///
    /// - Parameter snapshot: nil → "—"；
    /// - 非有限值 / 越界值（> 0 或 < -120）→ "—"（越界说明是脏值，不写出来骗人）。
    public static func rssiText(_ snapshot: WiFiLinkSnapshot?) -> String {
        guard let snapshot else { return placeholder }
        return rssiText(dbm: snapshot.rssiDBm)
    }

    /// RSSI 文本（裸值入口，供状态带 / 测试使用）
    public static func rssiText(dbm: Int) -> String {
        guard WiFiLinkCalculations.isValidRSSI(dbm) else { return placeholder }
        return "−\(abs(dbm))"
    }

    /// 信道与频段合并文本（"ch36 5G" / "ch6 2.4G"）
    ///
    /// 合并成一段的理由：拆成两段要多一个 9pt 间距 + 3pt 间隙，网络页那条只有约 240pt 可用宽。
    /// 信道不可读 → 只给频段；频段未知 → 只给信道；两者都不可读 → "—"。
    public static func channelText(_ snapshot: WiFiLinkSnapshot?) -> String {
        guard let snapshot else { return placeholder }
        let channel = snapshot.channelNumber.map { "ch\($0)" }
        let band = bandText(snapshot.band)
        switch (channel, band) {
        case let (channel?, band?): return channel + " " + band
        case let (channel?, nil): return channel
        case let (nil, band?): return band
        case (nil, nil): return placeholder
        }
    }

    /// 频段短标签（2.4G / 5G / 6G；未知返回 nil，不写「未知」占版面）
    public static func bandText(_ band: WiFiBand) -> String? {
        switch band {
        case .band2GHz: return "2.4G"
        case .band5GHz: return "5G"
        case .band6GHz: return "6G"
        case .unknown: return nil
        }
    }

    /// 协商速率文本（取整到整数 Mbps，与链路条 240pt 宽度对齐）
    ///
    /// 速率是协商速率（PHY 速率），不是实测吞吐；口径写在 toolTip。
    /// nil（不可读 / 非正值）→ "—"；超上限的脏值已由 `WiFiLinkCalculations.transmitRate` 过滤。
    public static func rateText(_ snapshot: WiFiLinkSnapshot?) -> String {
        guard let snapshot, let rate = snapshot.transmitRateMbps else { return placeholder }
        return "\(Int(rate.rounded()))"
    }

    // MARK: 档位

    /// 档位（供 UI 选颜色 / 圆点）
    ///
    /// 直接复用 `WiFiLinkCalculations.signalQuality` 的分档：UI 不另算阈值，
    /// 否则「圆点绿、数字说一般」这种自相矛盾迟早出现。
    public static func quality(_ snapshot: WiFiLinkSnapshot?) -> WiFiSignalQuality {
        guard let snapshot else { return .unknown }
        return snapshot.signalQuality
    }

    // MARK: 降级判定

    /// 是否可展示真实读数（false = 整条走占位形态）
    ///
    /// 两个条件同时成立才算可取：快照存在、且 RSSI 是有效读数。
    /// 快照存在但 RSSI 越界属于脏数据，按不可用处理（宁可显示「—」也不显示假数字）。
    public static func isAvailable(_ snapshot: WiFiLinkSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return WiFiLinkCalculations.isValidRSSI(snapshot.rssiDBm)
    }

    // MARK: 无障碍 / toolTip 拼装

    /// 链路条 toolTip —— 口径说明全部在这里，界面上不出现解释性文字
    ///
    /// - Parameter snapshot: nil 时给出「为什么是 —」的具体原因
    public static func toolTip(_ snapshot: WiFiLinkSnapshot?) -> String {
        guard let snapshot, isAvailable(snapshot) else {
            return "Wi-Fi 链路不可得 · 无 Wi-Fi 接口 / Wi-Fi 已关闭 / 未连接时采样器返回 nil，"
                + "不是 0 dBm，故各项显示「—」"
        }
        var parts = [
            "RSSI \(snapshot.rssiDBm) dBm（CoreWLAN rssiValue，已过滤未连接时的 0 / 正值占位）",
            "档位 \(qualityText(snapshot.signalQuality))（阈值 ≥-50 极佳 / -60 良好 / -70 一般 / -80 偏弱 / 更低很差）"
        ]
        if let noise = snapshot.noiseDBm {
            parts.append("噪声 \(noise) dBm")
        }
        if let snr = snapshot.snrDB {
            parts.append("信噪比 \(snr) dB")
        }
        if let channel = snapshot.channelNumber {
            var channelText = "信道 \(channel)"
            if let band = bandText(snapshot.band) {
                channelText += "（\(band)）"
            }
            if let width = snapshot.channelWidth {
                channelText += " · 带宽 \(width.rawValue) MHz"
            }
            if let frequency = snapshot.centerFrequencyMHz {
                channelText += " · 中心频率 \(frequency) MHz"
            }
            parts.append(channelText)
        }
        if let rate = snapshot.transmitRateMbps {
            parts.append("协商速率 \(Int(rate.rounded())) Mbps（PHY 协商值，非实测吞吐）")
        }
        if snapshot.phyMode != .unknown {
            parts.append("PHY \(snapshot.phyMode.rawValue)")
        }
        parts.append("随系统指标 5 秒慢节拍刷新")
        return parts.joined(separator: "；")
    }

    /// 档位中文（仅用于 toolTip / 无障碍标签，界面上不显示）
    public static func qualityText(_ quality: WiFiSignalQuality) -> String {
        switch quality {
        case .excellent: return "极佳"
        case .good: return "良好"
        case .fair: return "一般"
        case .weak: return "偏弱"
        case .poor: return "很差"
        case .unknown: return "不可判定"
        }
    }

    /// 无障碍标签（VoiceOver 读完整句子，而不是把「−」「65」「dBm」拆开念）
    public static func accessibilityLabel(_ snapshot: WiFiLinkSnapshot?) -> String {
        guard let snapshot, isAvailable(snapshot) else { return "Wi-Fi 链路不可得" }
        var text = "Wi-Fi 信号 \(snapshot.rssiDBm) dBm，档位 \(qualityText(snapshot.signalQuality))"
        if let channel = snapshot.channelNumber, let band = bandText(snapshot.band) {
            text += "，信道 \(channel)，\(band)"
        }
        if let rate = snapshot.transmitRateMbps {
            text += "，协商速率 \(Int(rate.rounded())) Mbps"
        }
        return text
    }
}

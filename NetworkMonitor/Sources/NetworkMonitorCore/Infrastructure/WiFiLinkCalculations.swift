import Foundation

// MARK: - Wi-Fi 链路纯计算（分档 / 信道频率换算 / 占位值过滤）
//
// 采样器落在 NetworkMonitor 目标（CoreWLAN 只能在可执行目标导入），TestRunner 只依赖
// NetworkMonitorCore，因此全部口径下沉到这里：采样器只读原始整数，换算与降级判定在本文件可测。
//
// **为什么处处要过滤占位值**：CoreWLAN 在 Wi-Fi 关闭 / 未连接时不会抛错，而是返回
// 0 / 100 之类的哨兵值（调研 §2.5 实测）。原样展示会变成「信号 0 dBm（极佳）」这类假读数。

public enum WiFiLinkCalculations {

    // MARK: 有效区间

    /// RSSI 合理区间（dBm，含端点）
    ///
    /// 收端灵敏度下限约 -100 dBm，再低的读数已在接收门限之外；上限 -20 dBm 是贴近 AP 的
    /// 合理极值。区间外的值（0 / 100 / 正数）都是 CoreWLAN 未连接时的占位值。
    static let rssiRange = -100 ... -20

    /// 噪声底合理区间（dBm，含端点）
    ///
    /// 本机实测 -96 / -90；占位值 0 与 100 都在区间外被过滤。
    static let noiseRange = -120 ... -20

    /// 5 GHz 的全部标准信道号
    ///
    /// 5 GHz 的信道号不是连续区间（36…64 / 100…144 / 149…177 三段，段间留空，
    /// 且每段内步进 4），用区间判定会把 37 / 38 这类不存在的信道算出一个
    /// 「看起来合理」的频率，故显式列出。
    static let channels5GHz: Set<Int> = {
        var channels = Set<Int>()
        for range in [(36, 64), (100, 144), (149, 177)] {
            for channel in stride(from: range.0, through: range.1, by: 4) {
                channels.insert(channel)
            }
        }
        return channels
    }()

    // MARK: RSSI

    /// RSSI 是否是可用的真实读数
    ///
    /// - 0 与正数：CoreWLAN 未连接时的占位值（实测未连接返回 0）；
    /// - 越界负值（如 -120、-5）：硬件不可能产生的读数，按无效处理。
    public static func isValidRSSI(_ rssi: Int) -> Bool {
        rssiRange.contains(rssi)
    }

    /// 信号质量分档
    ///
    /// 阈值按业界通行的 Wi-Fi 信号分级（dBm）：
    /// ≥ -50 极佳 / -60…-50 良好 / -70…-60 一般 / -80…-70 偏弱 / < -80 很差。
    /// 区间判定直接复用 isValidRSSI，占位值统一得到 unknown，**不会**落进「极佳」。
    public static func signalQuality(rssiDBm: Int) -> WiFiSignalQuality {
        guard isValidRSSI(rssiDBm) else { return .unknown }
        switch rssiDBm {
        case ..<(-80): return .poor
        case (-80) ..< (-70): return .weak
        case (-70) ..< (-60): return .fair
        case (-60) ..< (-50): return .good
        default: return .excellent
        }
    }

    // MARK: 噪声与信噪比

    /// 噪声读数是否有效（过滤 0 / 100 等占位值）
    public static func isValidNoise(_ noise: Int) -> Bool {
        noiseRange.contains(noise)
    }

    /// 信噪比（dB）
    ///
    /// - 任一读数无效 → nil（拿占位值算 SNR 会得出「信噪比 96 dB」这种荒谬结果）；
    /// - 噪声高于或等于信号 → nil：物理上不可信，说明某一路读数是脏值；
    /// - 结果上限 80 dB：超过说明读数异常，不展示。
    public static func snr(rssiDBm: Int, noiseDBm: Int) -> Int? {
        guard isValidRSSI(rssiDBm), isValidNoise(noiseDBm) else { return nil }
        let value = rssiDBm - noiseDBm
        guard value > 0, value <= 80 else { return nil }
        return value
    }

    // MARK: 频段 / 带宽 / PHY（rawValue 映射）

    /// CWChannelBand.rawValue → WiFiBand
    ///
    /// **只做数值映射**：CWChannelBand 的静态成员名在 Swift 3 已废弃（调研 §2.5），
    /// 因此不引用任何 BandUnknown / Band2GHz 之类的废弃标识符。
    /// rawValue 口径：0 未知 / 1 2.4G / 2 5G / 3 6G（实测本机 5GHz 为 2）。
    public static func band(rawValue: Int) -> WiFiBand {
        switch rawValue {
        case 1: return .band2GHz
        case 2: return .band5GHz
        case 3: return .band6GHz
        default: return .unknown
        }
    }

    /// CWChannelWidth.rawValue → WiFiChannelWidth
    ///
    /// rawValue 口径：0 未知 / 1 20MHz / 2 40MHz / 3 80MHz / 4 160MHz。
    /// 实测本机 5 GHz 连 36 信道时 rawValue=1（即 20MHz），而连 149 信道时 rawValue=3
    /// （80MHz）—— 带宽随 AP 协商结果变化，不能当成固定值。
    public static func channelWidth(rawValue: Int) -> WiFiChannelWidth? {
        switch rawValue {
        case 1: return .width20MHz
        case 2: return .width40MHz
        case 3: return .width80MHz
        case 4: return .width160MHz
        default: return nil
        }
    }

    /// CWPHYMode.rawValue → WiFiPHYMode
    ///
    /// rawValue 口径：0 无 / 1 11a / 2 11b / 3 11g / 4 11n / 5 11ac / 6 11ax / 7 11be
    /// （实测本机 phy rawValue=6 → 802.11ax）。
    public static func phyMode(rawValue: Int) -> WiFiPHYMode {
        switch rawValue {
        case 1: return .dot11a
        case 2: return .dot11b
        case 3: return .dot11g
        case 4: return .dot11n
        case 5: return .dot11ac
        case 6: return .dot11ax
        case 7: return .dot11be
        default: return .unknown
        }
    }

    // MARK: 信道频率换算

    /// 信道号 → 中心频率（MHz）
    ///
    /// 三个频段的编号规则互不相同，必须按频段分别换算：
    /// - 2.4 GHz：信道 1…13 → 2407 + 5n（信道 1 = 2412）；信道 14（仅日本）固定 2484；
    /// - 5 GHz：5000 + 5n，但信道号必须命中标准集合（信道 36 = 5180，实测本机 36 → 5180）；
    /// - 6 GHz：信道 1…233 且步进 4 → 5950 + 5n（信道 1 = 5955，与 5G 公式不同，不能复用）。
    ///
    /// 信道号或频段不合法（≤ 0 / 未知频段 / 该频段不存在该信道）→ nil，
    /// 不猜一个看起来合理的频率。
    public static func centerFrequencyMHz(channel: Int, band: WiFiBand) -> Int? {
        guard channel > 0 else { return nil }
        switch band {
        case .band2GHz:
            if channel == 14 { return 2484 }
            guard (1 ... 13).contains(channel) else { return nil }
            return 2407 + 5 * channel
        case .band5GHz:
            guard channels5GHz.contains(channel) else { return nil }
            return 5000 + 5 * channel
        case .band6GHz:
            guard (1 ... 233).contains(channel), (channel - 1) % 4 == 0 else { return nil }
            return 5950 + 5 * channel
        case .unknown:
            return nil
        }
    }

    // MARK: 传输速率

    /// 协商速率是否可用（Mbps）
    ///
    /// - 非有限值 / ≤ 0 → nil：未连接时 transmitRate 返回 0；
    /// - 上限 10000 Mbps：超过 Wi-Fi 7 的理论极值，按脏值丢弃。
    public static func transmitRate(_ rate: Double) -> Double? {
        guard rate.isFinite, rate > 0, rate <= 10000 else { return nil }
        return rate
    }
}

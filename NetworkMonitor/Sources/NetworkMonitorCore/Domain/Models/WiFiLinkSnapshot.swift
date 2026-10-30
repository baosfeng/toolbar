import Foundation

// MARK: - Wi-Fi 链路快照（第二批指标 · 调研 §2.5）
//
// 独立成文件的理由：与负载 / 进程 / 电池同属第二批指标，但语义完全独立（频段 / 信道 /
// PHY 模式），SystemMetricsSnapshot 只持有它的可选字段，互不牵连。
//
// **模型层面不提供 SSID / BSSID**：macOS 11+ 对这两个 API 有定位授权门控，未授权一律
// 返回 nil。为菜单栏 App 弹定位授权体验极差，故不申请权限，模型也不留字段（调研 §2.5）。

/// Wi-Fi 频段
///
/// CoreWLAN 的 `CWChannelBand.BandUnknown` 等静态名在 Swift 3 已废弃，
/// 采样器只用 rawValue 数值映射，本枚举承载映射后的语义（见 WiFiLinkCalculations）。
public enum WiFiBand: String, Sendable {
    /// 2.4 GHz（802.11b/g/n）
    case band2GHz = "2.4GHz"
    /// 5 GHz（802.11a/n/ac/ax）
    case band5GHz = "5GHz"
    /// 6 GHz（Wi-Fi 6E / 7）
    case band6GHz = "6GHz"
    /// 未知（信道不可读，或系统返回未定义的频段值）
    case unknown
}

/// 信道带宽（rawValue 直接用 MHz，便于展示与比较）
public enum WiFiChannelWidth: Int, Sendable {
    /// 20 MHz
    case width20MHz = 20
    /// 40 MHz
    case width40MHz = 40
    /// 80 MHz
    case width80MHz = 80
    /// 160 MHz
    case width160MHz = 160
}

/// PHY 模式（对应 CoreWLAN 的 CWPHYMode rawValue）
public enum WiFiPHYMode: String, Sendable {
    /// 802.11a
    case dot11a = "802.11a"
    /// 802.11b
    case dot11b = "802.11b"
    /// 802.11g
    case dot11g = "802.11g"
    /// 802.11n（Wi-Fi 4）
    case dot11n = "802.11n"
    /// 802.11ac（Wi-Fi 5）
    case dot11ac = "802.11ac"
    /// 802.11ax（Wi-Fi 6 / 6E）
    case dot11ax = "802.11ax"
    /// 802.11be（Wi-Fi 7）
    case dot11be = "802.11be"
    /// 未知（未定义 rawValue 或无可读值）
    case unknown
}

/// 信号质量分档（由 RSSI 换算，阈值见 WiFiLinkCalculations.signalQuality）
public enum WiFiSignalQuality: String, Sendable {
    /// 极佳（≥ -50 dBm）
    case excellent
    /// 良好（-60 … -50 dBm）
    case good
    /// 一般（-70 … -60 dBm）
    case fair
    /// 偏弱（-80 … -70 dBm）
    case weak
    /// 很差（< -80 dBm）
    case poor
    /// 无法判定（RSSI 是占位值 / 越界）
    case unknown
}

/// Wi-Fi 链路采样结果
///
/// 只在「已连接且 RSSI 有效」时产出；Wi-Fi 关闭 / 无接口 / 未连接一律由采样器返回 nil
/// （不是 0、也不是「—」字符串），见 SystemWiFiLinkSampler 的降级分支说明。
///
/// 除 rssiDBm 外全部可选：噪声读不到、信道不可读、速率异常时对应字段为 nil，
/// 不写 0 冒充 —— 0 在这几个字段上都是无意义的占位值。
public struct WiFiLinkSnapshot: Sendable, Equatable {
    /// 信号强度（dBm，负值；已过滤占位值）
    public let rssiDBm: Int
    /// 噪声底（dBm，负值）；读数无效为 nil
    public let noiseDBm: Int?
    /// 信噪比（dB）= rssi - noise；噪声无效或信噪关系不成立时为 nil
    public let snrDB: Int?
    /// 信道号（如 6 / 36 / 149）；不可读为 nil
    public let channelNumber: Int?
    /// 频段
    public let band: WiFiBand
    /// 信道带宽；不可读为 nil
    public let channelWidth: WiFiChannelWidth?
    /// 信道中心频率（MHz）；由信道号 + 频段换算，不可读为 nil
    public let centerFrequencyMHz: Int?
    /// 协商速率（Mbps）；不可读或非正值为 nil
    public let transmitRateMbps: Double?
    /// PHY 模式
    public let phyMode: WiFiPHYMode
    /// 信号质量分档
    public let signalQuality: WiFiSignalQuality

    public init(rssiDBm: Int,
                noiseDBm: Int? = nil,
                snrDB: Int? = nil,
                channelNumber: Int? = nil,
                band: WiFiBand = .unknown,
                channelWidth: WiFiChannelWidth? = nil,
                centerFrequencyMHz: Int? = nil,
                transmitRateMbps: Double? = nil,
                phyMode: WiFiPHYMode = .unknown,
                signalQuality: WiFiSignalQuality = .unknown) {
        self.rssiDBm = rssiDBm
        self.noiseDBm = noiseDBm
        self.snrDB = snrDB
        self.channelNumber = channelNumber
        self.band = band
        self.channelWidth = channelWidth
        self.centerFrequencyMHz = centerFrequencyMHz
        self.transmitRateMbps = transmitRateMbps
        self.phyMode = phyMode
        self.signalQuality = signalQuality
    }
}

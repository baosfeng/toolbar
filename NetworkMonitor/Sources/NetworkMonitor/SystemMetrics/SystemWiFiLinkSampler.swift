import CoreWLAN
import Foundation
import NetworkMonitorCore

// MARK: - Wi-Fi 链路采样

/// Wi-Fi 链路采样 — CoreWLAN（RSSI / 噪声 / 信道 / 速率 / PHY）
///
/// 实测成本（M1 Pro / macOS 27，第二批指标调研 §2.5）：rssi + noise ≈ 2.6 ms，
/// 加上 channel / rate 共 ≈ 3.9 ms，20 次均值 2.65 ms → **必须走 5 秒慢节拍**，
/// 禁止塞进 1 秒档。
///
/// 全部降级分支都**不算采样失败、不产生 failure**（只给一次性 debug 提示），
/// 因为这些都是「本机没有该能力」而不是「采样出错」：
/// 1. 无任何 Wi-Fi 接口（台式机 / 无线网卡被停用）；
/// 2. `powerOn()` 为 false（Wi-Fi 开关关闭）；
/// 3. `serviceActive()` 为 false（接口没有激活任何网络服务）；
/// 4. RSSI 为占位值（未连接时 CoreWLAN 返回 0，实测见调研）。
///
/// **不读 ssid() / bssid()**：macOS 11+ 这两个 API 受定位授权门控，未授权恒返回 nil，
/// 这不是错误（调研 §2.5）。菜单栏 App 弹定位授权体验极差，故不申请权限、也不调用，
/// 模型里本就没有 SSID 字段。
enum SystemWiFiLinkSampler {

    /// 采样一次 Wi-Fi 链路
    ///
    /// - Returns: value 为 nil 表示本机当前没有可展示的 Wi-Fi 链路（上述四个降级分支之一，
    ///   或读取过程中接口消失）；issues 是可记录的降级说明，**不是失败**。
    static func snapshot() -> (value: WiFiLinkSnapshot?, issues: [String]) {
        // 每次采样都重新取 shared client / interface，不在采样器里跨帧缓存 CW 对象：
        // CWInterface 非 Sendable，且接口在运行期可能被拔插或切换，缓存会读到过期接口。
        let client = CWWiFiClient.shared()
        let names = client.interfaceNames() ?? []
        guard !names.isEmpty else {
            return (nil, ["无 Wi-Fi 接口（台式机或无线网卡被停用）"])
        }
        // 默认接口：本机实测只有 en0，多网卡机型也以系统默认接口为准
        guard let wifi = client.interface() else {
            return (nil, ["Wi-Fi 接口列表非空但取不到默认接口（\(names.count) 个）"])
        }
        guard wifi.powerOn() else {
            return (nil, ["Wi-Fi 已关闭，链路指标不可用"])
        }
        guard wifi.serviceActive() else {
            return (nil, ["Wi-Fi 接口未激活网络服务（未连接）"])
        }

        // RSSI 是「是否已连接」的唯一可靠判据：未连接时返回 0 这类占位值
        let rssi = wifi.rssiValue()
        guard WiFiLinkCalculations.isValidRSSI(rssi) else {
            return (nil, ["Wi-Fi 未连接（RSSI = \(rssi) 为占位值或越界）"])
        }

        var issues: [String] = []

        // 噪声：常返回 0 / 100 等占位值，无效就不给（不写 0 冒充）
        let rawNoise = wifi.noiseMeasurement()
        let noise = WiFiLinkCalculations.isValidNoise(rawNoise) ? rawNoise : nil
        if noise == nil {
            issues.append("Wi-Fi 噪声读数无效（\(rawNoise)），按不可用处理")
        }

        // 信道：三要素（号 / 频段 / 带宽）来自同一个 CWChannel 对象，避免口径打架
        var channelNumber: Int?
        var band: WiFiBand = .unknown
        var width: WiFiChannelWidth?
        var centerFrequencyMHz: Int?
        if let channel = wifi.wlanChannel() {
            let number = channel.channelNumber
            // 只做 rawValue 数值映射：CWChannelBand / CWChannelWidth 的静态名 Swift 3 已废弃
            let mappedBand = WiFiLinkCalculations.band(rawValue: channel.channelBand.rawValue)
            channelNumber = number > 0 ? number : nil
            band = mappedBand
            width = WiFiLinkCalculations.channelWidth(rawValue: channel.channelWidth.rawValue)
            centerFrequencyMHz = channelNumber.flatMap {
                WiFiLinkCalculations.centerFrequencyMHz(channel: $0, band: mappedBand)
            }
        } else {
            issues.append("Wi-Fi 信道不可读，频段 / 带宽 / 频率按不可用处理")
        }

        return (WiFiLinkSnapshot(rssiDBm: rssi,
                                 noiseDBm: noise,
                                 snrDB: noise.flatMap { WiFiLinkCalculations.snr(rssiDBm: rssi, noiseDBm: $0) },
                                 channelNumber: channelNumber,
                                 band: band,
                                 channelWidth: width,
                                 centerFrequencyMHz: centerFrequencyMHz,
                                 transmitRateMbps: WiFiLinkCalculations.transmitRate(wifi.transmitRate()),
                                 phyMode: WiFiLinkCalculations.phyMode(rawValue: wifi.activePHYMode().rawValue),
                                 signalQuality: WiFiLinkCalculations.signalQuality(rssiDBm: rssi)),
                issues)
    }
}

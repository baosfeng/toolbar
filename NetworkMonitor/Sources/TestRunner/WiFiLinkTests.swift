import Foundation
import NetworkMonitorCore

// MARK: - Wi-Fi 链路断言（第二批指标 · 调研 §2.5）
//
// 覆盖三层：模型（WiFiLinkSnapshot）、纯计算（WiFiLinkCalculations）与快照字段兼容性。
// 采样器本身依赖 CoreWLAN、且结论随本机联网状态变化，不做运行时断言；
// 其降级判定全部下沉到 WiFiLinkCalculations，这里逐条覆盖正常 / 边界 / 异常三档。
//
// 拆成独立文件的理由：Wi-Fi 与负载 / 进程 / 电池四组指标无共享口径，
// 由 runWiFiLinkTests() 统一调度，main.swift 只加一行注册。

/// Wi-Fi 链路：分档 / 频率换算 / 占位值过滤 / 模型与快照兼容
func runWiFiLinkTests() {
    testWiFiRSSIQuality()
    testWiFiNoiseAndSNR()
    testWiFiChannelMapping()
    testWiFiCenterFrequency()
    testWiFiTransmitRate()
    testWiFiLinkSnapshotModel()
}

// MARK: - RSSI 与信号质量

private func testWiFiRSSIQuality() {
    // 正常：本机实测 -63 / -65 / -66 dBm 都落「一般」档
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -63), .fair, "-63 dBm → 一般")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -65), .fair, "-65 dBm → 一般")

    // 正常：五档全覆盖（阈值取档位端点验证边界归属）
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -40), .excellent, "-40 dBm → 极佳")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -50), .excellent, "-50 含在极佳档")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -51), .good, "-51 → 良好")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -60), .good, "-60 含在良好档")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -61), .fair, "-61 → 一般")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -70), .fair, "-70 含在一般档")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -71), .weak, "-71 → 偏弱")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -80), .weak, "-80 含在偏弱档")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -81), .poor, "-81 → 很差")

    // 边界：有效区间端点
    assertEqual(WiFiLinkCalculations.isValidRSSI(-100), true, "-100 是有效下界")
    assertEqual(WiFiLinkCalculations.isValidRSSI(-20), true, "-20 是有效上界")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -100), .poor, "下界仍属很差档")

    // 异常：占位值与越界值一律 unknown（绝不能落进「极佳」）
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: 0), .unknown,
                "0 dBm 是未连接的占位值 → unknown")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: 100), .unknown, "正值 → unknown")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -5), .unknown, "越界负值 → unknown")
    assertEqual(WiFiLinkCalculations.signalQuality(rssiDBm: -120), .unknown, "低于灵敏度 → unknown")
    assertEqual(WiFiLinkCalculations.isValidRSSI(0), false, "isValidRSSI(0) 为 false")
}

// MARK: - 噪声与信噪比

private func testWiFiNoiseAndSNR() {
    // 正常：本机实测 rssi -63 / noise -96 → SNR 33 dB
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -63, noiseDBm: -96), 33, "-63 - (-96) = 33 dB")
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -65, noiseDBm: -90), 25, "-65 - (-90) = 25 dB")

    // 边界：噪声端点有效
    assertEqual(WiFiLinkCalculations.isValidNoise(-120), true, "-120 是噪声有效下界")
    assertEqual(WiFiLinkCalculations.isValidNoise(-20), true, "-20 是噪声有效上界")

    // 异常：噪声占位值（实测常返回 0 或 100）→ 不给 SNR
    assertEqual(WiFiLinkCalculations.isValidNoise(0), false, "噪声 0 是占位值")
    assertEqual(WiFiLinkCalculations.isValidNoise(100), false, "噪声 100 是占位值")
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -63, noiseDBm: 0), nil, "噪声占位 → SNR nil")
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: 0, noiseDBm: -96), nil, "RSSI 占位 → SNR nil")

    // 异常：噪声高于信号（脏值）→ nil，不出负 SNR
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -90, noiseDBm: -60), nil, "噪声高于信号 → nil")
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -60, noiseDBm: -60), nil, "相等 → nil（不为 0 dB）")

    // 异常：SNR 超过 80 dB 视为读数异常
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -20, noiseDBm: -120), nil,
                "-20 与 -120 相差 100 dB 超过上限 → nil")
    assertEqual(WiFiLinkCalculations.snr(rssiDBm: -40, noiseDBm: -120), 80, "恰好 80 dB 保留")
}

// MARK: - 频段 / 带宽 / PHY 的 rawValue 映射

private func testWiFiChannelMapping() {
    // 正常：本机实测 rawValue 口径（band 2 = 5GHz、width 1 = 20MHz、phy 6 = ax）
    assertEqual(WiFiLinkCalculations.band(rawValue: 2), .band5GHz, "band rawValue 2 = 5GHz")
    assertEqual(WiFiLinkCalculations.band(rawValue: 1), .band2GHz, "band rawValue 1 = 2.4GHz")
    assertEqual(WiFiLinkCalculations.band(rawValue: 3), .band6GHz, "band rawValue 3 = 6GHz")
    assertEqual(WiFiLinkCalculations.channelWidth(rawValue: 1), .width20MHz, "width 1 = 20MHz")
    assertEqual(WiFiLinkCalculations.channelWidth(rawValue: 3), .width80MHz, "width 3 = 80MHz")
    assertEqual(WiFiLinkCalculations.phyMode(rawValue: 6), .dot11ax, "phy 6 = 802.11ax")
    assertEqual(WiFiLinkCalculations.phyMode(rawValue: 5), .dot11ac, "phy 5 = 802.11ac")

    // 边界：全部已知档位
    assertEqual(WiFiLinkCalculations.channelWidth(rawValue: 2), .width40MHz, "width 2 = 40MHz")
    assertEqual(WiFiLinkCalculations.channelWidth(rawValue: 4), .width160MHz, "width 4 = 160MHz")
    assertEqual(WiFiLinkCalculations.phyMode(rawValue: 7), .dot11be, "phy 7 = 802.11be")

    // 异常：未知 rawValue 不猜（width 用 nil，band / phy 用 unknown）
    assertEqual(WiFiLinkCalculations.band(rawValue: 0), .unknown, "band 0 = unknown")
    assertEqual(WiFiLinkCalculations.band(rawValue: 9), .unknown, "未定义 band → unknown")
    assertEqual(WiFiLinkCalculations.channelWidth(rawValue: 0), nil, "width 0 = nil（不是 20MHz）")
    assertEqual(WiFiLinkCalculations.channelWidth(rawValue: 9), nil, "未定义 width → nil")
    assertEqual(WiFiLinkCalculations.phyMode(rawValue: 0), .unknown, "phy 0 = unknown")
    assertEqual(WiFiLinkCalculations.phyMode(rawValue: 42), .unknown, "未定义 phy → unknown")
}

// MARK: - 信道频率换算

private func testWiFiCenterFrequency() {
    // 正常：三个频段的代表信道
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 36, band: .band5GHz), 5180,
                "5G 信道 36 = 5180 MHz（本机实测）")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 149, band: .band5GHz), 5745,
                "5G 信道 149 = 5745 MHz（调研记录）")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 1, band: .band2GHz), 2412,
                "2.4G 信道 1 = 2412 MHz")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 6, band: .band2GHz), 2437,
                "2.4G 信道 6 = 2437 MHz")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 14, band: .band2GHz), 2484,
                "2.4G 信道 14 = 2484 MHz（日本特例）")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 1, band: .band6GHz), 5955,
                "6G 信道 1 = 5955 MHz（与 5G 公式不同）")

    // 边界：各频段的有效端点
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 13, band: .band2GHz), 2472,
                "2.4G 上界信道 13")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 64, band: .band5GHz), 5320,
                "5G 首段末信道 64")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 100, band: .band5GHz), 5500,
                "5G DFS 段起始信道 100")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 165, band: .band5GHz), 5825,
                "5G 149…165 段末信道")

    // 异常：频段不存在该信道 → nil，不猜频率
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 37, band: .band5GHz), nil,
                "5G 不存在信道 37（段内步进 4）→ nil")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 65, band: .band5GHz), nil,
                "5G 段间空档 65 → nil")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 15, band: .band2GHz), nil,
                "2.4G 无信道 15 → nil")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 2, band: .band6GHz), nil,
                "6G 步进 4，信道 2 不存在 → nil")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 0, band: .band5GHz), nil,
                "信道 0 非法 → nil")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: -36, band: .band5GHz), nil,
                "负信道号 → nil")
    assertEqual(WiFiLinkCalculations.centerFrequencyMHz(channel: 36, band: .unknown), nil,
                "未知频段不猜频率 → nil")
}

// MARK: - 传输速率

private func testWiFiTransmitRate() {
    // 正常：本机实测 103.0 / 144.0 Mbps
    assertEqual(WiFiLinkCalculations.transmitRate(103.0), 103.0, "103 Mbps 保留")
    assertEqual(WiFiLinkCalculations.transmitRate(144.0), 144.0, "144 Mbps 保留")

    // 边界：极小正值仍算有效
    assertEqual(WiFiLinkCalculations.transmitRate(0.5), 0.5, "0.5 Mbps 是有效读数")
    assertEqual(WiFiLinkCalculations.transmitRate(10000), 10000, "上限 10000 Mbps 保留")

    // 异常：未连接时为 0 / 非有限 / 越界 → nil，不写 0 冒充
    assertEqual(WiFiLinkCalculations.transmitRate(0), nil, "0 Mbps 视为未连接")
    assertEqual(WiFiLinkCalculations.transmitRate(-1), nil, "负速率 → nil")
    assertEqual(WiFiLinkCalculations.transmitRate(.nan), nil, "NaN → nil")
    assertEqual(WiFiLinkCalculations.transmitRate(.infinity), nil, "无穷 → nil")
    assertEqual(WiFiLinkCalculations.transmitRate(12000), nil, "超过 Wi-Fi 7 极值 → nil")
}

// MARK: - 模型与快照兼容性

private func testWiFiLinkSnapshotModel() {
    let full = WiFiLinkSnapshot(rssiDBm: -63,
                                noiseDBm: -96,
                                snrDB: 33,
                                channelNumber: 36,
                                band: .band5GHz,
                                channelWidth: .width20MHz,
                                centerFrequencyMHz: 5180,
                                transmitRateMbps: 103,
                                phyMode: .dot11ax,
                                signalQuality: .fair)
    assertEqual(full.rssiDBm, -63, "RSSI 保留")
    assertEqual(full.snrDB, 33, "SNR 保留")
    assertEqual(full.band, .band5GHz, "频段保留")
    assertEqual(full.channelWidth, .width20MHz, "带宽保留")
    assertEqual(full.centerFrequencyMHz, 5180, "中心频率保留")
    assertEqual(full.transmitRateMbps, 103, "协商速率保留")
    assertEqual(full.phyMode, .dot11ax, "PHY 模式保留")
    assertEqual(full.signalQuality, .fair, "质量分档保留")

    // 边界：只有 RSSI 也能构造（噪声 / 信道 / 速率全不可读）
    let minimal = WiFiLinkSnapshot(rssiDBm: -70)
    assertEqual(minimal.noiseDBm, nil, "缺省噪声为 nil")
    assertEqual(minimal.snrDB, nil, "缺省 SNR 为 nil")
    assertEqual(minimal.channelNumber, nil, "缺省信道为 nil")
    assertEqual(minimal.band, .unknown, "缺省频段 unknown（不猜成 2.4G）")
    assertEqual(minimal.channelWidth, nil, "缺省带宽为 nil")
    assertEqual(minimal.transmitRateMbps, nil, "缺省速率为 nil")
    assertEqual(minimal.phyMode, .unknown, "缺省 PHY 为 unknown")

    // 边界：新字段参与 Equatable（UI 靠比较判重）
    let other = WiFiLinkSnapshot(rssiDBm: -80, noiseDBm: -96, snrDB: 16,
                                 channelNumber: 36, band: .band5GHz,
                                 channelWidth: .width20MHz, centerFrequencyMHz: 5180,
                                 transmitRateMbps: 103, phyMode: .dot11ax,
                                 signalQuality: .weak)
    assertEqual(full == other, false, "RSSI 不同即快照不等")

    // 边界：快照字段默认 nil，不破坏旧调用点
    let legacy = SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: 1))
    assertEqual(legacy.wifi, nil, "旧调用点 wifi 缺省为 nil")
    let withWiFi = SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: 1), wifi: full)
    assertEqual(withWiFi.wifi, full, "wifi 字段写进快照")

    // 异常：有 wifi 与无 wifi 的快照必须不等（否则面板不会刷新）
    assertEqual(legacy == withWiFi, false, "wifi 存在与否影响相等性")
}

import Foundation
import NetworkMonitorCore

// MARK: - Wi-Fi 链路展示口径断言（格式化纯函数）
//
// 与 WiFiLinkTests.swift 分文件的理由：那份守的是**采样口径**（分档 / 频率换算 / 占位值过滤），
// 这份守的是**展示口径**（怎么写进面板的那一行字），两者改动的触发条件不同，
// 合在一起会把单文件推过 15 KiB 上限。
//
// 重点守一条纪律：**快照为 nil 时绝不能产出 0 dBm 或「极佳」**——
// 采样器在 Wi-Fi 关闭 / 未连接 / 无接口时返回 nil（不是 0），UI 一旦把它写成数字，
// 屏幕上就会出现「信号 0 dBm（极佳）」这种假读数（调研 §2.5 实测的坑）。

/// Wi-Fi 链路展示口径：正常 / 边界 / 降级三档
func runWiFiLinkFormattingTests() {
    testWiFiLinkTexts()
    testWiFiLinkDegradation()
    testWiFiLinkToolTipAndA11y()
}

// MARK: - 文本拼装

private func testWiFiLinkTexts() {
    let full = WiFiLinkSnapshot(rssiDBm: -65,
                                noiseDBm: -96,
                                snrDB: 31,
                                channelNumber: 36,
                                band: .band5GHz,
                                channelWidth: .width20MHz,
                                centerFrequencyMHz: 5180,
                                transmitRateMbps: 103,
                                phyMode: .dot11ax,
                                signalQuality: .fair)

    // 正常：四项文本与档位
    assertEqual(WiFiLinkFormatting.rssiText(full), "−65", "RSSI 输出排版减号 + 绝对值")
    assertEqual(WiFiLinkFormatting.channelText(full), "ch36 5G", "信道与频段合并成一段")
    assertEqual(WiFiLinkFormatting.rateText(full), "103", "速率取整到整数 Mbps")
    assertEqual(WiFiLinkFormatting.quality(full), .fair, "-65 dBm → 一般档")
    assertEqual(WiFiLinkFormatting.isAvailable(full), true, "有效快照可取")

    // 边界：有效区间端点（排版减号不能把 −100 写成 −10 或 100）
    assertEqual(WiFiLinkFormatting.rssiText(dbm: -100), "−100", "-100 是有效下界")
    assertEqual(WiFiLinkFormatting.rssiText(dbm: -20), "−20", "-20 是有效上界")

    // 局部降级：只有频段 / 只有信道 / 都没有
    let bandOnly = WiFiLinkSnapshot(rssiDBm: -60, band: .band2GHz, signalQuality: .good)
    assertEqual(WiFiLinkFormatting.channelText(bandOnly), "2.4G", "无信道号时只给频段")
    let channelOnly = WiFiLinkSnapshot(rssiDBm: -60, channelNumber: 6, band: .unknown,
                                       signalQuality: .good)
    assertEqual(WiFiLinkFormatting.channelText(channelOnly), "ch6", "频段未知时只给信道")
    let neither = WiFiLinkSnapshot(rssiDBm: -60, signalQuality: .good)
    assertEqual(WiFiLinkFormatting.channelText(neither), "—", "信道与频段都不可读 → 「—」")
    assertEqual(WiFiLinkFormatting.rateText(neither), "—", "无速率 → 「—」")

    // 频段短标签：未知不写「未知」占版面
    assertEqual(WiFiLinkFormatting.bandText(.band2GHz), "2.4G", "2.4G 短标签")
    assertEqual(WiFiLinkFormatting.bandText(.band5GHz), "5G", "5G 短标签")
    assertEqual(WiFiLinkFormatting.bandText(.band6GHz), "6G", "6G 短标签")
    assertEqual(WiFiLinkFormatting.bandText(.unknown), nil, "未知频段返回 nil")
}

// MARK: - 降级（核心）

private func testWiFiLinkDegradation() {
    // 核心断言：nil 一律「—」，绝不 0 dBm / 极佳
    assertEqual(WiFiLinkFormatting.rssiText(nil as WiFiLinkSnapshot?), "—", "nil → 「—」")
    assertEqual(WiFiLinkFormatting.channelText(nil), "—", "nil 信道 → 「—」")
    assertEqual(WiFiLinkFormatting.rateText(nil), "—", "nil 速率 → 「—」")
    assertEqual(WiFiLinkFormatting.quality(nil), .unknown, "nil 档位 → unknown（不是 excellent）")
    assertEqual(WiFiLinkFormatting.isAvailable(nil), false, "nil 不可取")

    // 异常：快照存在但 RSSI 是占位值（未连接时 CoreWLAN 返回 0）→ 仍按不可用处理
    let placeholder = WiFiLinkSnapshot(rssiDBm: 0, signalQuality: .unknown)
    assertEqual(WiFiLinkFormatting.rssiText(placeholder), "—", "占位 RSSI 0 → 「—」")
    assertEqual(WiFiLinkFormatting.isAvailable(placeholder), false, "占位 RSSI 不可取")
    assertEqual(WiFiLinkFormatting.rssiText(dbm: 0), "—", "裸值 0 → 「—」")
    assertEqual(WiFiLinkFormatting.rssiText(dbm: 100), "—", "正值占位 → 「—」")
    assertEqual(WiFiLinkFormatting.rssiText(dbm: -120), "—", "低于灵敏度 → 「—」")

    // 档位文案（只进 toolTip / 无障碍，不进界面）
    assertEqual(WiFiLinkFormatting.qualityText(.excellent), "极佳", "极佳文案")
    assertEqual(WiFiLinkFormatting.qualityText(.unknown), "不可判定", "未知档文案")
}

// MARK: - toolTip / 无障碍

private func testWiFiLinkToolTipAndA11y() {
    // nil 的说明必须点名「不是 0 dBm」：这条文案就是把降级口径讲清楚的地方
    let nilTip = WiFiLinkFormatting.toolTip(nil)
    assertEqual(nilTip.contains("不是 0 dBm"), true, "nil toolTip 要写明「不是 0 dBm」")
    assertEqual(nilTip.contains("—"), true, "nil toolTip 要说明显示「—」")

    let full = WiFiLinkSnapshot(rssiDBm: -65,
                                noiseDBm: -96,
                                snrDB: 31,
                                channelNumber: 36,
                                band: .band5GHz,
                                channelWidth: .width20MHz,
                                centerFrequencyMHz: 5180,
                                transmitRateMbps: 103,
                                phyMode: .dot11ax,
                                signalQuality: .fair)
    let tip = WiFiLinkFormatting.toolTip(full)
    assertEqual(tip.contains("−65".replacingOccurrences(of: "−", with: "-")), true,
                "toolTip 带 RSSI 原值")
    assertEqual(tip.contains("建议"), false, "toolTip 里不出现建议性话术")
    assertEqual(tip.contains("非实测吞吐"), true, "速率要标明是协商值不是吞吐")

    // 无障碍：整套读成一句，不把「−」「65」「dBm」拆开念
    assertEqual(WiFiLinkFormatting.accessibilityLabel(nil), "Wi-Fi 链路不可得", "nil 无障碍标签")
    let label = WiFiLinkFormatting.accessibilityLabel(full)
    assertEqual(label.contains("-65 dBm"), true, "无障碍标签带原值")
    assertEqual(label.contains("一般"), true, "无障碍标签带档位中文")
}

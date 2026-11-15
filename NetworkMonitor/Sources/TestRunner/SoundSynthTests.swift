import Foundation
import NetworkMonitorCore

// MARK: - 内建音合成测试

/// 覆盖 CueSoundSynth 的确定性 / 时长 / 峰值 / 首尾归零 / 各 cue 互不相同，
/// 以及 AiffFile 容器头的关键字段（采样率、位深、声道数、帧数）。
///
/// 断言口径对着需求写：用户要的是「清脆的咔嚓」，可量化的部分就是
/// 「短、响度适中、两头不能有爆音」，这三条正好能用字节与采样值守住。
func runCueSoundSynthTests() {
    print("\n🧪 Testing 内建音合成（确定性 / 时长 / 峰值 / 首尾归零）...")
    testSynthIsDeterministic()
    testSynthDurationAndPeak()
    testSynthEdgesAreSilent()
    testSynthFamiliesDiffer()
    testAiffContainer()
}

// MARK: - 确定性

func testSynthIsDeterministic() {
    for cue in NotificationCue.allCases {
        let first = CueSoundSynth.pcm(for: cue)
        let second = CueSoundSynth.pcm(for: cue)
        assertEqual(first == second, true, "同 cue 连跑两次 PCM 完全一致：\(cue.rawValue)")
        assertEqual(CueSoundSynth.aiffData(for: cue) == CueSoundSynth.aiffData(for: cue), true,
                    "同 cue 连跑两次 AIFF 字节完全一致：\(cue.rawValue)")
    }
    // 版本号是缓存判据的一半，必须有值且与文件主名稳定
    assertEqual(CueSoundSynth.version.isEmpty, false, "配方版本非空")
    assertEqual(CueSoundSynth.fileStem(for: .copy), "cue-copy", "文件主名按 cue 命名")
}

// MARK: - 时长与峰值

func testSynthDurationAndPeak() {
    assertEqual(CueSoundSynth.sampleRate, 44_100, "采样率 44.1kHz")
    for cue in NotificationCue.allCases {
        let pcm = CueSoundSynth.pcm(for: cue)
        assertEqual(pcm.isEmpty, false, "每个 cue 都有非空 PCM：\(cue.rawValue)")

        // 操作反馈音必须短：最长的「低沉两段」也压在 200ms 以内
        let seconds = Double(pcm.count) / CueSoundSynth.sampleRate
        assertEqual(seconds > 0.02 && seconds <= 0.20, true,
                    "\(cue.rawValue) 时长 \(String(format: "%.4f", seconds))s 落在 20–200ms")

        // 峰值：归一化到 0.5，既不会削顶也不会小到听不见
        let peak = pcm.reduce(0) { max($0, abs(Int($1))) }
        let ratio = Double(peak) / 32_767
        assertEqual(ratio <= 1.0, true, "\(cue.rawValue) 峰值 \(ratio) ≤ 1.0（不削顶）")
        assertEqual(ratio >= 0.3, true, "\(cue.rawValue) 峰值 \(ratio) ≥ 0.3（听得见）")
    }
    // 复制是「咔嚓」里最短的那一档：需求给的硬指标 ≤ 45ms
    let copySeconds = Double(CueSoundSynth.pcm(for: .copy).count) / CueSoundSynth.sampleRate
    assertEqual(copySeconds <= 0.045, true,
                "复制总长 \(String(format: "%.4f", copySeconds))s ≤ 45ms（机械键咔嚓的体感上限）")
}

// MARK: - 首尾归零

func testSynthEdgesAreSilent() {
    for cue in NotificationCue.allCases {
        let pcm = CueSoundSynth.pcm(for: cue)
        assertEqual(pcm.first, 0, "\(cue.rawValue) 首个采样为 0（起音不爆）")
        assertEqual(pcm.last, 0, "\(cue.rawValue) 末个采样为 0（结尾不咔嗒）")
        // 起音 ≤ 3ms：前 3ms 内的振幅必须已经离开 0 且没冲到峰值——
        // 判据取「前 3ms 的最大绝对样本 ≥ 峰值的 10%」，冲太快就是爆音
        let attackFrames = Int(0.003 * CueSoundSynth.sampleRate)
        let head = pcm.prefix(attackFrames).reduce(0) { max($0, abs(Int($1))) }
        let peak = pcm.reduce(0) { max($0, abs(Int($1))) }
        assertEqual(Double(head) / Double(peak) >= 0.1, true,
                    "\(cue.rawValue) 前 3ms 已起音（不是静音头）")
        // 结尾 8ms 淡出：最后 4ms 的振幅必须明显低于峰值
        let tailFrames = Int(0.004 * CueSoundSynth.sampleRate)
        let tail = pcm.suffix(tailFrames).reduce(0) { max($0, abs(Int($1))) }
        assertEqual(Double(tail) / Double(peak) <= 0.15, true,
                    "\(cue.rawValue) 末 4ms 已收到峰值 15% 以内")
    }
}

// MARK: - 性格差异

func testSynthFamiliesDiffer() {
    // 复制与粘贴必须是两种声音：用户抱怨的正是「复制粘贴一个味儿」
    assertEqual(CueSoundSynth.pcm(for: .copy) == CueSoundSynth.pcm(for: .paste), false,
                "复制与粘贴不是同一个声音")
    // 同族共用配方：截图与复制同属「咔嚓」
    assertEqual(CueSoundSynth.pcm(for: .copy) == CueSoundSynth.pcm(for: .snipCapture), true,
                "截图与复制同族（都是做完一件事的咔嚓）")
    assertEqual(NotificationCue.copy.builtInFamily, .crisp, "复制是清脆族")
    assertEqual(NotificationCue.paste.builtInFamily, .thud, "粘贴是钝咔族")
    assertEqual(NotificationCue.pin.builtInFamily, .chime, "收藏是清亮双击族")
    assertEqual(NotificationCue.delete.builtInFamily, .swipe, "删除是下行唰族")
    assertEqual(NotificationCue.error.builtInFamily, .alert, "失败是低沉族")
    assertEqual(NotificationCue.billingAlert.builtInFamily, .alert, "额度提醒沿用失败的低沉性格")
    assertEqual(NotificationCue.billingRecovery.builtInFamily, .chime, "额度回升沿用好消息的清亮性格")
    assertEqual(Set(NotificationCue.allCases.map { CueSoundSynth.pcm(for: $0) }).count,
                CueSoundFamily.allCases.count,
                "十一个 cue 恰好收敛成五族声音")
}

// MARK: - 容器

func testAiffContainer() {
    let pcm = CueSoundSynth.pcm(for: .copy)
    let data = CueSoundSynth.aiffData(for: .copy)
    assertEqual(String(decoding: data.prefix(4), as: UTF8.self), "FORM", "文件头是 FORM")
    assertEqual(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self), "AIFF", "格式标识是 AIFF")
    // COMM 块紧跟在 FORM 头之后：单声道 / 16-bit / 帧数与 PCM 长度一致
    assertEqual(String(decoding: data.dropFirst(12).prefix(4), as: UTF8.self), "COMM", "第三个块是 COMM")
    let channels = aiffUInt16(data, at: 20)
    let frames = aiffUInt32(data, at: 22)
    let bits = aiffUInt16(data, at: 26)
    assertEqual(channels, 1, "单声道")
    assertEqual(bits, 16, "16-bit")
    assertEqual(frames, UInt32(pcm.count), "帧数与 PCM 长度一致")
    // 采样率字段是 80-bit 扩展精度：44100 = 1.345... × 2^15，指数偏置 16398 = 0x400E
    let rateBytes = [UInt8](data[28..<38])
    assertEqual(rateBytes, [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0],
                "采样率字段 = 44100Hz（80-bit 扩展精度）")
    // 文件总长 = 头 + 采样数据（每样本 2 字节）
    assertEqual(data.count, pcm.count * 2 + 54, "AIFF 总长 = 样本 × 2 + 54 字节头")
}

/// 按大端读一个 UInt16（AIFF 字段都是大端）
private func aiffUInt16(_ data: Data, at offset: Int) -> UInt16 {
    let bytes = [UInt8](data[offset..<offset + 2])
    return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
}

/// 按大端读一个 UInt32
private func aiffUInt32(_ data: Data, at offset: Int) -> UInt32 {
    let bytes = [UInt8](data[offset..<offset + 4])
    return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
        | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
}

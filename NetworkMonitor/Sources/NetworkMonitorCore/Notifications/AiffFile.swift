import Foundation

// MARK: - AIFF 编码

/// AIFF 编码 — 16-bit 大端 PCM 单声道容器
///
/// 为什么手写容器而不引 AVFoundation：Core 层不带媒体框架依赖，TestRunner 能直接断言字节；
/// 而 NSSound 与系统通知都认 AIFF（系统通知只吃 AIFF / WAV / CAF 这三种）。
public enum AiffFile {

    /// 把 16-bit 采样打包成完整 AIFF 文件
    public static func encode(pcm: [Int16], sampleRate: Double) -> Data {
        let frames = UInt32(clamping: pcm.count)
        let sampleBytes = UInt32(clamping: pcm.count * 2)
        let ssndSize = sampleBytes + 8
        // 文件总长 = "AIFF"(4) + COMM 头(8) + COMM 体(18) + SSND 头(8) + SSND 体
        let formSize = 4 + (8 + 18) + (8 + ssndSize)

        var data = Data()
        data.append(contentsOf: Array("FORM".utf8))
        appendBigEndian(formSize, to: &data)
        data.append(contentsOf: Array("AIFF".utf8))

        data.append(contentsOf: Array("COMM".utf8))
        appendBigEndian(UInt32(18), to: &data)
        appendBigEndian(UInt16(1), to: &data)
        appendBigEndian(frames, to: &data)
        appendBigEndian(UInt16(16), to: &data)
        data.append(contentsOf: extended80(sampleRate))

        data.append(contentsOf: Array("SSND".utf8))
        appendBigEndian(ssndSize, to: &data)
        appendBigEndian(UInt32(0), to: &data)
        appendBigEndian(UInt32(0), to: &data)
        for sample in pcm {
            appendBigEndian(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    // MARK: - 字序与浮点字段

    private static func appendBigEndian(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value >> 8 & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value >> 24 & 0xFF))
        data.append(UInt8(value >> 16 & 0xFF))
        data.append(UInt8(value >> 8 & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    /// IEEE 754 80-bit 扩展精度（AIFF 的采样率字段就是这个格式，大端）
    ///
    /// 取值永远是 2 的整数次幂乘一个 53 位以内尾数（44100 这类整数），
    /// Double 的 52 位精度足够精确表达，不会掉位。
    static func extended80(_ value: Double) -> [UInt8] {
        guard value > 0 else { return [UInt8](repeating: 0, count: 10) }
        // 规范化到尾数 ∈ [1, 2)：扩展精度的整数位是显式的 1，取别的区间读者会算出两倍偏差
        var mantissa = value
        var exponent = 0
        while mantissa >= 2 {
            mantissa /= 2
            exponent += 1
        }
        while mantissa < 1 {
            mantissa *= 2
            exponent -= 1
        }
        let biased = UInt16(clamping: exponent + 16_383)
        let significand = UInt64(mantissa * 9_223_372_036_854_775_808)
        var bytes: [UInt8] = [
            UInt8(biased >> 8 & 0xFF), UInt8(biased & 0xFF),
        ]
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(significand >> UInt64(shift) & 0xFF))
        }
        return bytes
    }
}
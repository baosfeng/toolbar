import Foundation

// MARK: - cue 音色族

/// 提示音的性格族 — 一个 cue 归一族，同族共用同一份合成配方
///
/// 为什么按族而不是按 cue 逐条写配方：十一个 cue 里大半是同一件事的变体
/// （复制与截图都是「咔嚓」、额度重置与回升都是「叮-叮」），
/// 逐条写会让配方表变成十一段重复的魔数；按族写则改一处即全族一致。
public enum CueSoundFamily: String, CaseIterable, Sendable {
    /// 机械键「咔嚓」：极短高频噪声 + 轻微体音
    case crisp
    /// 钝「嗒」：低频正弦快速衰减
    case thud
    /// 清亮「叮-叮」：两声衰减正弦
    case chime
    /// 下行「唰」：噪声 + 频率下滑
    case swipe
    /// 低沉两段方波
    case alert
}

// MARK: - 合成器

/// cue 音效合成器 — 纯逻辑（不依赖 AppKit / AVFoundation），运行期生成 PCM
///
/// 口径：
/// - 44.1kHz / 16-bit / 单声道，峰值归一化到 0.5（不刺耳，也不至于听不见）；
/// - 起音 ≤ 3ms、结尾 8ms 线性淡出：两头都收到 0，避免爆音与截断咔嗒声；
/// - 全流程确定性（噪声走固定种子的 SplitMix64），同 cue 每次生成字节一致，
///   于是可以断言、可以缓存，配方升级时只认 `version`。
public enum CueSoundSynth {

    /// 采样率
    public static let sampleRate: Double = 44_100
    /// 目标峰值（归一化到这里）
    public static let peak: Double = 0.5
    /// 全曲尾部淡出时长（秒）
    public static let fadeOut: Double = 0.008
    /// 单层起音上限（秒）——超过这个就会听到「噗」
    private static let maxAttack: Double = 0.003

    // MARK: - 生成

    /// 生成某个 cue 的 16-bit PCM（长度 = 配方时长 × 采样率）
    public static func pcm(for cue: NotificationCue) -> [Int16] {
        var buffer = render(family: cue.builtInFamily)
        normalize(&buffer)
        fadeOutTail(&buffer)
        return buffer.map { Int16(clamping: Int(($0 * 32_767).rounded())) }
    }

    /// 生成某个 cue 的 AIFF 文件内容（含容器头）
    public static func aiffData(for cue: NotificationCue) -> Data {
        AiffFile.encode(pcm: pcm(for: cue), sampleRate: sampleRate)
    }

    /// 生成文件的主名（无扩展名）：应用内播放与通知副本共用同一份命名
    public static func fileStem(for cue: NotificationCue) -> String {
        "cue-\(cue.rawValue)"
    }

    /// 配方版本 — 改配方就加一，磁盘上的旧文件据此重新生成
    ///
    /// 不用文件时间戳判新旧：时间戳会因拷贝 / 备份还原而漂移，
    /// 而「这份 aiff 是不是当前配方生成的」只有版本号说得清。
    public static let version = "1"

    // MARK: - 配方

    /// 一层音：起始时刻 + 时长 + 增益 + 波形
    struct Layer {
        let start: Double
        let duration: Double
        let gain: Double
        let shape: Shape

        enum Shape {
            /// 带通噪声（中心频率 + 带宽，Hz）
            case noise(centerHz: Double, bandwidthHz: Double)
            /// 正弦（起始频率，可下滑到 endHz）
            case sine(hz: Double, endHz: Double)
            /// 方波
            case square(hz: Double)
        }
    }

    /// 一族音的全部层（顺序即叠加顺序，不影响结果之和）
    struct Recipe {
        let duration: Double
        let layers: [Layer]
    }

    static func recipe(for family: CueSoundFamily) -> Recipe {
        switch family {
        case .crisp:
            // 机械键「咔—嚓」：4ms 高频 tick + 13ms 中高频体噪声，只留一点低频体音压住
            return Recipe(duration: 0.030, layers: [
                Layer(start: 0, duration: 0.004, gain: 1.0,
                      shape: .noise(centerHz: 4_200, bandwidthHz: 3_000)),
                Layer(start: 0.005, duration: 0.013, gain: 0.62,
                      shape: .noise(centerHz: 2_600, bandwidthHz: 1_800)),
                Layer(start: 0.005, duration: 0.018, gain: 0.22,
                      shape: .sine(hz: 1_500, endHz: 1_300)),
            ])
        case .thud:
            // 320Hz 快速衰减 + 一下点击噪声：更钝的「嗒」
            return Recipe(duration: 0.043, layers: [
                Layer(start: 0, duration: 0.035, gain: 1.0,
                      shape: .sine(hz: 320, endHz: 260)),
                Layer(start: 0, duration: 0.006, gain: 0.28,
                      shape: .noise(centerHz: 700, bandwidthHz: 500)),
            ])
        case .chime:
            // 两声 2.4kHz 衰减正弦，间隔 40ms：清亮的「叮-叮」
            return Recipe(duration: 0.118, layers: [
                Layer(start: 0, duration: 0.070, gain: 1.0,
                      shape: .sine(hz: 2_400, endHz: 2_400)),
                Layer(start: 0.040, duration: 0.070, gain: 0.75,
                      shape: .sine(hz: 2_400, endHz: 2_400)),
            ])
        case .swipe:
            // 噪声 + 1.8k→500Hz 下滑：短促下行的「唰」
            return Recipe(duration: 0.068, layers: [
                Layer(start: 0, duration: 0.060, gain: 0.9,
                      shape: .noise(centerHz: 1_500, bandwidthHz: 1_800)),
                Layer(start: 0, duration: 0.060, gain: 0.5,
                      shape: .sine(hz: 1_800, endHz: 500)),
            ])
        case .alert:
            // 220Hz / 165Hz 两段方波：沉下来的「警告」
            return Recipe(duration: 0.153, layers: [
                Layer(start: 0, duration: 0.070, gain: 0.62, shape: .square(hz: 220)),
                Layer(start: 0.075, duration: 0.070, gain: 0.62, shape: .square(hz: 165)),
            ])
        }
    }

    // MARK: - 渲染

    /// 按配方叠加出浮点样本（未归一化）
    static func render(family: CueSoundFamily) -> [Double] {
        let plan = recipe(for: family)
        var buffer = [Double](repeating: 0, count: frames(plan.duration))
        for (index, layer) in plan.layers.enumerated() {
            render(layer, seed: seed(for: family, layer: index), into: &buffer)
        }
        return buffer
    }

    private static func render(_ layer: Layer, seed: UInt64, into buffer: inout [Double]) {
        let start = frames(layer.start)
        let count = frames(layer.duration)
        guard count > 0, start < buffer.count else { return }
        var rng = SplitMix64(state: seed)
        var filter = BiquadBandpass()
        let attack = attackSeconds(for: layer.shape)
        // 每层尾部 2ms 收到 0：层与层相接处也听不到断点
        let tail = Double(max(1, frames(min(0.002, layer.duration / 2))))
        let decay = layer.duration / 3.2
        var phase = 0.0
        var squareLowpass = 0.0
        for offset in 0..<count {
            let time = Double(offset) / sampleRate
            let progress = Double(offset) / Double(max(1, count - 1))
            let wave: Double
            switch layer.shape {
            case .noise(let center, let bandwidth):
                if !filter.isConfigured {
                    filter.configure(centerHz: center, bandwidthHz: bandwidth, sampleRate: sampleRate)
                }
                let white = rng.nextDouble()
                // 七成半谐振噪声 + 两成半原始白噪声：纯谐振器太「呼哨」，纯白噪又没频段
                wave = filter.process(white) * 0.75 + white * 0.25
            case .sine(let hz, let endHz):
                phase += 2 * Double.pi * (hz + (endHz - hz) * progress) / sampleRate
                wave = sin(phase)
            case .square(let hz):
                phase += 2 * Double.pi * hz / sampleRate
                // 一阶低通把方波的锯齿边磨圆：全带宽方波听起来是「刺」而不是「沉」
                squareLowpass = squareLowpass + (sin(phase) >= 0 ? 1 : -1 - squareLowpass) * 0.18
                wave = squareLowpass
            }
            let envelope = min(1, time / attack) * exp(-time / decay)
            let edge = min(Double(offset), Double(count - 1 - offset))
            let tailFactor = min(1, edge / tail)
            buffer[start + offset] += wave * envelope * tailFactor * layer.gain
        }
    }

    /// 归一化到目标峰值（全零时原样返回）
    private static func normalize(_ buffer: inout [Double]) {
        let peakValue = buffer.reduce(0) { max($0, abs($1)) }
        guard peakValue > 0 else { return }
        let scale = peak / peakValue
        for index in buffer.indices { buffer[index] *= scale }
    }

    /// 结尾 8ms 线性淡出——最后一个样本严格为 0
    private static func fadeOutTail(_ buffer: inout [Double]) {
        let count = frames(fadeOut)
        guard count > 1, buffer.count >= count else { return }
        for offset in 0..<count {
            let index = buffer.count - count + offset
            buffer[index] *= Double(count - 1 - offset) / Double(count - 1)
        }
    }

    // MARK: - 参数

    /// 各波形起音时长（都不超过 maxAttack）
    private static func attackSeconds(for shape: Layer.Shape) -> Double {
        switch shape {
        case .noise: return 0.0004
        case .sine, .square: return 0.0015
        }
    }

    /// 秒 → 样本数
    private static func frames(_ seconds: Double) -> Int {
        max(1, Int((seconds * sampleRate).rounded()))
    }

    /// 每层的噪声种子：族 + 层序号决定，改一层不会让别的层悄悄变样
    private static func seed(for family: CueSoundFamily, layer: Int) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in family.rawValue.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return hash ^ (UInt64(layer &+ 1) &* 0x9E37_79B9_7F4A_7C15)
    }
}

// MARK: - 确定性噪声

/// SplitMix64 — 固定种子、跨平台一致的伪随机数（系统随机源会让音效不可断言）
private struct SplitMix64 {
    var state: UInt64

    mutating func nextDouble() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53) * 2 - 1
    }
}

// MARK: - 带通滤波

/// RBJ 双二次带通 — 给噪声上「频段」，否则白噪声听起来只有沙沙声
private struct BiquadBandpass {
    private var b0 = 0.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0
    private(set) var isConfigured = false

    mutating func configure(centerHz: Double, bandwidthHz: Double, sampleRate: Double) {
        let omega = 2 * Double.pi * max(20, min(centerHz, sampleRate * 0.45)) / sampleRate
        let quality = max(0.3, centerHz / max(1, bandwidthHz))
        let alpha = sin(omega) / (2 * quality)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = -2 * cos(omega) / a0
        a2 = (1 - alpha) / a0
        isConfigured = true
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}
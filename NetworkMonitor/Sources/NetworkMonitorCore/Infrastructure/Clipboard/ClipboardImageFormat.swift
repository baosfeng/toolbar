import Foundation
import UniformTypeIdentifiers

// MARK: - 剪贴板图片格式候选

/// JPEG 的统一类型标识（白名单与回写判定共用一份，避免字面量在多处重复）
private let clipboardJPEGTypeName = "public.jpeg"

/// 剪贴板图片格式兼容判定 — 纯函数，不依赖 AppKit（采集侧与回写侧共用同一份口径）
///
/// 背景：采集侧只认 png / tiff 时，从「预览 / 照片 / 浏览器 / 微信」复制 HEIC / WebP / GIF / JPEG
/// 会整条静默漏采。这里用「显式白名单 + 统一类型系统兜底」的正向判据：
/// 先按白名单优先级输出命中的类型名，再追加其它 UTI 归入 image 的类型，避免黑名单式的排除法。
public enum ClipboardImageFormat {

    /// 显式白名单（按优先级降序）
    ///
    /// 前两项仍是 PNG / TIFF，保持既有的「PNG 优先、TIFF 兜底」语义不变；
    /// 类型名写字面值而不取 UTType 常量，避免个别系统缺该 UTI 时白名单被静默缩短。
    public static let whitelistedTypeNames: [String] = [
        "public.png",
        "public.tiff",
        clipboardJPEGTypeName,
        "public.heic",
        "public.heif",
        "org.webmproject.webp",
        "com.compuserve.gif",
        "com.microsoft.bmp"
    ]

    /// 类型名归一化（去首尾空白 + 转小写；空串判为无类型）
    ///
    /// 系统给的类型名大小写与空白并不稳定，判等一律走归一化结果；
    /// 输出时白名单命中给白名单里的规范名，兜底命中保留调用方原始写法（写入侧按原名取字节）。
    public static func normalized(_ typeName: String) -> String? {
        let trimmed = typeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    /// 候选类型名排序：白名单命中（按白名单顺序）→ 其余 image 类型（按入参顺序）
    ///
    /// - 去重按归一化结果：同一个类型名的大小写变体、带空白的变体只留第一次出现的那一项
    /// - 白名单命中一律输出白名单里的规范名，保证调用方能按规范名取到 pasteboard 数据
    /// - 白名单外但 `UTType.conforms(to: .image)` 的类型追加在后面（兜底未来格式）
    /// - 纯文本等非图片类型、空数组、全空白数组都返回空候选（调用方据此走既有降级）
    public static func orderedCandidates(from typeNames: [String]) -> [String] {
        // 1) 输入保序去重：归一化结果 → 原始写法（首次出现）
        var entries: [(key: String, original: String)] = []
        var seenKeys: Set<String> = []
        for typeName in typeNames {
            guard let key = normalized(typeName) else { continue }
            guard seenKeys.insert(key).inserted else { continue }
            entries.append((key, typeName.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        guard !entries.isEmpty else { return [] }

        var ordered: [String] = []
        var usedKeys: Set<String> = []
        // 2) 白名单命中按白名单优先级输出
        for canonical in whitelistedTypeNames {
            guard entries.contains(where: { $0.key == canonical }) else { continue }
            guard usedKeys.insert(canonical).inserted else { continue }
            ordered.append(canonical)
        }
        // 3) 兜底：白名单外但统一类型系统判为图片
        for entry in entries where !usedKeys.contains(entry.key) {
            guard isImageType(entry.original) else { continue }
            guard usedKeys.insert(entry.key).inserted else { continue }
            ordered.append(entry.original)
        }
        return ordered
    }

    /// 该类型名是否归入图片（白名单之外的兜底判据，走统一类型系统而非硬编码枚举）
    public static func isImageType(_ typeName: String) -> Bool {
        guard let key = normalized(typeName), let type = UTType(key) else { return false }
        return type.conforms(to: .image)
    }

    /// 取字节时该试的类型名（候选本身 + 与它归一化等价的原始写法，按入参顺序）
    ///
    /// 白名单命中给的是规范名，而系统实际登记的类型名可能带大小写或空白差异，
    /// 因此先按候选名试，不行再按等价原始名试；两者重复时只留一个。
    public static func dataLookupNames(for candidate: String, in typeNames: [String]) -> [String] {
        guard let candidateKey = normalized(candidate) else { return [] }
        var names: [String] = []
        var seenNames: Set<String> = []
        // 候选名本身优先（白名单命中时它是规范名），随后是同归一化键的其它原始写法
        for rawName in [candidate] + typeNames {
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = normalized(trimmed), key == candidateKey else { continue }
            guard seenNames.insert(trimmed).inserted else { continue }
            names.append(trimmed)
        }
        return names
    }

    /// 首个可读表示的查询结果（类型名 + 原始字节，不含任何 AppKit 类型）
    public struct Selection: Equatable, Sendable {
        /// 命中的类型名（白名单命中时是规范名）
        public let typeName: String
        /// 该类型名对应的原始字节
        public let data: Data

        public init(typeName: String, data: Data) {
            self.typeName = typeName
            self.data = data
        }
    }

    /// 按候选顺序取首个非空表示：判定全在 Core，调用方只需提供「按类型名取字节」的读取闭包
    ///
    /// - Parameter read: 按类型名取原始字节（返回 nil 或空数据视为该候选不可用，继续试下一个）
    /// - Returns: 首个可用候选；无候选或全部不可用返回 nil（调用方据此走既有降级）
    public static func firstReadableCandidate(in typeNames: [String],
                                              read: (String) -> Data?) -> Selection? {
        for candidate in orderedCandidates(from: typeNames) {
            for name in dataLookupNames(for: candidate, in: typeNames) {
                guard let data = read(name), !data.isEmpty else { continue }
                return Selection(typeName: candidate, data: data)
            }
        }
        return nil
    }

    /// 该文件类型标识是否为 JPEG（回写据此决定是否补一份 JPEG 表示）
    public static func isJPEGType(_ typeIdentifier: String?) -> Bool {
        guard let typeIdentifier, let key = normalized(typeIdentifier) else { return false }
        return key == clipboardJPEGTypeName
    }

    /// JPEG 写入剪贴板时用的类型名
    public static var jpegTypeName: String { clipboardJPEGTypeName }

    /// 回写是否要额外写 JPEG 表示
    ///
    /// 白名单语义：PNG + TIFF 正常时只在原图本身是 JPEG 时补一份 JPEG（保留原始压缩形态）；
    /// PNG 与 TIFF 都编不出来时由 JPEG 兜底，避免三种全失败而整体写回失败。
    public static func shouldWriteJPEG(sourceIsJPEG: Bool, pngAvailable: Bool, tiffAvailable: Bool) -> Bool {
        if sourceIsJPEG { return true }
        return !pngAvailable && !tiffAvailable
    }
}

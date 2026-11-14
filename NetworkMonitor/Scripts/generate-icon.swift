#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - 用法
//
// 一览（NetworkMonitor）App 图标生成器 —— 纯 Core Graphics 绘制，零外部资源。
//
//   swift Scripts/generate-icon.swift <输出目录>
//   swift Scripts/generate-icon.swift <输出目录> --size 32        # 只导出单档 PNG（调试用）
//
// 默认产出：<输出目录>/AppIcon.iconset（16…512 全 10 档）+ <输出目录>/AppIcon.icns，
// 成功后删除 iconset；加 --keep-iconset 可保留中间产物。
//
// 图形语言（原型 .open-design/drafts/s1-icons/s1-icon-a2-rings.html 定稿的 A2「同心环」）：
// 22% 圆角微渐变盘面 + 渐变色外环 + 白色中环 + 深色玻璃核 + 一处高光 + 玻璃内外描边。
// 小尺寸按 detailCompression 连续压缩：外环加粗、中环让位、核相对放大，
// 保证 16px 下仍是「亮盘 + 蓝环 + 暗心」而不是一团蓝。

// MARK: - 错误

/// 图标生成失败原因（脚本级显式类型，不用字符串抛错）
enum IconGenerationError: Error {
    case bitmapContextUnavailable(pixels: Int)
    case imageEncodingFailed(pixels: Int)
    case iconutilFailed(output: String)
    case invalidArgument(String)
}

// MARK: - 颜色与渐变工具

/// sRGB 颜色（0xRRGGBB），绘图全程使用显式色彩空间，不依赖当前外观
func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// 线性插值
func mix(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat { from + (to - from) * t }

/// 渐变定义（色标 + 位置）
struct GradientSpec {
    let stops: [(color: CGColor, location: CGFloat)]

    func gradient() -> CGGradient? {
        let colors = stops.map(\.color) as CFArray
        let locations = stops.map { $0.location }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: colors,
                          locations: locations)
    }
}

// MARK: - 几何参数（随像素尺寸连续插值）

/// 单档像素尺寸下的绘制几何
///
/// compression 是核心变量：0 = 128px 以上的精细版，1 = 16px 的极简版。
/// 所有长度都是「占盘面边长的比例 × side」，因此同一套参数可画出任意尺寸。
struct IconGeometry {
    let side: CGFloat
    /// 小尺寸压缩系数（0…1）
    let compression: CGFloat

    /// 22% 大圆角
    let cornerRadius: CGFloat
    /// 外环中心半径 / 线宽
    let outerRingRadius: CGFloat
    let outerRingWidth: CGFloat
    /// 核半径
    let coreRadius: CGFloat
    /// 中白环中心半径 / 线宽 / 不透明度
    let innerRingRadius: CGFloat
    let innerRingWidth: CGFloat
    let innerRingAlpha: CGFloat
    /// 核上高光强度（0 = 不画）
    let highlightAlpha: CGFloat
    /// 玻璃内外描边（小尺寸只保留极细外缘）
    let usesGlassEdges: Bool

    /// 由像素尺寸推导压缩系数：128px 及以上为 0，16px 为 1，中间连续过渡
    static func compression(for side: CGFloat) -> CGFloat {
        guard side > 1 else { return 1 }
        let level = log2(side)
        return min(max((7 - level) / 3, 0), 1)
    }

    init(side: CGFloat) {
        let t = Self.compression(for: side)
        self.side = side
        self.compression = t
        cornerRadius = side * 0.22
        // 外环：小尺寸从 6.45% 加粗到 11%（16px 上 1.76px，仍是一整圈实线）
        outerRingRadius = side * mix(0.2598, 0.2620, t)
        outerRingWidth = side * mix(0.0620, 0.1100, t)
        // 核：小尺寸从 10.4% 放大到 12.5%（16px 上直径 4px），保证暗心可辨
        coreRadius = side * mix(0.1040, 0.1250, t)
        // 中白环：32px 及以下完全让位（否则与核、外环糊成一条脏线）
        innerRingRadius = side * 0.1760
        innerRingAlpha = max(0, (0.55 - t) / 0.55)
        innerRingWidth = side * 0.0430 * innerRingAlpha
        // 高光只保留 1 处，64px 以下衰减到 0
        highlightAlpha = max(0, (0.5 - t) / 0.5)
        usesGlassEdges = t < 0.5
    }

    /// 自检打印用的一行摘要
    var summary: String {
        let ring = String(format: "%.2f", Double(outerRingWidth))
        let core = String(format: "%.2f", Double(coreRadius * 2))
        let inner = innerRingAlpha > 0.01 ? String(format: "%.2f", Double(innerRingWidth)) : "—"
        let mark = highlightAlpha > 0.01 ? "√" : "—"
        return [String(format: "%4.0fpx", Double(side)),
                String(format: "t=%.2f", Double(compression)),
                "环宽 \(ring)",
                "核径 \(core)",
                "中环 \(inner)",
                "高光 \(mark)"].joined(separator: "  ")
    }
}

// MARK: - 绘制

/// 盘面线性渐变（左上 → 右下，158° 视觉方向）
let panelGradient = GradientSpec(stops: [
    (srgb(0xFFFFFF), 0.00),
    (srgb(0xEDF3FC), 0.38),
    (srgb(0xD6E2F4), 0.72),
    (srgb(0xBCCCE6), 1.00),
])

/// 外环渐变（左上深蓝 → 右下青）
let ringGradient = GradientSpec(stops: [
    (srgb(0x2447C6), 0.00),
    (srgb(0x3E7DF0), 0.50),
    (srgb(0x2CC0E0), 1.00),
])

/// 核渐变（左上深靛 → 右下青）
let coreGradient = GradientSpec(stops: [
    (srgb(0x0E1E4E), 0.00),
    (srgb(0x1B55B8), 0.60),
    (srgb(0x38C4E4), 1.00),
])

/// 小尺寸核渐变（更暗，16px 上要能压出硬对比）
let denseCoreGradient = GradientSpec(stops: [
    (srgb(0x0A1640), 0.00),
    (srgb(0x15459F), 1.00),
])

/// 画一档图标（返回 CGImage，像素尺寸精确等于 side）
func renderIcon(_ geometry: IconGeometry) throws -> CGImage {
    let side = Int(geometry.side)
    guard let ctx = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconGenerationError.bitmapContextUnavailable(pixels: side)
    }

    let size = geometry.side
    let center = CGPoint(x: size / 2, y: size / 2)
    let panelRect = CGRect(x: 0, y: 0, width: size, height: size)
    let panelPath = CGPath(roundedRect: panelRect,
                           cornerWidth: geometry.cornerRadius,
                           cornerHeight: geometry.cornerRadius,
                           transform: nil)

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // 1. 盘面：22% 圆角 + 微渐变（裁到圆角内，圆角外保持透明）
    ctx.saveGState()
    ctx.addPath(panelPath)
    ctx.clip()
    if let gradient = panelGradient.gradient() {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size * 0.72, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    // 底部冷色光晕：小尺寸几乎看不出，随压缩系数淡出，避免吃掉对比
    if geometry.usesGlassEdges,
       let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [srgb(0x4F6BFF, alpha: 0.22 * (1 - geometry.compression)),
                                      srgb(0x4F6BFF, alpha: 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: size / 2, y: size * 0.14), startRadius: 0,
                               endCenter: CGPoint(x: size / 2, y: size * 0.14), endRadius: size * 0.62,
                               options: [])
    }
    ctx.restoreGState()

    // 2. 外环：描边路径本身当裁剪区，才能让渐变沿着环走
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - geometry.outerRingRadius,
                              y: center.y - geometry.outerRingRadius,
                              width: geometry.outerRingRadius * 2,
                              height: geometry.outerRingRadius * 2))
    ctx.setLineWidth(geometry.outerRingWidth)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let gradient = ringGradient.gradient() {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: size * 0.15, y: size * 0.85),
                               end: CGPoint(x: size * 0.85, y: size * 0.15),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    // 3. 中白环（≥64px 才出现）
    if geometry.innerRingAlpha > 0.01 {
        ctx.saveGState()
        ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.94 * geometry.innerRingAlpha))
        ctx.setLineWidth(geometry.innerRingWidth)
        let radius = geometry.innerRingRadius
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 4. 核：暗底玻璃球
    let coreRect = CGRect(x: center.x - geometry.coreRadius,
                          y: center.y - geometry.coreRadius,
                          width: geometry.coreRadius * 2,
                          height: geometry.coreRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: coreRect)
    ctx.clip()
    let coreSpec = geometry.compression > 0.6 ? denseCoreGradient : coreGradient
    if let gradient = coreSpec.gradient() {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: coreRect.minX + coreRect.width * 0.2,
                                              y: coreRect.maxY - coreRect.height * 0.1),
                               end: CGPoint(x: coreRect.minX + coreRect.width * 0.8,
                                            y: coreRect.minY + coreRect.height * 0.05),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    // 核上唯一一处高光：左上方椭圆，径向渐变自带柔边
    if geometry.highlightAlpha > 0.01,
       let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [srgb(0xFFFFFF, alpha: 0.42 * geometry.highlightAlpha),
                                           srgb(0xFFFFFF, alpha: 0)] as CFArray,
                                  locations: [0, 1]) {
        let radius = geometry.coreRadius * 0.46
        ctx.saveGState()
        ctx.translateBy(x: center.x - geometry.coreRadius * 0.32, y: center.y + geometry.coreRadius * 0.36)
        ctx.rotate(by: -28 * .pi / 180)
        ctx.scaleBy(x: 1, y: 0.66)
        ctx.drawRadialGradient(highlight,
                               startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: radius,
                               options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // 5. 核的白描边（小尺寸省略，避免糊边）
    if geometry.usesGlassEdges {
        ctx.saveGState()
        ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.52))
        ctx.setLineWidth(max(1, size * 0.0024))
        ctx.addEllipse(in: coreRect)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 6. 玻璃边：内高光 + 外轮廓（小尺寸只留一条极细外缘确保在浅色桌面上有轮廓）
    let innerWidth = max(1, size * 0.0024)
    let outerWidth = max(1, size * 0.0018)
    ctx.saveGState()
    ctx.addPath(panelPath)
    ctx.setStrokeColor(srgb(0xFFFFFF, alpha: geometry.usesGlassEdges ? 0.95 : 0.45))
    ctx.setLineWidth(innerWidth)
    ctx.strokePath()
    ctx.addPath(panelPath)
    ctx.setStrokeColor(srgb(0x18264A, alpha: geometry.usesGlassEdges ? 0.22 : 0.30))
    ctx.setLineWidth(outerWidth)
    ctx.strokePath()
    ctx.restoreGState()

    guard let image = ctx.makeImage() else {
        throw IconGenerationError.imageEncodingFailed(pixels: side)
    }
    return image
}

// MARK: - 写盘

/// 把 CGImage 写成 PNG 文件
func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.imageEncodingFailed(pixels: image.width)
    }
    try data.write(to: url)
}

/// iconset 的 10 个档位（逻辑尺寸, 倍率）
let iconsetEntries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

// MARK: - 入口

let arguments = Array(CommandLine.arguments.dropFirst())
var outputDirectory = FileManager.default.currentDirectoryPath
var singleSize: Int?
var keepsIconset = false

var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--size":
        guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
            throw IconGenerationError.invalidArgument("--size 需要一个正整数像素尺寸")
        }
        singleSize = value
        index += 2
    case "--keep-iconset":
        keepsIconset = true
        index += 1
    default:
        outputDirectory = argument
        index += 1
    }
}

let outputRoot = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

// 单档调试模式：只出一张 PNG
if let pixels = singleSize {
    let geometry = IconGeometry(side: CGFloat(pixels))
    print(geometry.summary)
    let image = try renderIcon(geometry)
    let url = outputRoot.appendingPathComponent("preview-\(pixels).png")
    try writePNG(image, to: url)
    print("OK \(url.path)")
    exit(0)
}

let iconsetURL = outputRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

print("生成 iconset：\(iconsetURL.path)")
var writtenCount = 0
for entry in iconsetEntries {
    let pixels = entry.points * entry.scale
    let geometry = IconGeometry(side: CGFloat(pixels))
    let suffix = entry.scale == 2 ? "@2x" : ""
    let name = "icon_\(entry.points)x\(entry.points)\(suffix).png"
    let image = try renderIcon(geometry)
    try writePNG(image, to: iconsetURL.appendingPathComponent(name))
    writtenCount += 1
    print("  OK \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(pixels)x\(pixels)  \(geometry.summary)")
}

let icnsURL = outputRoot.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "--output", icnsURL.path]
let errorPipe = Pipe()
iconutil.standardError = errorPipe
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    throw IconGenerationError.iconutilFailed(output: message)
}

if keepsIconset == false {
    try? FileManager.default.removeItem(at: iconsetURL)
}

let attributes = try? FileManager.default.attributesOfItem(atPath: icnsURL.path)
let byteCount = (attributes?[.size] as? Int) ?? 0
print("\nOK \(icnsURL.path)（\(writtenCount) 档，\(byteCount) 字节）")

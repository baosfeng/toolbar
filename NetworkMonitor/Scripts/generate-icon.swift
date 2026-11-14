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
// 图形语言（原型 .open-design/drafts/s1-icons-r2/s1-r2-d2-stacked-cards.html 定稿的 D2 方向）：
// 22% 圆角微渐变盘面 + 三张错位微旋转的玻璃卡片（一屏装下多块面板），
// 正面卡里露出彩色的读数条。小尺寸按 compression 连续压缩：
//   128px 以上：三层卡片（-12° / +9° / 0°）；
//   64~32px：后卡淡出成两层，读数条加粗、条内高光撤掉；
//   32px 以下：只剩主卡 + 一道斜切边，读数条压成两条对比最强的（蓝 / 橙）。
// 全程没有圆环、没有暗心、没有红点 —— 避免与录屏 / 镜头类图标混淆。

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
func mixValue(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat { from + (to - from) * t }

/// 渐变定义（色标 + 位置）
struct GradientSpec {
    let stops: [(color: CGColor, location: CGFloat)]

    func gradient() -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: stops.map(\.color) as CFArray,
                   locations: stops.map { $0.location })
    }
}

// MARK: - 几何参数（随像素尺寸连续插值）

/// 单档像素尺寸下的绘制几何
///
/// compression 是核心变量：0 = 128px 以上的精细版（三层卡片），
/// 1 = 16px 的极简版（主卡 + 斜切边 + 两条粗读数条）。所有长度都从它插值而来。
struct IconGeometry {
    let side: CGFloat
    let compression: CGFloat

    /// 盘面 22% 大圆角
    let cornerRadius: CGFloat
    /// 卡片尺寸与圆角
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardRadius: CGFloat
    /// 卡片中心（主卡居中，略偏上给底部留呼吸）
    let center: CGPoint

    /// 后卡（-12° 方向）：偏移 / 旋转 / 填充不透明度
    let backOffset: CGPoint
    let backRotation: CGFloat
    let backAlpha: CGFloat
    /// 中卡（+9° 方向）
    let midOffset: CGPoint
    let midRotation: CGFloat
    let midAlpha: CGFloat
    let midScale: CGFloat
    /// 主卡填充不透明度
    let mainAlpha: CGFloat

    /// 卡内内容
    let titleAlpha: CGFloat
    let thirdBarAlpha: CGFloat
    let barHeight: CGFloat
    let barGap: CGFloat
    let barSpecular: CGFloat

    /// 阴影强度（0 = 不画）
    let shadowStrength: CGFloat
    let shadowBlur: CGFloat
    let shadowOffsetY: CGFloat

    /// 由像素尺寸推导压缩系数：128px 及以上为 0，16px 为 1，中间连续过渡
    static func compression(for side: CGFloat) -> CGFloat {
        guard side > 1 else { return 1 }
        return min(max((7 - log2(side)) / 3, 0), 1)
    }

    init(side: CGFloat) {
        let u = Self.compression(for: side)
        self.side = side
        self.compression = u

        cornerRadius = side * 0.22
        // 卡片：小尺寸放大卡片占比（16px 上只有 8.8px 宽，再小就看不出叠卡）
        cardWidth = side * mixValue(0.5469, 0.6200, u)
        cardHeight = side * mixValue(0.3828, 0.5200, u)
        cardRadius = side * mixValue(0.0508, 0.0750, u)
        // 主卡中心：精细版 y=0.523，极简版略上移给斜切边让位
        center = CGPoint(x: side * 0.5, y: side * mixValue(0.5234, 0.5000, u))

        // 后卡：64px 起淡出，32px 及以下完全消失（压成两层）
        backOffset = CGPoint(x: side * mixValue(-0.0957, -0.1250, u),
                             y: side * mixValue(-0.0879, -0.1050, u))
        backRotation = mixValue(-12, -17, u)
        backAlpha = max(0, (0.5 - u) / 0.5)

        // 中卡：始终保留，越往小越收窄，最终只剩一道斜切边
        midOffset = CGPoint(x: side * mixValue(0.1172, 0.1150, u),
                            y: side * mixValue(-0.0195, -0.0250, u))
        midRotation = mixValue(9, 16, u)
        midAlpha = mixValue(0.60, 0.78, u)
        // 小尺寸中卡要比主卡略大，斜切边才露得出来（否则被主卡完全遮住）
        midScale = mixValue(1.0, 1.065, u)

        mainAlpha = mixValue(0.76, 0.92, u)

        // 内容：标题条与条内高光在小尺寸消失；第三条读数条 32px 以下淡出
        titleAlpha = max(0, (0.5 - u) / 0.5)
        thirdBarAlpha = min(max((0.65 - u) / 0.25, 0), 1)
        barHeight = cardHeight * mixValue(0.0969, 0.1150, u)
        barGap = cardHeight * mixValue(0.0561, 0.1500, u)
        barSpecular = max(0, (0.4 - u) / 0.4)

        // 阴影：小尺寸收紧，否则 16px 上会糊成一团
        shadowStrength = mixValue(1.0, 0.45, u)
        shadowBlur = side * mixValue(0.0264, 0.0120, u)
        shadowOffsetY = side * mixValue(0.0215, 0.0100, u)
    }

    /// 每条读数条相对卡宽的宽度（0 = 蓝，1 = 青，2 = 橙）
    func barWidthRatio(at index: Int) -> CGFloat {
        switch index {
        case 0: return mixValue(0.8071, 0.8600, compression)
        case 1: return mixValue(0.4893, 0.7200, compression)
        default: return mixValue(0.6464, 0.7200, compression)
        }
    }

    /// 自检打印用的一行摘要
    var summary: String {
        let layers = backAlpha > 0.02 ? (midAlpha > 0.02 ? 3 : 2) : (midAlpha > 0.02 ? 2 : 1)
        let bars = thirdBarAlpha > 0.02 ? 3 : 2
        let card = String(format: "%.1f×%.1f", Double(cardWidth), Double(cardHeight))
        let bar = String(format: "%.2f", Double(barHeight))
        return [String(format: "%4.0fpx", Double(side)),
                String(format: "u=%.2f", Double(compression)),
                "卡 \(card)",
                "层 \(layers)",
                "条 \(bars)×\(bar)",
                "后卡 \(String(format: "%.2f", Double(backAlpha)))"].joined(separator: "  ")
    }
}

// MARK: - 渐变

/// 盘面线性渐变（左上 → 右下）
let panelGradient = GradientSpec(stops: [
    (srgb(0xFFFFFF), 0.00),
    (srgb(0xEDF3FC), 0.38),
    (srgb(0xD6E2F4), 0.72),
    (srgb(0xBCCCE6), 1.00),
])

/// 三条读数条的渐变（蓝 / 青 / 橙，与面板语义族同源）
let barGradients: [GradientSpec] = [
    GradientSpec(stops: [(srgb(0x1B3488), 0.0), (srgb(0x3E9BFF), 1.0)]),
    GradientSpec(stops: [(srgb(0x0B6D64), 0.0), (srgb(0x2DD4BF), 1.0)]),
    GradientSpec(stops: [(srgb(0xA83A0B), 0.0), (srgb(0xFB923C), 1.0)]),
]

// MARK: - 绘制

/// 画盘面：22% 圆角 + 微渐变 + 玻璃内外描边
func drawPanel(_ ctx: CGContext, _ geometry: IconGeometry) {
    let size = geometry.side
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect,
                      cornerWidth: geometry.cornerRadius,
                      cornerHeight: geometry.cornerRadius,
                      transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if let gradient = panelGradient.gradient() {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size * 0.72, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    // 底部冷色光晕（小尺寸淡出，避免吃掉对比）
    if geometry.compression < 0.6,
       let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [srgb(0x5B7BF0, alpha: 0.20 * (1 - geometry.compression)),
                                      srgb(0x5B7BF0, alpha: 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: size / 2, y: size * 0.12), startRadius: 0,
                               endCenter: CGPoint(x: size / 2, y: size * 0.12), endRadius: size * 0.66,
                               options: [])
    }
    ctx.restoreGState()

    // 玻璃边：内亮线 + 外轮廓（小尺寸只留极细外缘，保证在浅色桌面上有轮廓）
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(srgb(0xFFFFFF, alpha: geometry.compression < 0.5 ? 0.95 : 0.45))
    ctx.setLineWidth(max(1, size * 0.0024))
    ctx.strokePath()
    ctx.addPath(path)
    ctx.setStrokeColor(srgb(0x18264A, alpha: geometry.compression < 0.5 ? 0.22 : 0.30))
    ctx.setLineWidth(max(1, size * 0.0018))
    ctx.strokePath()
    ctx.restoreGState()
}

/// 画一张圆角卡（中心 + 旋转 + 缩放 + 可选阴影）
func drawCard(_ ctx: CGContext,
              geometry: IconGeometry,
              center: CGPoint,
              rotationDegrees: CGFloat,
              scale: CGFloat,
              fillAlpha: CGFloat,
              shadowStrength: CGFloat,
              tintAlpha: CGFloat = 0) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotationDegrees * .pi / 180)
    if scale != 1 {
        ctx.scaleBy(x: scale, y: scale)
    }
    let rect = CGRect(x: -geometry.cardWidth / 2, y: -geometry.cardHeight / 2,
                      width: geometry.cardWidth, height: geometry.cardHeight)
    let path = CGPath(roundedRect: rect,
                      cornerWidth: geometry.cardRadius,
                      cornerHeight: geometry.cardRadius,
                      transform: nil)

    if shadowStrength > 0.01 {
        ctx.setShadow(offset: CGSize(width: 0, height: -geometry.shadowOffsetY),
                      blur: geometry.shadowBlur,
                      color: srgb(0x16213C, alpha: 0.24 * shadowStrength))
    }
    ctx.addPath(path)
    ctx.setFillColor(srgb(0xFFFFFF, alpha: fillAlpha))
    ctx.fillPath()
    // 小尺寸：背后那张卡补一层极淡墨色，与白主卡拉开明暗差（16px 上靠它读层次）
    if tintAlpha > 0.01 {
        ctx.addPath(path)
        ctx.setFillColor(srgb(0x18264A, alpha: tintAlpha))
        ctx.fillPath()
    }
    // 描边不带阴影，否则边缘会发虚
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(srgb(0xFFFFFF, alpha: min(1, fillAlpha + 0.22)))
    ctx.setLineWidth(max(1, geometry.side * 0.0024))
    ctx.strokePath()
    // 小尺寸补一圈淡墨边：叠卡之间的分界靠它才看得清
    if geometry.compression > 0.5 {
        ctx.addPath(path)
        ctx.setStrokeColor(srgb(0x18264A, alpha: 0.14))
        ctx.setLineWidth(max(1, geometry.side * 0.0018))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

/// 画主卡里的内容：标题条（仅大尺寸）+ 2~3 条彩色读数条
func drawCardContent(_ ctx: CGContext, _ geometry: IconGeometry) {
    let g = geometry
    let left = g.center.x - g.cardWidth / 2 + g.cardWidth * 0.0964
    let top = g.center.y + g.cardHeight / 2

    // 标题条：代表「卡头」，小尺寸直接省掉
    if g.titleAlpha > 0.02 {
        let titleRect = CGRect(x: left,
                               y: top - g.cardHeight * 0.0867 - g.cardHeight * 0.0561,
                               width: g.cardWidth * 0.2464,
                               height: g.cardHeight * 0.0561)
        let titlePath = CGPath(roundedRect: titleRect,
                               cornerWidth: titleRect.height / 2,
                               cornerHeight: titleRect.height / 2,
                               transform: nil)
        ctx.addPath(titlePath)
        ctx.setFillColor(srgb(0x18264A, alpha: 0.26 * g.titleAlpha))
        ctx.fillPath()
    }

    let startOffset = g.cardHeight * mixValue(0.2347, 0.2600, g.compression)
    let step = g.barHeight + g.barGap
    for index in 0..<3 {
        let alpha: CGFloat = index == 2 ? g.thirdBarAlpha : 1
        guard alpha > 0.02 else { continue }
        let width = g.cardWidth * g.barWidthRatio(at: index)
        // 第二条：大尺寸是青、小尺寸换成橙（蓝橙冷暖对比最强）。
        // 交叉区间收窄到 u 0.45~0.60，避免中间档位出现青橙混合的褐色。
        let secondarySwap: CGFloat = index == 1
            ? min(max((g.compression - 0.45) / 0.15, 0), 1)
            : 0
        let palette: [(gradient: GradientSpec, weight: CGFloat)] = index == 1
            ? [(barGradients[1], 1 - secondarySwap), (barGradients[2], secondarySwap)]
            : [(barGradients[index], 1)]
        let rect = CGRect(x: left,
                          y: top - startOffset - CGFloat(index) * step - g.barHeight,
                          width: width,
                          height: g.barHeight)
        let path = CGPath(roundedRect: rect,
                          cornerWidth: rect.height / 2,
                          cornerHeight: rect.height / 2,
                          transform: nil)
        for entry in palette where entry.weight > 0.02 {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setAlpha(alpha * entry.weight)
            if let gradient = entry.gradient.gradient() {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.minX, y: rect.midY),
                                       end: CGPoint(x: rect.maxX, y: rect.midY),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            ctx.restoreGState()
        }
        // 条内 16% 高光（小尺寸撤掉，避免把细条糊成一片）
        if g.barSpecular > 0.02 {
            ctx.addPath(path)
            ctx.setFillColor(srgb(0xFFFFFF, alpha: 0.16 * alpha * g.barSpecular))
            ctx.fillPath()
        }
    }
}

/// 画一档图标（返回 CGImage，像素尺寸精确等于 side）
func renderIcon(_ geometry: IconGeometry) throws -> CGImage {
    let pixels = Int(geometry.side)
    guard let ctx = CGContext(data: nil,
                              width: pixels,
                              height: pixels,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconGenerationError.bitmapContextUnavailable(pixels: pixels)
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    drawPanel(ctx, geometry)

    // 后卡 → 中卡 → 主卡：错位叠放，形成「一屏装多块面板」的剪影
    if geometry.backAlpha > 0.02 {
        drawCard(ctx, geometry: geometry,
                 center: CGPoint(x: geometry.center.x + geometry.backOffset.x,
                                 y: geometry.center.y + geometry.backOffset.y),
                 rotationDegrees: geometry.backRotation,
                 scale: 1,
                 fillAlpha: 0.44 * geometry.backAlpha + 0.12,
                 shadowStrength: geometry.shadowStrength * geometry.backAlpha)
    }
    drawCard(ctx, geometry: geometry,
             center: CGPoint(x: geometry.center.x + geometry.midOffset.x,
                             y: geometry.center.y + geometry.midOffset.y),
             rotationDegrees: -geometry.midRotation,
             scale: geometry.midScale,
             fillAlpha: geometry.midAlpha,
             shadowStrength: geometry.shadowStrength * 0.8,
             tintAlpha: max(0, (geometry.compression - 0.45) / 0.55) * 0.10)
    drawCard(ctx, geometry: geometry,
             center: geometry.center,
             rotationDegrees: 0,
             scale: 1,
             fillAlpha: geometry.mainAlpha,
             shadowStrength: geometry.shadowStrength)

    drawCardContent(ctx, geometry)

    // 主卡顶部一道镜面高光（大尺寸才有意义）
    if geometry.titleAlpha > 0.02 {
        ctx.saveGState()
        ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.9 * geometry.titleAlpha))
        ctx.setLineWidth(max(1, geometry.side * 0.0024))
        let inset = geometry.cardRadius
        ctx.move(to: CGPoint(x: geometry.center.x - geometry.cardWidth / 2 + inset,
                             y: geometry.center.y + geometry.cardHeight / 2 - geometry.cardRadius * 0.18))
        ctx.addLine(to: CGPoint(x: geometry.center.x + geometry.cardWidth / 2 - inset,
                                y: geometry.center.y + geometry.cardHeight / 2 - geometry.cardRadius * 0.18))
        ctx.strokePath()
        ctx.restoreGState()
    }

    guard let image = ctx.makeImage() else {
        throw IconGenerationError.imageEncodingFailed(pixels: pixels)
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

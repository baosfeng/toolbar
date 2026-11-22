import CoreGraphics
import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 贴图棋盘底（透明判据 + 开关口径）

private func makeOpaqueQuadImage() -> CGImage? {
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let pixels: [UInt8] = [
        255, 0, 0, 255,     0, 255, 0, 255,
        0, 0, 255, 255,     255, 255, 255, 255
    ]
    return CGDataProvider(data: Data(pixels) as CFData).flatMap { provider in
        CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
    }
}

/// 左上角一格半透明（alpha 0）、其余三格全不透明 —— 「含透明区」的最小样本
private func makePartiallyTransparentImage() -> CGImage? {
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let pixels: [UInt8] = [
        0, 0, 0, 0,         0, 255, 0, 255,
        0, 0, 255, 255,     255, 255, 255, 255
    ]
    return CGDataProvider(data: Data(pixels) as CFData).flatMap { provider in
        CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
    }
}

/// 2×2 全不透明但 alpha 通道存在（alphaInfo = premultipliedLast）：依然不该画棋盘
func runPinBoardBackgroundTests() {
    print("🧪 Testing pin board background...")

    // MARK: alpha 判据

    guard let opaque = makeOpaqueQuadImage(),
          let transparent = makePartiallyTransparentImage() else { return }
    assertEqual(SnipImageAlphaProbe.hasTransparentPixels(opaque), false,
                "全不透明的图没有透明区，不画棋盘")
    assertEqual(SnipImageAlphaProbe.hasTransparentPixels(transparent), true,
                "有一个 alpha=0 的像素就算含透明区")

    // 整图 alpha 全为 128（半透明）：也算含透明区，棋盘要画
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let translucentPixels: [UInt8] = [64, 0, 0, 128, 0, 64, 0, 128]
    let translucent = CGDataProvider(data: Data(translucentPixels) as CFData).flatMap { provider in
        CGImage(width: 1, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
    }
    assertEqual(translucent.flatMap { SnipImageAlphaProbe.hasTransparentPixels($0) }, true,
                "半透明（alpha=128）同样算含透明区")

    // MARK: 该不该画：开关 × 是否含 alpha 的四格矩阵

    assertEqual(PinBoardBackgroundResolver.shouldDraw(enabled: true, hasTransparentPixels: true), true,
                "开关打开 + 含透明区 → 画棋盘")
    assertEqual(PinBoardBackgroundResolver.shouldDraw(enabled: true, hasTransparentPixels: false), false,
                "开关打开但图全不透明 → 不画（截图 / 照片不该有棋盘噪音）")
    assertEqual(PinBoardBackgroundResolver.shouldDraw(enabled: false, hasTransparentPixels: true), false,
                "开关关闭 → 一律不画，含透明区也不画")
    assertEqual(PinBoardBackgroundResolver.shouldDraw(enabled: false, hasTransparentPixels: false), false,
                "开关关闭 + 全不透明 → 不画")

    // MARK: 偏好键：缺键即关，老用户升级后外观不变

    let storage = InMemoryStorage()
    assertEqual(PinBoardBackgroundResolver.isEnabled(storage: storage), false,
                "缺键即关：老用户升级后贴图外观与接线前一致")
    assertEqual(storage.object(forKey: PinBoardPreferenceKey.boardBackground) == nil, true,
                "读路径不写回：缺键读完仍然是缺键")
    PinBoardBackgroundResolver.save(true, storage: storage)
    assertEqual(PinBoardBackgroundResolver.isEnabled(storage: storage), true,
                "菜单里打开后落盘，新建贴图跟着走")
    PinBoardBackgroundResolver.save(false, storage: storage)
    assertEqual(PinBoardBackgroundResolver.isEnabled(storage: storage), false,
                "关掉后同样落盘")
    // 键存在但不是布尔值（手工写坏 / 旧版本留下的字符串）：按关处理，不崩
    storage.set("yes", forKey: PinBoardPreferenceKey.boardBackground)
    assertEqual(PinBoardBackgroundResolver.isEnabled(storage: storage), false,
                "非布尔值按关处理")

    // MARK: 绘制口径：格子边长 / 两档灰度 / 棋盘奇偶

    assertEqual(PinBoardBackgroundResolver.cellSize, 8, "格子边长 8pt（Retina 上 16 物理像素）")
    assertEqual(PinBoardBackgroundResolver.Tone.light > PinBoardBackgroundResolver.Tone.dark, true,
                "浅格比深格亮，棋盘才有对比")
    assertEqual(PinBoardBackgroundResolver.isLightCell(column: 0, row: 0), true, "左上格为浅格")
    assertEqual(PinBoardBackgroundResolver.isLightCell(column: 1, row: 0), false, "右邻为深格")
    assertEqual(PinBoardBackgroundResolver.isLightCell(column: 0, row: 1), false, "下邻为深格")
    assertEqual(PinBoardBackgroundResolver.isLightCell(column: 1, row: 1), true, "对角同色")
    assertEqual(PinBoardBackgroundResolver.gridCount(for: CGSize(width: 20, height: 20)),
                PinBoardBackgroundResolver.Grid(columns: 3, rows: 3),
                "20pt 见方按 8pt 格向上取整到 3×3")
    assertEqual(PinBoardBackgroundResolver.gridCount(for: CGSize(width: 8, height: 16)),
                PinBoardBackgroundResolver.Grid(columns: 1, rows: 2),
                "正好整数格时不画多余的半格")
    assertEqual(PinBoardBackgroundResolver.gridCount(for: .zero),
                PinBoardBackgroundResolver.Grid(columns: 0, rows: 0),
                "零尺寸不画格子，避免死循环 / 空转")

    print("✅ 贴图棋盘底测试通过")
}

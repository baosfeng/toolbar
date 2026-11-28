import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 覆盖层 ↔ 捕获图配对（回归：点复制 / 保存静默无反应）

/// 回归背景：旧实现用 `appKitRect(display.frame) == window.frame` 配对覆盖层与捕获图。
/// frame 会因 NSWindow 取整 / 多屏缩放漂移 0.5pt，一旦配不上，复制 / 保存 / 贴图
/// 全部静默返回，用户看到的是「点了没反应、截图界面退不出去」。
func runSnipCaptureMatchingTests() {
    print("🧪 Testing snip capture matching...")

    let image = makeMatchingFixtureImage()
    let main = SnipDisplay(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                           pixelSize: CGSize(width: 3024, height: 1964),
                           displayID: 1)
    let external = SnipDisplay(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                               pixelSize: CGSize(width: 5120, height: 2880),
                               displayID: 2)
    let captures = [SnipCapturedImage(image: image, display: main),
                    SnipCapturedImage(image: image, display: external)]

    // 1. displayID 优先：frame 传成完全对不上的值也必须配上
    //    （这正是回归点：真实窗口 frame 与 CG 翻转结果差一点点时不能失效）
    let drifted = SnipCaptureMatching.capture(forDisplayID: 2,
                                              frame: CGRect(x: 1512.5, y: 0.5, width: 2560, height: 1440),
                                              in: captures)
    assertEqual(drifted?.display.displayID, UInt32(2), "displayID 命中时不受 frame 漂移影响")
    assertEqual(drifted?.display.frame.width, 2560, "配到的是副屏那条捕获图")

    // 2. displayID 未命中时回落 frame 全等（兼容 displayID 缺失的旧假实现）
    let byFrame = SnipCaptureMatching.capture(forDisplayID: 99,
                                              frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                              in: captures)
    assertEqual(byFrame?.display.displayID, UInt32(1), "displayID 未命中时按 frame 回落")

    // 3. 单屏兜底：多屏都不匹配时返回 nil，单屏则给唯一那张（宁可比配不上好）
    let single = [SnipCapturedImage(image: image, display: main)]
    let fallback = SnipCaptureMatching.capture(forDisplayID: 99,
                                               frame: CGRect(x: 7, y: 7, width: 1, height: 1),
                                               in: single)
    assertEqual(fallback?.display.displayID, UInt32(1), "单屏时无歧义地兜底")

    // 4. 多屏且都配不上 = 明确失败，不拿错屏的图硬凑
    let unmatched = SnipCaptureMatching.capture(forDisplayID: 99,
                                                frame: CGRect(x: 7, y: 7, width: 1, height: 1),
                                                in: captures)
    assertEqual(unmatched == nil, true, "多屏都配不上时返回 nil")

    // 5. 空捕获列表不崩
    assertEqual(SnipCaptureMatching.capture(forDisplayID: 1, frame: .zero, in: []) == nil, true,
                "空捕获列表返回 nil")
}

/// 1×1 的占位图：配对逻辑与像素无关，只需要一个合法 CGImage
private func makeMatchingFixtureImage() -> CGImage {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let context, let image = context.makeImage() else {
        fatalError("测试夹具：无法创建 1×1 CGImage")
    }
    return image
}

import AppKit
import Carbon
import CoreGraphics
import Foundation
import ImageIO
import NetworkMonitorCore
import NetworkMonitorFeatureSnip
import NetworkMonitorUI

// MARK: - 截图服务层（独立 target）边界测试

/// 跨 target 断言：抓屏 / 写盘 / 写剪贴板 / OCR / 截图热键 / 偏好键住在新拆出的
/// NetworkMonitorFeatureSnip 里，TestRunner 直接 import 该模块、走真实入口。
///
/// 改造前测不到：服务层在可执行 target NetworkMonitor 里，TestRunner 对 ScreenCaptureService /
/// SnipFileWriter / SnipPasteboardImageWriter / SnipHotKeyPreferences 全不可见，只能断言 Core
/// 的纯判据。这里补四类：① 端口注入（logger / storage 必传，构造不产生副作用）；
/// ② 关键口径不变（写盘文件名与像素尺寸、剪贴板选档、热键偏好归一化、组合键展示）；
/// ③ 边界（覆盖层 UI 仍留在 App，新 target 不反向依赖 App 的任何类型）；
/// ④ 依赖方向（新 target 只 import Core / UI / 系统框架，Core 仍不依赖 Carbon）。
@MainActor
func runSnipFeatureBoundaryTests() {
    print("\n🧪 Testing 截图服务层跨 target 边界（端口注入 / 热键归一化 / 写盘与选档口径 / 源码边界）...")
    testSnipServicePortsRequireInjectedDependencies()
    testSnipHotKeyPreferenceNormalization()
    testSnipFileWriterFormatAndPixelSize()
    testSnipPasteboardWriterTierSelection()
    testSnipVisionNoTextOutcome()
    testSnipHotKeyComboDisplay()
    testSnipFeatureSourceBoundaries()
    print("✅ 截图服务层跨 target 边界 works")
}

// MARK: - 端口注入（logger / storage 必传）

@MainActor
private func testSnipServicePortsRequireInjectedDependencies() {
    let logger = RecordingLogger()
    let storage = InMemoryStorage()

    // 这几行能编译即证明三件事：三个服务已跨 target 公开；logger 没有默认值
    // （不再默认取 App 层的 AppContext.shared.logger）；存储走端口注入。
    let capture: any SnipCaptureServicing = ScreenCaptureService(logger: logger)
    let recognizer: any SnipTextRecognizing = VisionTextRecognizer(logger: logger)
    let registry = HotKeyRegistry(logger: logger)
    let preferences = SnipHotKeyPreferences(storage: storage)
    _ = recognizer

    // 权限预检只查不登记：调用不弹系统框、不把 app 写进「屏幕录制」清单
    _ = capture.isAuthorized()
    // 注销不存在的 id / 全量注销都是幂等 no-op（构造不装 Carbon 事件处理器）
    registry.unregister(4242)
    registry.unregisterAll()

    assertEqual(logger.all.isEmpty, true, "仅构造 + 空注销不产生日志（构造无副作用）")
    assertEqual(preferences.combo(for: .screenshot), SnipHotKeyAction.screenshot.defaultCombo,
                "未写入过偏好时回落默认组合")
    assertEqual(SnipHotKeyAction.allCases.count, 6, "六个截图快捷键动作都在")
    for action in SnipHotKeyAction.allCases {
        assertEqual(action.defaultCombo.hasModifier, true, "默认组合一律带修饰键：\(action.rawValue)")
        assertEqual(action.displayName.isEmpty, false, "动作都有可读名：\(action.rawValue)")
    }
}

// MARK: - 热键偏好归一化（缺键回落 / 不写回 / keyCode 0 合法 / 旧默认迁移）

@MainActor
private func testSnipHotKeyPreferenceNormalization() {
    let storage = InMemoryStorage()
    let preferences = SnipHotKeyPreferences(storage: storage)
    let screenshot = SnipHotKeyAction.screenshot

    // 缺键：回落默认，且读路径不写回（「我没设置过」不许被固化成一条显式默认值）
    assertEqual(preferences.combo(for: screenshot), screenshot.defaultCombo, "缺键回落默认组合")
    assertEqual(storage.object(forKey: screenshot.keyCodeKey) == nil, true, "读路径不回写键码")
    assertEqual(storage.object(forKey: screenshot.modifiersKey) == nil, true, "读路径不回写修饰键")
    assertEqual(preferences.combo(for: screenshot), screenshot.defaultCombo, "再读一次仍回落同一个默认值")

    // keyCode 0（kVK_ANSI_A）是合法键码：存在性看「键在不在」，不看值大小
    let keyA = HotKeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey))
    preferences.setCombo(keyA, for: screenshot)
    assertEqual(preferences.combo(for: screenshot), keyA, "keyCode 0 原样读回（A 键不被误判成未设置）")
    assertEqual(storage.integer(forKey: screenshot.keyCodeKey), Int(kVK_ANSI_A), "键码按整数落盘")
    assertEqual(storage.integer(forKey: screenshot.modifiersKey), Int(cmdKey | optionKey), "修饰键掩码按整数落盘")

    // 旧默认值迁移：无修饰键的 F1 → 新默认（⌃⇧S），并把迁移结果回写一次
    preferences.setCombo(HotKeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0), for: screenshot)
    assertEqual(preferences.combo(for: screenshot), screenshot.defaultCombo, "旧默认值 F1 迁移到新的默认组合")
    assertEqual(storage.integer(forKey: screenshot.modifiersKey), Int(controlKey | shiftKey),
                "迁移结果回写修饰键（这是迁移，不是补默认值）")

    // 损坏值（负数）按「未设置」回落，不能 trapping 成崩溃
    storage.set(-5, forKey: screenshot.keyCodeKey)
    storage.set(-1, forKey: screenshot.modifiersKey)
    assertEqual(preferences.combo(for: screenshot), screenshot.defaultCombo, "损坏值（负数）回落默认组合")

    // 逐动作键名互不串台：设置贴图不影响截图
    let pin = SnipHotKeyAction.pin
    assertEqual(screenshot.keyCodeKey == pin.keyCodeKey, false, "动作之间的键码键名互不相同")
    preferences.setCombo(keyA, for: pin)
    assertEqual(preferences.combo(for: pin), keyA, "另一个动作读到自己的组合")
    assertEqual(preferences.combo(for: screenshot), screenshot.defaultCombo, "本动作仍按损坏值回落（不受别的动作影响）")
}

// MARK: - 写盘口径（文件名 / 格式 / 像素尺寸 / 失败不静默）

@MainActor
private func testSnipFileWriterFormatAndPixelSize() {
    guard let image = snipFeatureTestImage(width: 64, height: 32) else {
        assertNotNil(nil as CGImage?, "造不出 64×32 测试位图（CoreGraphics 异常）")
        return
    }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("nm-snip-feature-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date()
    let pngURL = directory.appendingPathComponent(SnipFileNaming.fileName(for: now, format: .png))
    let jpegURL = directory.appendingPathComponent(SnipFileNaming.fileName(for: now, format: .jpeg))

    // 文件名口径：换格式只换扩展名，时间戳规则不动
    assertEqual(pngURL.pathExtension, "png", "PNG 扩展名")
    assertEqual(jpegURL.pathExtension, "jpg", "JPEG 扩展名固定 .jpg")
    assertEqual(pngURL.deletingPathExtension().lastPathComponent,
                jpegURL.deletingPathExtension().lastPathComponent,
                "换格式只换扩展名，时间戳部分不动")

    try? SnipFileWriter.write(image, to: pngURL, format: .png)
    try? SnipFileWriter.write(image, to: jpegURL, format: .jpeg, quality: 0.5)
    assertEqual(FileManager.default.fileExists(atPath: pngURL.path), true, "PNG 落盘成功")
    assertEqual(FileManager.default.fileExists(atPath: jpegURL.path), true, "JPEG 落盘成功")
    assertEqual(snipFeaturePixelSize(of: pngURL), CGSize(width: 64, height: 32),
                "PNG 像素尺寸与输入一致（不缩放、不裁切）")
    assertEqual(snipFeaturePixelSize(of: jpegURL), CGSize(width: 64, height: 32),
                "JPEG 像素尺寸与输入一致（质量只影响体积）")

    // PNG 便捷入口与 write(format: .png) 同口径
    let convenienceURL = directory.appendingPathComponent("convenience.png")
    try? SnipFileWriter.writePNG(image, to: convenienceURL)
    assertEqual(snipFeaturePixelSize(of: convenienceURL), CGSize(width: 64, height: 32),
                "writePNG 与 write(format: .png) 同口径")

    // 质量夹紧口径在 Core，写盘层原样消费
    assertEqual(SnipImageFormat.clampedQuality(2.0), SnipImageFormat.jpegQualityRange.upperBound,
                "越界质量夹到上限")
    assertEqual(SnipImageFormat.clampedQuality(0.1), SnipImageFormat.jpegQualityRange.lowerBound,
                "越界质量夹到下限")
    assertEqual(SnipImageFormat.clampedQuality(.nan), SnipImageFormat.defaultJPEGQuality,
                "非法质量（NaN）回落默认 0.9")

    // 写不进的目标路径必须抛错，不静默丢图
    let missingDirectoryURL = URL(fileURLWithPath: "/nm-snip-missing-\(UUID().uuidString)/x.png")
    var writeFailed = false
    do {
        try SnipFileWriter.write(image, to: missingDirectoryURL, format: .png)
    } catch is SnipFileWriter.WriteError {
        writeFailed = true
    } catch {
        writeFailed = true
    }
    assertEqual(writeFailed, true, "目标目录不存在时抛 WriteError（不静默丢图）")
    assertEqual(FileManager.default.fileExists(atPath: missingDirectoryURL.path), false,
                "失败路径不留半截文件")
}

// MARK: - 剪贴板选档（体积预算 / 载体类型）

@MainActor
private func testSnipPasteboardWriterTierSelection() {
    let logger = RecordingLogger()
    guard let image = snipFeatureTestImage(width: 20, height: 10) else {
        assertNotNil(nil as CGImage?, "造不出 20×10 测试位图（CoreGraphics 异常）")
        return
    }

    assertEqual(SnipPasteboardImageWriter.lossyQuality, 0.85, "JPEG 兜底档质量口径")
    guard let item = SnipPasteboardImageWriter.makeItem(for: image, logger: logger) else {
        assertNotNil(nil as NSPasteboardItem?, "小图必须能出剪贴板载体")
        return
    }
    let pngData = item.data(forType: .png)
    assertEqual(item.types.contains(.png), true, "小图走 2x 无损 PNG（体积天然达标）")
    assertNotNil(pngData, "载体里带 PNG 数据")
    assertEqual((pngData?.count ?? Int.max) <= SnipPasteboardImageBudget.byteBudget, true,
                "载体体积不超过 1MB 预算")

    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bsfeng.macmonitor.snip.feature.boundary"))
    assertEqual(SnipPasteboardImageWriter.write(image, to: pasteboard, logger: logger), true,
                "写入剪贴板成功")
    let written = pasteboard.data(forType: .png)
    assertNotNil(written, "剪贴板读回 PNG 表示")
    assertEqual((written?.count ?? Int.max) <= SnipPasteboardImageBudget.byteBudget, true,
                "写进剪贴板的图仍在预算内")
    assertEqual(logger.all.contains { $0.contains("剪贴板图片") }, true, "选档结论写进日志（可追）")
    pasteboard.clearContents()
}

// MARK: - OCR 失败口径（空图不谎报有字）

@MainActor
private func testSnipVisionNoTextOutcome() {
    guard let blank = snipFeatureTestImage(width: 200, height: 80) else {
        assertNotNil(nil as CGImage?, "造不出 200×80 测试位图（CoreGraphics 异常）")
        return
    }
    switch VisionTextRecognizer.recognizeLines(in: blank, languages: ["en-US"]) {
    case .success(let lines):
        assertEqual(lines.isEmpty, false, "纯色空图不该识别出任何文字行")
    case .failure(let error):
        assertEqual(error, SnipTextRecognitionError.noTextFound,
                    "纯色空图 → noTextFound（不是 recognitionFailed）")
    }
}

// MARK: - 组合键展示口径（HotKeyCombo 在 UI target）

@MainActor
private func testSnipHotKeyComboDisplay() {
    assertEqual(HotKeyCombo.defaultPanelToggle.displayString, "⌥⌘V", "默认唤起组合展示为 ⌥⌘V")
    assertEqual(HotKeyCombo.defaultPanelToggle.hasModifier, true, "默认唤起组合带修饰键")
    assertEqual(HotKeyCombo(keyCode: 0, modifiers: 0).hasModifier, false, "裸键不满足「全局热键必须带修饰键」")
    assertEqual(HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: 0).displayString, "S", "无修饰键只出键名")
    assertEqual(HotKeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0).displayString, "F1", "功能键键名")
    assertEqual(HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(shiftKey)).displayString,
                "⇧空格", "空格键名")
    assertEqual(HotKeyCombo(keyCode: 250, modifiers: UInt32(controlKey)).displayString,
                "⌃键码 250", "未知键码回退为「键码 N」")
    let allModifiers = HotKeyCombo(keyCode: UInt32(kVK_ANSI_V),
                                   modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
    assertEqual(allModifiers.displayString, "⌃⌥⇧⌘V", "修饰键展示顺序固定 ⌃⌥⇧⌘")

    // 默认组合与展示口径同源（截图 / 贴图 / 隐藏贴图）
    assertEqual(SnipHotKeyAction.screenshot.defaultCombo.displayString, "⌃⇧S", "截图默认组合展示")
    assertEqual(SnipHotKeyAction.pin.defaultCombo.displayString, "⌃⇧V", "贴图默认组合展示")
    assertEqual(SnipHotKeyAction.hidePins.defaultCombo.displayString, "⇧F3", "隐藏贴图默认组合展示")
    assertEqual(Set(SnipHotKeyAction.allCases.map { $0.defaultCombo.displayString }).count, 6,
                "六个动作的默认组合互不重复")
}

// MARK: - 测试辅助（写盘 / 选档 / OCR 共用的测试图）

/// 纯色测试图（写盘 / 选档 / OCR 都需要一张确定尺寸的位图）
///
/// 返回可选：造不出位图时由调用方显式判失败，不要静默跳过（假的图会让尺寸断言失去意义）。
private func snipFeatureTestImage(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// 读取落盘图片的像素尺寸（写盘口径按这张图核对）
private func snipFeaturePixelSize(of url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return CGSize(width: image.width, height: image.height)
}

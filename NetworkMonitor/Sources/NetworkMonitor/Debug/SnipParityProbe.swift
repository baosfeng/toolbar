#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 截图补差取证（仅 DEBUG）

/// 本轮补差（OCR / 序号）的真实链路取证，两个独立入口：
///
/// 1. OCR：`NM_SNIP_OCR_PROBE=<输入 PNG> [NM_SNIP_OCR_PROBE_OUT=<输出 txt>] <可执行>`
///    走生产链路（VisionTextRecognizer + SnipTextRecognition.plainText），打印行数/字数并把文本落盘。
/// 2. 序号：`NM_SNIP_NUMBER_PROBE=1 <可执行>`
///    造一张底图 + 三个序号标注，走生产链路（SnipAnnotationComposer.compose）落盘成 PNG，
///    用来核对圆底数字的居中、粗细与多位数缩放。
@MainActor
enum SnipParityProbe {

    static let ocrInputEnvKey = "NM_SNIP_OCR_PROBE"
    static let ocrOutputEnvKey = "NM_SNIP_OCR_PROBE_OUT"
    static let numberEnvKey = "NM_SNIP_NUMBER_PROBE"

    static let numberOutputPath = "/tmp/nm-snip-number-probe.png"
    static let ocrDemoInputPath = "/tmp/nm-ocr-demo-input.png"

    static var isOCRRequested: Bool {
        ProcessInfo.processInfo.environment[ocrInputEnvKey]?.isEmpty == false
    }

    static var isNumberRequested: Bool {
        ProcessInfo.processInfo.environment[numberEnvKey] != nil
    }

    static func runIfRequested() {
        if isOCRRequested { runOCR() }
        if isNumberRequested { runNumber() }
    }

    // MARK: OCR

    private static func runOCR() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[ocrInputEnvKey], !path.isEmpty else { return }
        // path == "demo"：自造一张中英混排文字图（可公开取证，不涉及用户屏幕内容）
        let isDemo = path == "demo"
        guard let image = isDemo ? makeTextImage() : loadImage(path) else {
            print("ocr probe: 读不到输入图 \(path)")
            exit(2)
        }
        if isDemo {
            try? SnipDemo.saveImage(image, to: ocrDemoInputPath)
            print("ocr probe: 已生成演示输入图 \(ocrDemoInputPath)")
        }
        let payload = SnipTextRecognitionImage(image: image)
        Task { @MainActor in
            do {
                let lines = try await VisionTextRecognizer().recognize(in: payload)
                let text = SnipTextRecognition.plainText(from: lines)
                print("ocr probe: \(lines.count) 行 / \(text.count) 字")
                print("ocr probe: 前 3 行 =", SnipTextRecognition.acceptedLines(lines).prefix(3))
                if let output = environment[ocrOutputEnvKey], !output.isEmpty {
                    try? text.write(toFile: output, atomically: true, encoding: .utf8)
                    print("ocr probe: 已写入 \(output)")
                }
            } catch {
                print("ocr probe error: \(error)")
                exit(3)
            }
            exit(0)
        }
    }

    // MARK: 序号

    private static func runNumber() {
        Task { @MainActor in
            let size = CGSize(width: 420, height: 220)
            guard let base = makeBase(size: size) else { exit(2) }
            var style = SnipAnnotationStyle()
            style.color = .red
            style.lineWidth = 4
            let annotations = [1, 2, 3].enumerated().map { index, value -> SnipAnnotation in
                let center = CGPoint(x: 70 + CGFloat(index) * 110, y: 110)
                let radius = SnipNumberAnnotation.radius(forLineWidth: index == 2 ? 8 : 4)
                return SnipAnnotation(kind: .number,
                                      start: CGPoint(x: center.x - radius, y: center.y - radius),
                                      end: CGPoint(x: center.x + radius, y: center.y + radius),
                                      text: String(value),
                                      style: style)
            }
            guard let composed = SnipAnnotationComposer.compose(base: base,
                                                               cropRect: CGRect(origin: .zero, size: size),
                                                               annotations: annotations,
                                                               selectionOrigin: .zero,
                                                               scale: 1) else {
                print("number probe: 合成失败")
                exit(3)
            }
            do {
                try SnipDemo.saveImage(composed, to: numberOutputPath)
                print("number probe: 已写入 \(numberOutputPath)（\(composed.width)×\(composed.height)）")
            } catch {
                print("number probe error: \(error)")
                exit(4)
            }
            exit(0)
        }
    }

    private static func makeBase(size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return nil }
        context.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// 中英混排演示图：白底深字两行，用来验证「语言自动」与阅读顺序
    private static func makeTextImage() -> CGImage? {
        let size = CGSize(width: 720, height: 200)
        guard let base = makeBase(size: size),
              let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                          | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(origin: .zero, size: size))
        // CoreText 原点在左下：这里直接给基线坐标，两行分别 y = 150 / 60
        let lines: [(String, CGFloat, CGFloat)] = [
            ("OCR 自证：识别中文与 English", 150, 30),
            ("第二行 number 42 · 序号一 二 三", 60, 26),
        ]
        for (text, baselineY, pointSize) in lines {
            let font = CTFontCreateWithName("PingFang SC" as CFString, pointSize, nil)
            let color = CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            let attributed = NSAttributedString(string: text, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 40, y: baselineY)
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }

    private static func loadImage(_ path: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
#endif

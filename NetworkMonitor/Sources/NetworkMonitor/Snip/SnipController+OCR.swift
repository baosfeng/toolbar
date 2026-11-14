import AppKit
import NetworkMonitorCore

// MARK: - OCR 文字识别（选区 → 文字）

/// 选区 → 文字：合成当前选区（含标注，所见即所得）→ Vision 识别 → 剪贴板文本
///
/// 两条出口（与 sniplite / Snipaste 的口径一致）：
/// 1. 默认：识别结果写入剪贴板（纯文本），并收起覆盖层；
/// 2. 偏好「识别后贴图」打开时，额外把文字渲染成一张贴图钉在屏幕上（对照看更方便）。
///
/// 线程：识别在后台（VisionTextRecognizer 是非隔离 async，函数体在通用执行器上跑），
/// 本类为 @MainActor，await 之后回到主线程再改剪贴板与界面；重复触发用 isRecognizing 挡住。
extension SnipController {

    /// 对覆盖层里的选区做识别
    func recognizeText(in view: SnipOverlayView, localRect: CGRect) {
        guard !isRecognizing else {
            logger.info("已有一次识别在进行，忽略重复触发")
            return
        }
        guard let target = resolve(capturedFor: view, localRect: localRect),
              let image = composedImage(captured: target.captured,
                                        globalRect: target.globalRect,
                                        annotations: view.annotationsForComposition) else {
            fail(message: "识别失败：选区图像不可用")
            return
        }
        isRecognizing = true
        logger.info("开始识别文字：\(Int(target.globalRect.width))×\(Int(target.globalRect.height))")
        let payload = SnipTextRecognitionImage(image: image)
        Task { [weak self] in
            guard let self else { return }
            do {
                let lines = try await self.textRecognizer.recognize(in: payload)
                self.isRecognizing = false
                self.handleRecognizedLines(lines)
            } catch let error as SnipTextRecognitionError {
                self.isRecognizing = false
                self.fail(message: Self.recognitionFailureText(error))
            } catch {
                self.isRecognizing = false
                self.fail(message: "识别失败：\(error.localizedDescription)")
            }
        }
    }

    /// 识别成功：写剪贴板 →（可选）贴文字图 → 轻提示 → 收起覆盖层
    private func handleRecognizedLines(_ lines: [SnipTextLine]) {
        let text = SnipTextRecognition.plainText(from: lines)
        guard !text.isEmpty else {
            fail(message: "没有识别到文字（可试着放大选区或换一张更清晰的截图）")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("识别完成：\(lines.count) 行 / \(text.count) 字，已复制到剪贴板")
        if storage.bool(forKey: SnipPreferenceKey.ocrPinResult) {
            pinRecognizedText(text)
        }
        SnipHintWindow.show("已识别 \(lines.count) 行文字，已复制")
        dismissOverlays()
    }

    /// 失败原因的可读文案（无文字 / 图不可用 / 框架报错三种）
    static func recognitionFailureText(_ error: SnipTextRecognitionError) -> String {
        switch error {
        case .noTextFound:
            return "没有识别到文字（可试着放大选区或换一张更清晰的截图）"
        case .imageUnavailable:
            return "识别失败：选区图像不可用"
        case .recognitionFailed(let detail):
            return "识别失败：\(detail)"
        }
    }
}

// MARK: - 覆盖层回调

extension SnipController {

    /// 覆盖层请求识别（⌘O / 工具条「更多 → 识别文字」/ 选中该工具后点选区）
    func overlayView(_ view: SnipOverlayView, didRequestTextRecognition rect: CGRect) {
        recognizeText(in: view, localRect: rect)
    }
}

import Foundation
import NetworkMonitorCore
import Vision

// MARK: - Vision 文字识别

/// OCR 实现 —— Vision VNRecognizeTextRequest（accurate 档，中英自动检测）
///
/// 线程：方法无 actor 隔离，async 调用时函数体在通用执行器上跑（Swift 6 的非隔离 async 语义），
/// Vision 的同步 perform 因此不会卡主线程；返回的 SnipTextLine 是 Sendable 值类型。
/// 语言：开启 automaticallyDetectsLanguage（macOS 13+）并给出中英候选，
/// 中英混排的界面截图不需要用户先选语言。
/// 可跨线程共享：内部只有注入的日志器与不可变语言表，每次识别各建一个 VNImageRequestHandler。
final class VisionTextRecognizer: SnipTextRecognizing, @unchecked Sendable {

    private let logger: LoggingService
    /// 语言候选：自动检测开启时作为先验，检测不可用时仍能识别中英
    private let languages = ["zh-Hans", "en-US"]

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    func recognize(in image: SnipTextRecognitionImage) async throws -> [SnipTextLine] {
        let lines = Self.recognizeLines(in: image.image, languages: languages)
        switch lines {
        case .success(let value):
            logger.debug("OCR 识别到 \(value.count) 行")
            return value
        case .failure(let error):
            throw error
        }
    }

    /// 同步识别 —— 与 Vision 的同步 API 一一对应，便于单独验证与日志
    static func recognizeLines(in image: CGImage,
                               languages: [String]) -> Result<[SnipTextLine], SnipTextRecognitionError> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .failure(.recognitionFailed(error.localizedDescription))
        }
        // request.results 已是 [VNRecognizedTextObservation]?：再写 as? 条件转换是冗余的，
        // 会触发「conditional downcast does nothing」告警（编译告警基线为 0 条）
        let observations = request.results ?? []
        let lines: [SnipTextLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return SnipTextLine(text: candidate.string,
                                confidence: Double(candidate.confidence),
                                normalizedTop: Double(box.midY),
                                normalizedLeft: Double(box.minX))
        }
        guard !lines.isEmpty else { return .failure(.noTextFound) }
        return .success(lines)
    }
}

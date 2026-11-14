import CoreGraphics
import Foundation

// MARK: - 文字识别协议

/// OCR 服务 —— 调用方只依赖协议，实现在可执行 target（VisionTextRecognizer）
///
/// 线程约定：方法声明为 async 且实现侧不做 actor 隔离，Swift 6 会把函数体放到通用执行器上，
/// Vision 的同步识别因此天然不在主线程；调用方（SnipController，@MainActor）await 后回到主线程，
/// 直接改剪贴板与界面状态即可。
public protocol SnipTextRecognizing: AnyObject, Sendable {
    /// 识别一张图里的文字；无可识别文字时抛 .noTextFound
    func recognize(in image: SnipTextRecognitionImage) async throws -> [SnipTextLine]
}

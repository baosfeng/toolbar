import AppKit
import NetworkMonitorCore

// MARK: - 图片采集的后台结算（从 PasteboardWatcher 拆出，守住单文件体积上限）

/// `PasteboardWatcher` 的图片结算部分 —— 主线程只交字节，其余都在 `ClipboardImagePipeline` 里
///
/// 拆文件原因：采集主文件贴着 15 KiB 上限，而「后台结算 + draft 组装」是一段自成体系的
/// 异步逻辑，独立成文件更清晰。跨文件访问：`logger` / `onCapture` / `DelayedImage`
/// 由主文件的 private 放宽为 internal。
extension PasteboardWatcher {

    /// 主线程只交字节，哈希 / 落盘 / 缩略图 / 编码都在后台流水线里（见 ClipboardImagePipeline）
    func submitImage(_ request: ImageRequest) {
        let logger = logger
        Task { [weak self] in
            guard let result = await ClipboardImagePipeline.shared.process(data: request.data,
                                                                          logger: logger) else { return }
            self?.deliver(imageResult: result, request: request)
        }
    }

    /// 回主线程产出 draft：成功走已落盘路径，像素守卫拒绝走占位降级（与旧同步路径同文案）
    ///
    /// 顺序由 `ClipboardImagePipeline`（actor）保证：连续两次复制按到达顺序结算，
    /// 不会出现「后复制的先落库」把列表顺序打乱。
    func deliver(imageResult: ClipboardImagePipeline.Result, request: ImageRequest) {
        let draft: ClipboardDraft
        switch imageResult.outcome {
        case .stored(let stored):
            draft = ClipboardDraft(kind: .image,
                                   contentHash: imageResult.contentHash,
                                   preview: "图片 \(stored.width)×\(stored.height)",
                                   imagePath: stored.path,
                                   imageWidth: stored.width,
                                   imageHeight: stored.height,
                                   sourceBundleID: request.bundleID,
                                   sourceAppName: request.appName,
                                   createdAt: request.now)
        case .rejected(let rejection):
            // 占位降级：图太大（或不合法）时只记尺寸与提示，绝不落盘、不缓存
            draft = ClipboardDraft(kind: .image,
                                   contentHash: imageResult.contentHash,
                                   preview: rejection.placeholderPreview,
                                   imagePath: nil,
                                   imageWidth: rejection.width,
                                   imageHeight: rejection.height,
                                   sourceBundleID: request.bundleID,
                                   sourceAppName: request.appName,
                                   createdAt: request.now)
        case nil:
            return
        }
        onCapture?(draft)
    }
}

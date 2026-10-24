import CoreGraphics

// MARK: - 带底图的标注合成

/// 统一渲染入口 — 普通图元交给渲染器，马赛克 / 模糊从底图取像素
///
/// 调用方须保证当前 CTM 已按「左上原点、单位点」设置，
/// 且 baseOrigin 是底图左上角在当前坐标系里的位置。
public enum SnipAnnotationCompositor {

    public static func draw(annotations: [SnipAnnotation],
                            base: CGImage,
                            baseOrigin: CGPoint,
                            scale: CGFloat,
                            in context: CGContext) {
        for annotation in annotations {
            if annotation.kind.needsBaseImage {
                drawPixelEffect(annotation,
                                base: base,
                                baseOrigin: baseOrigin,
                                scale: scale,
                                in: context)
            } else {
                SnipAnnotationRenderer.draw(annotation, in: context)
            }
        }
    }

    private static func drawPixelEffect(_ annotation: SnipAnnotation,
                                        base: CGImage,
                                        baseOrigin: CGPoint,
                                        scale: CGFloat,
                                        in context: CGContext) {
        let rect = annotation.boundingRect
        guard rect.width >= 2, rect.height >= 2 else { return }
        // 本地点 → 底图像素
        let pixelRect = CGRect(x: (rect.minX - baseOrigin.x) * scale,
                               y: (rect.minY - baseOrigin.y) * scale,
                               width: rect.width * scale,
                               height: rect.height * scale)
        let imageSize = CGRect(x: 0, y: 0, width: CGFloat(base.width), height: CGFloat(base.height))
        let clamped = pixelRect.integral.intersection(imageSize)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return }

        let processed: CGImage?
        switch annotation.kind {
        case .mosaic:
            processed = SnipMosaicProcessor.pixelated(base, in: clamped)
        case .blur:
            processed = SnipMosaicProcessor.blurred(base, in: clamped)
        default:
            processed = nil
        }
        guard let processed else { return }

        // 目标矩形回到点坐标（只画与底图相交的那块）
        let target = CGRect(x: clamped.minX / scale + baseOrigin.x,
                            y: clamped.minY / scale + baseOrigin.y,
                            width: clamped.width / scale,
                            height: clamped.height / scale)
        context.saveGState()
        context.interpolationQuality = annotation.kind == .mosaic ? .none : .default
        context.draw(processed, in: target)
        context.restoreGState()
    }
}

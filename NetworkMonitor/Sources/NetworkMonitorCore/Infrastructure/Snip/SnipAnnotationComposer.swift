import CoreGraphics

// MARK: - 标注合成导出

/// 把标注烧进裁剪后的图里 — 复制 / 保存 / 贴图都走这里
public enum SnipAnnotationComposer {

    /// - Parameters:
    ///   - base: 全屏捕获图（像素）
    ///   - cropRect: 选区在捕获图中的像素矩形
    ///   - annotations: 标注（屏幕本地点坐标，左上原点）
    ///   - selectionOrigin: 选区在屏幕中的点坐标（左上角）
    ///   - scale: 点 → 像素的缩放比
    public static func compose(base: CGImage,
                               cropRect: CGRect,
                               annotations: [SnipAnnotation],
                               selectionOrigin: CGPoint,
                               scale: CGFloat) -> CGImage? {
        guard let cropped = base.cropping(to: cropRect) else { return nil }
        let width = cropped.width
        let height = cropped.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = cropped.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        // 底图按默认（左下原点）绘制，交给系统处理摆放
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard !annotations.isEmpty else {
            return context.makeImage()
        }

        // 标注坐标系：左上原点、单位为点，平移到选区局部
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -selectionOrigin.x, y: -selectionOrigin.y)
        SnipAnnotationCompositor.draw(annotations: annotations,
                                      base: base,
                                      baseOrigin: selectionOrigin,
                                      scale: scale,
                                      in: context)
        return context.makeImage()
    }
}

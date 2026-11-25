import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 像素效果偏好的读写

/// 马赛克 / 模糊强度与偏好键之间的翻译
///
/// 两个键分开存：缺键要能各自回落（老用户两键全缺 → 沿用 14/14，观感零变化），
/// 而合成成一根字符串会让「只调过马赛克」的用户在升级后连模糊也被改写。
public enum SnipEffectStylePreference {

    /// 从存储读出效果强度
    public static func load(storage: any KeyValueStorage) -> SnipEffectStyle {
        let mosaic = (storage.object(forKey: SnipPreferenceKey.annotationMosaicBlock) as? Double)
            .map { CGFloat($0) } ?? SnipEffectStyle.defaultMosaicBlock
        let blur = (storage.object(forKey: SnipPreferenceKey.annotationBlurRadius) as? Double)
            .map { CGFloat($0) } ?? SnipEffectStyle.defaultBlurRadius
        return SnipEffectStyle(mosaicBlock: mosaic, blurRadius: blur)
    }

    /// 写回存储（夹取已在 SnipEffectStyle 的 init 里做过）
    public static func save(_ style: SnipEffectStyle, storage: any KeyValueStorage) {
        storage.set(Double(style.mosaicBlock), forKey: SnipPreferenceKey.annotationMosaicBlock)
        storage.set(Double(style.blurRadius), forKey: SnipPreferenceKey.annotationBlurRadius)
    }
}

import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 文字样式偏好读写

/// 文字样式（字号 / 加粗 / 字体族）与偏好键之间的翻译
///
/// 三个键分开存而不是打包成一个字符串：缺键语义要能各自回落
/// （老用户三键全缺 → 沿用旧口径「字号由线宽推导」，行为零变化）。
public enum SnipTextStylePreference {

    /// 从存储读出文字样式
    ///
    /// - 字号缺键 → nil（沿用旧口径「由线宽推导」）
    /// - 加粗缺键 → false
    /// - 字体族缺键或取值非法 → 默认族
    public static func load(storage: any KeyValueStorage) -> SnipTextStyle {
        let rawSize = (storage.object(forKey: SnipPreferenceKey.annotationTextFontSize) as? Double)
            .map { CGFloat($0) }
        let fontSize = rawSize.map { SnipTextStyle.clampFontSize($0) }
        let bold = storage.bool(forKey: SnipPreferenceKey.annotationTextBold)
        let family = SnipTextFamily(rawValue: storage.string(forKey: SnipPreferenceKey.annotationTextFamily) ?? "")
            ?? .system
        return SnipTextStyle(fontSize: fontSize, bold: bold, family: family)
    }

    /// 把文字样式写回存储
    ///
    /// 只在字号有值时才写字号键：用户从没调过字号时不该平白多出一个键，
    /// 否则「老偏好零迁移」的判据会被自己破坏。
    public static func save(_ style: SnipTextStyle,
                            storage: any KeyValueStorage) {
        if let fontSize = style.fontSize {
            storage.set(Double(SnipTextStyle.clampFontSize(fontSize)),
                        forKey: SnipPreferenceKey.annotationTextFontSize)
        }
        storage.set(style.bold, forKey: SnipPreferenceKey.annotationTextBold)
        storage.set(style.family.rawValue, forKey: SnipPreferenceKey.annotationTextFamily)
    }
}

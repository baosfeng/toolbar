import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureSnip

// MARK: - 覆盖层的偏好灌值

/// 把与「覆盖层行为」相关的偏好一次性灌进本次截图的全部覆盖层
///
/// 这些偏好不属于标注样式（那是颜色 / 线宽 / 字号那一组），而是**覆盖层本身怎么响应**：
/// 滚轮能不能调数值、操作提示要不要再显示。
///
/// 单独成文件的理由：`SnipController` 族只允许变小。摘出来之后，
/// 「新增一个覆盖层级偏好」只改这一个文件 + 一个偏好键，不碰编排主文件。
enum OverlayPreferences {

    /// 滚轮调数值的总开关（缺键即开：老用户升级后行为不变）
    static func scrollAdjustEnabled(storage: any KeyValueStorage) -> Bool {
        (storage.object(forKey: SnipPreferenceKey.scrollAdjustEnabled) as? Bool) ?? true
    }

    /// 标注操作提示是否已经看过（缺键 = 没看过）
    static func hintsShown(storage: any KeyValueStorage) -> Bool {
        storage.bool(forKey: SnipPreferenceKey.annotationHintsShown)
    }

    /// 把上面几项灌进覆盖层，并装好玩过之后回写偏好的回调
    ///
    /// 回写走弱引用 self 的 closure：编排层比覆盖层活得久，覆盖层消失后回调不该再持有它。
    @MainActor
    static func apply(to overlays: [SnipOverlayWindow],
                      storage: any KeyValueStorage,
                      logger: any LoggingService) {
        let enabled = scrollAdjustEnabled(storage: storage)
        let shown = hintsShown(storage: storage)
        for window in overlays {
            window.overlayView.scrollAdjustEnabled = enabled
            window.overlayView.hints.alreadyShown = shown
            window.overlayView.onHintsShown = { [weak storage] in
                guard let storage else { return }
                storage.set(true, forKey: SnipPreferenceKey.annotationHintsShown)
                logger.info("标注操作提示已展示，后续截图不再出现")
            }
        }
    }
}

import Foundation
import NetworkMonitorCore

// MARK: - 贴图默认透明度

/// PinDefaultAlphaResolver 的契约：设置页写的键就是贴图窗读的键，缺键 / 越界都收敛到合法区间
func runPinDefaultAlphaTests() {
    print("🧪 Testing pin default alpha...")

    // 隔离存储：不碰本机偏好，也不依赖 UserDefaults 的跨用例残留
    let storage = InMemoryStorage()

    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 1,
                "缺键回落满不透明，老用户升级后贴图外观不变")

    storage.set(0.5, forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha)
    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 0.5, "设置页写入的值原样读回")

    storage.set(2.0, forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha)
    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 1, "超过上限钳制到 1")

    storage.set(0.1, forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha)
    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 0.3, "低于下限钳制到 0.3")

    storage.set(0.3, forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha)
    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 0.3, "下限本身合法，不被再钳制")

    storage.set("0.5", forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha)
    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 1, "非数值按缺键处理，不崩也不猜")

    storage.set(Double.nan, forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha)
    assertEqual(PinDefaultAlphaResolver.load(storage: storage), 1, "NaN 不参与钳制，回落默认")
}

import Foundation

// MARK: - 外观偏好（主题 / 玻璃 / 渲染帧率档）

/// 外观偏好 — 收敛全部键名与默认值，读写一律走注入的 `KeyValueStorage`
///
/// 三个键各自独立：
/// - 主题：唯一决定面系与玻璃配方（见 `ThemeCatalog`）
/// - 渲染档：决定刷新节拍 / 动效 / 玻璃默认开关 / 图表重采样上限（见 `RenderTierLogic`）
/// - 玻璃显式开关：**只在用户手动动过时存在**；不存在表示「跟随档位」
///
/// 玻璃之所以要多一个「显式」标记：省电档要默认关玻璃，但用户手动打开后再切回省电档
/// 不应该又把人家刚开的开关关掉——所以用户手动值优先，没设过才看档位。
public final class AppearancePreferences: Sendable {

    private enum Key {
        static let theme = "appearance.theme"
        static let renderTier = "appearance.renderTier"
        static let glassOverride = "appearance.glassOverride"
    }

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    // MARK: - 主题

    /// 当前主题 id；缺键或非法值回落 Apple（默认档）
    public var themeID: ThemeID {
        get { ThemeID.resolved(fromRaw: storage.string(forKey: Key.theme) ?? "") }
        set { storage.set(newValue.rawValue, forKey: Key.theme) }
    }

    /// 当前主题定义
    public var theme: Theme { ThemeCatalog.theme(for: themeID) }

    // MARK: - 渲染帧率档

    /// 当前档位；缺键或非法值回落标准档
    public var renderTier: RenderTier {
        get { RenderTier.resolved(fromRaw: storage.string(forKey: Key.renderTier) ?? "") }
        set { storage.set(newValue.rawValue, forKey: Key.renderTier) }
    }

    /// 当前档位展开后的参数表
    public var renderProfile: RenderTierProfile { RenderTierLogic.profile(for: renderTier) }

    // MARK: - 玻璃

    /// 用户显式设定的玻璃开关；nil = 没动过，跟随档位
    public var glassOverride: Bool? {
        get {
            guard let raw = storage.object(forKey: Key.glassOverride) else { return nil }
            _ = raw
            return storage.bool(forKey: Key.glassOverride)
        }
        set {
            guard let newValue else {
                storage.removeObject(forKey: Key.glassOverride)
                return
            }
            storage.set(newValue, forKey: Key.glassOverride)
        }
    }

    /// 玻璃实际是否生效（用户显式值优先，否则看档位）
    public var glassEnabled: Bool {
        RenderTierLogic.effectiveGlass(override: glassOverride, tier: renderTier)
    }

    /// 恢复默认：清掉三个键，回到 Apple + 标准档 + 玻璃跟随档位
    public func reset() {
        storage.removeObject(forKey: Key.theme)
        storage.removeObject(forKey: Key.renderTier)
        storage.removeObject(forKey: Key.glassOverride)
    }
}

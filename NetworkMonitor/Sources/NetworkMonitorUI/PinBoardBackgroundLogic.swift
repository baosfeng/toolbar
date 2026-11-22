import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 棋盘底偏好键

/// 贴图棋盘底的偏好键
///
/// 键名只在这里定义一次：贴图窗写、贴图窗读、测试断言共用，
/// 避免「写了一个键、读的是另一个键」这类「设了不生效」的故障。
public enum PinBoardPreferenceKey {
    /// 半透明贴图的棋盘底开关（缺键即关：老用户升级后外观与行为不变）
    public static let boardBackground = "pin.boardBackground"
}

// MARK: - 棋盘底判据（纯逻辑，可单测）

/// 「这张贴图该不该画棋盘底」
///
/// 两条都要满足：
/// 1. 用户打开了棋盘底开关（缺键即关，老用户零变化）；
/// 2. 这张图确实含透明像素 —— 全不透明的截图 / 照片画棋盘只会变成噪音。
///
/// 判据收在这里而不是贴图窗里：视图只按结果决定 `isHidden`，口径可被测试直接断言。
public enum PinBoardBackgroundResolver {

    /// 棋盘格边长（点）：8pt 在 Retina 上正好 16 物理像素，小而密，不抢内容
    public static let cellSize: CGFloat = 8

    /// 两档灰度 —— 只在这里出现一次，绘制与取证都读它
    public enum Tone {
        /// 浅格（白灰）
        public static let light: CGFloat = 0.98
        /// 深格（中灰）
        public static let dark: CGFloat = 0.82
    }

    /// 该贴图是否显示棋盘底
    ///
    /// - Parameters:
    ///   - enabled: 开关状态（偏好读出来的值）
    ///   - hasTransparentPixels: 图像是否含非全不透明像素（`SnipImageAlphaProbe`）
    public static func shouldDraw(enabled: Bool, hasTransparentPixels: Bool) -> Bool {
        enabled && hasTransparentPixels
    }

    /// 从存储读开关；缺键、非布尔值一律按关（老用户升级零变化）
    public static func isEnabled(storage: any KeyValueStorage) -> Bool {
        guard let raw = storage.object(forKey: PinBoardPreferenceKey.boardBackground) as? Bool else {
            return false
        }
        return raw
    }

    /// 写开关（右键菜单切一次就落盘，后续新建的贴图跟着走）
    public static func save(_ enabled: Bool, storage: any KeyValueStorage) {
        storage.set(enabled, forKey: PinBoardPreferenceKey.boardBackground)
    }

    /// 第 column / row 格是浅格还是深格（棋盘格的对角同色）
    ///
    /// 行列奇偶相同即浅格：与自绘视图里的循环判据同源，测试可以直接断言。
    public static func isLightCell(column: Int, row: Int) -> Bool {
        (column + row) % 2 == 0
    }

    /// 一格棋盘的行列数（结构体而非元组：元组不能直接进 assertEqual 的等值断言）
    public struct Grid: Equatable, Sendable {
        public let columns: Int
        public let rows: Int

        public init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
        }
    }

    /// 覆盖整个尺寸需要画的行列数（最后一格可能不满，按向上取整）
    public static func gridCount(for size: CGSize) -> Grid {
        guard size.width > 0, size.height > 0 else { return Grid(columns: 0, rows: 0) }
        return Grid(columns: Int((size.width / cellSize).rounded(.up)),
                    rows: Int((size.height / cellSize).rounded(.up)))
    }
}

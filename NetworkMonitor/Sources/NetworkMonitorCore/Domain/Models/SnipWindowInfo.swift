import CoreGraphics

// MARK: - 窗口层级

/// 窗口层级 — 直接对应 CGWindowList 的 kCGWindowLayer 原始值
///
/// 窗口检测只认下面这份**白名单**：显式列举参与检测的层级，其余层级一律不参与命中。
/// 白名单是显式列举，新增层级要到这里加一行，不会因为别处冒出别的数值就被静默收进结果集。
public enum SnipWindowLayer {

    /// 普通应用窗口（用户平日说的「窗口」）
    public static let normal: Int = 0
    /// 程序坞（Dock）— CGWindowList 里是**一个**整屏窗口，不是逐个图标
    public static let dock: Int = 20
    /// 菜单栏 — CGWindowList 里是**整条**菜单栏，不是逐个菜单项
    public static let menuBar: Int = 24
    /// 状态栏项（含自家菜单栏 App 的 popover）
    public static let statusItem: Int = 25
    /// 系统层级集合的边界：白名单里最高的那一层，供调试与测试核对
    public static let highestSupported: Int = statusItem
    /// 覆盖层量级的起点（screenSaver 及更高）；白名单不收这些层，仅用于自家进程兜底判断
    public static let overlayFloor: Int = 1000

    /// 系统层级（程序坞 / 菜单栏 / 状态栏项）— 尺寸不受 minimumSide 限制
    ///
    /// 状态栏项实测可能只有 30×24，用普通窗口的最小边长门槛会把它们全部滤掉；
    /// 菜单栏与程序坞虽然尺寸很大，但贴着屏幕边缘，也不该再走一遍尺寸判断。
    public static func isSystemLayer(_ layer: Int) -> Bool {
        layer == dock || layer == menuBar || layer == statusItem
    }

    /// 参与窗口检测的层级白名单 — 唯一判据，调用方与测试共用同一个函数
    public static func isSupported(_ layer: Int) -> Bool {
        layer == normal || isSystemLayer(layer)
    }
}

// MARK: - 窗口信息

/// 屏幕上的一个可检测窗口 — 全局 CG 坐标（左上原点，单位点）
public struct SnipWindowInfo: Equatable, Sendable {
    public let windowID: UInt32
    public let frame: CGRect
    public let ownerPID: Int32
    public let ownerName: String
    public let title: String
    /// CGWindowList 的原始层级，取值为 SnipWindowLayer 白名单之一
    public let layer: Int

    public init(windowID: UInt32,
                frame: CGRect,
                ownerPID: Int32,
                ownerName: String,
                title: String,
                layer: Int = SnipWindowLayer.normal) {
        self.windowID = windowID
        self.frame = frame
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.layer = layer
    }

    /// 面积，用于在嵌套窗口里取最小者
    public var area: CGFloat { frame.width * frame.height }
}

// MARK: - 窗口命中

/// 窗口命中判定 — 纯函数，便于单测
public enum SnipWindowHitTesting {

    /// 命中包含该点的最靠前窗口 — CGWindowList 已按前后序返回，取第一个命中者
    ///
    /// 不能按面积取最小：面积小的窗口可能在后面（例如被大窗口遮住的设置面板），
    /// 那样高亮的就不是用户眼睛看到的那个窗口。
    ///
    /// 唯一额外判据是程序坞：它在 CGWindowList 里是一个整屏窗口（本机实测 1512×982，
    /// 覆盖菜单栏以下的整块屏幕），不加限制的话屏幕任何位置都能命中它。
    /// 因此程序坞只在自己贴边的那条带子里算命中（见 isSelectable）；
    /// 带子内它仍按列表序优先 —— Dock 栏是浮在普通窗口之上的，视觉上本来就该先选它。
    public static func window(at point: CGPoint, in windows: [SnipWindowInfo]) -> SnipWindowInfo? {
        windows.first { $0.frame.contains(point) && isSelectable($0, at: point) }
    }

    /// 过滤出真正可检测的窗口 — 层级白名单 + 尺寸门槛
    ///
    /// - 层级：只收 SnipWindowLayer.isSupported 为真的层（0 / 20 / 24 / 25）
    /// - 尺寸：普通窗口要过 minimumSide（滤掉提示条、浮动条等辅助窗口）；
    ///   系统层级不受 minimumSide 限制，状态栏项才不会被当成「太小」丢掉
    /// - 自家进程：只有层级高到覆盖层量级（>= 1000）的自家窗口才排除。
    ///   自家普通窗口与自家 popover（层级 25）照常可识别 —— 用户能看到、能框选的东西
    ///   就该出现在结果里，否则「自己的详情页窗口识别不到」。
    ///
    /// 调用方注意：windowInfos() 在覆盖层创建**之前**执行（先列窗口再上屏），
    /// 那一刻屏幕上还没有自家覆盖层；覆盖层本身是 screenSaver（层级 1000）且不在白名单内，
    /// 所以这里的自家层级判断只是将来浮层变化时的兜底。
    public static func usable(windows: [SnipWindowInfo],
                              excludingPID: Int32,
                              minimumSide: CGFloat = 20) -> [SnipWindowInfo] {
        windows.filter { window in
            guard SnipWindowLayer.isSupported(window.layer) else { return false }
            guard window.ownerPID != excludingPID || !isAtOverlayLevel(window.layer) else { return false }
            guard !SnipWindowLayer.isSystemLayer(window.layer) else { return true }
            return window.frame.width >= minimumSide && window.frame.height >= minimumSide
        }
    }

    /// 覆盖层量级的层级（>= 1000，screenSaver 与更高）— 自家进程在这些层级不参与检测
    ///
    /// 判据收敛到这一个纯函数，调用方与测试共用；上限收敛在「自家进程」范围内，
    /// 不会误伤别的应用在同层级上的窗口。
    static func isAtOverlayLevel(_ layer: Int) -> Bool {
        layer >= SnipWindowLayer.overlayFloor
    }

    /// 程序坞窗口的贴边带宽（点）— 超出这条带子的程序坞窗口命中不算数
    ///
    /// 实测程序坞是 1512×982 的整屏容器（菜单栏以下的整块屏幕），它本身不含「图标位置」信息。
    /// Dock 栏实体会贴在屏幕某一条边上，带子按 Dock 最大高度（约 96 点）取，
    /// 既能覆盖停靠在任意一条边上的 Dock，又不至于把整块屏幕都算成程序坞。
    ///
    /// 已知一阶近似的局限：容器占满整块屏幕，所以左右两侧的窄条也会被算作程序坞，
    /// 即便用户把 Dock 停在底部。真实图标带位置要靠 Accessibility API 拿，本轮不做；
    /// 待办见任务说明「逐个 Dock 图标需要 Accessibility API」。
    public static let dockEdgeBand: CGFloat = 96

    /// 该窗口在这一点的命中是否成立 — 目前只有程序坞需要额外判据
    ///
    /// 只看屏幕的左 / 右 / 下三边：Dock 栏只会贴在这三条边上停靠，
    /// 顶边是菜单栏的地盘（整屏程序坞容器的顶边落在菜单栏下方，不算贴边方向）。
    public static func isSelectable(_ window: SnipWindowInfo, at point: CGPoint) -> Bool {
        guard window.layer == SnipWindowLayer.dock else { return true }
        let distances = [point.x - window.frame.minX,
                         window.frame.maxX - point.x,
                         window.frame.maxY - point.y]
        return distances.min() ?? .infinity <= dockEdgeBand
    }

    /// 单击选窗时真正成立的选区 — 普通窗口就是整窗，程序坞只取贴边的那一条
    ///
    /// 程序坞的窗口矩形是整块屏幕，直接用它当选区会截出满屏，用户点 Dock 图标却拿到
    /// 整屏图。这里按点所在的最近一条边裁出带宽为 dockEdgeBand 的带子，
    /// Dock 停靠在底部 / 左侧 / 右侧都能框出贴合的一条。
    public static func selectionFrame(for window: SnipWindowInfo, at point: CGPoint) -> CGRect {
        guard window.layer == SnipWindowLayer.dock else { return window.frame }
        var frame = window.frame
        let toLeft = point.x - frame.minX
        let toRight = frame.maxX - point.x
        let toBottom = frame.maxY - point.y
        if toBottom <= min(toLeft, toRight) {
            frame.origin.y = frame.maxY - dockEdgeBand
            frame.size.height = dockEdgeBand
        } else if toLeft <= toRight {
            frame.size.width = dockEdgeBand
        } else {
            frame.origin.x = frame.maxX - dockEdgeBand
            frame.size.width = dockEdgeBand
        }
        return frame
    }

}
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 菜单面板几何与开合

/// 菜单面板的定位与开关 — 全部「现查」，绝不写死坐标
///
/// 三条硬事实（均实测）：
/// 1. 状态项的屏幕 x 随上下行速率文字宽度变化（见过 1065 / 1075 / 1115），必须现读 `kAXPositionAttribute`；
/// 2. 面板是 `NSPanel`（nonactivating），不在 `AXWindows` 里，只有 CGWindowList 能拿到 bounds；
/// 3. 面板高度随当前 tab 内容变化（331 / 475 / 506 / 537 都见过），坐标换算必须每次重取。
enum PanelGeometry {

    /// 面板内 tab 条几何：左右各留 25pt、按 `tabNames.count` 等分剩余宽度、中心线距面板顶端 35pt
    ///
    /// 数值来自实测：面板宽 346pt 时高亮块宽 59.2pt、左右边距 25pt；
    /// 纵向 35pt 是「点得中」的实测值（20pt 落在色带边缘外，点了不切页）。
    static let horizontalInset: CGFloat = 25
    static let tabCenterOffsetY: CGFloat = 35

    /// 兜底 tab 名表（枚举里还有、用户可能打开的全集）
    ///
    /// **不要用它算坐标**：面板实际显示几段由用户的「分页可见性 + 排序」决定
    /// （实测就有只留 4 段的配置），写死数量会让等分坐标整体偏移、点到隔壁段。
    /// 真正的判据是 `visibleTabNames(of:)` —— 现读 AX 一级按钮的顺序，只有 AX 读不到时才回落到本表。
    static let tabNames = ["网络", "传送", "额度", "Token", "系统"]

    /// 面板当前**实际显示**的分页（顺序即屏幕上的左右顺序）
    ///
    /// AX 里分页按钮的 bounds 是脏值（恒为 0,954），所以只取顺序不取坐标：
    /// 坐标仍按「面板宽 − 左右内边距，按实际段数等分」现算。
    static func visibleTabNames(of target: AppTarget) -> [String] {
        guard let popover = popover(of: target) else { return tabNames }
        let titles = AXReader.children(popover.element).compactMap { child -> String? in
            let node = AXReader.node(child)
            guard node.role == "AXButton", !node.title.isEmpty else { return nil }
            return node.title
        }
        // 分页按钮是 popover 一级子里的按钮，但同一层还可能有其它按钮（如「设置」）：
        // 只认停在已知分页名表里的那些，顺序按 AX 给出的先后
        let filtered = titles.filter { name in tabNames.contains { $0 == name || $0.contains(name) || name.contains($0) } }
        return filtered.count >= 2 ? filtered : tabNames
    }

    /// 现查面板：layer 25 + 可见 + 宽度像面板（> 200）
    static func panel(of target: AppTarget) -> WindowInfo? {
        WindowList.visibleWindows(of: target.pid)
            .first { $0.layer == WindowInfo.panelLayer && $0.bounds.width > 200 }
    }

    /// 第 index 个 tab 的中心点（屏幕全局坐标，左上原点）
    static func tabCenter(panel: CGRect, index: Int, count: Int = tabNames.count) -> CGPoint {
        let usable = panel.width - horizontalInset * 2
        let step = usable / CGFloat(max(count, 1))
        return CGPoint(x: panel.minX + horizontalInset + step * (CGFloat(index) + 0.5),
                       y: panel.minY + tabCenterOffsetY)
    }

    static func tabIndex(of name: String) -> Int? {
        tabNames.firstIndex { name.contains($0) || $0.contains(name) }
    }

    /// 某分页在**当前显示**的段序里排第几（切页用这个，别用全集下标）
    static func visibleTabIndex(of name: String, in target: AppTarget) -> Int? {
        visibleTabNames(of: target).firstIndex { $0 == name || $0.contains(name) || name.contains($0) }
    }

    /// 面板的 AX 容器（AXPopover）
    ///
    /// 面板是 `NSPanel`，不在 `AXWindows` 里，但它的内容视图在 AX 树里——
    /// 只是没有从 app 根可达的路径。做法：在面板 bounds 上取一个点做命中测试，
    /// 再沿 `AXParent` 往上爬到 role == AXPopover 的那一层。
    static func popover(of target: AppTarget) -> AXNode? {
        guard let window = panel(of: target) else { return nil }
        let probe = CGPoint(x: window.bounds.midX, y: window.bounds.minY + 8)
        guard let element = AXReader.element(at: probe)?.element else { return nil }
        return AXReader.ancestor(of: element, where: { $0.role == "AXPopover" })
    }

    /// 当前选中 tab 的标题（读 popover 一级子按钮的 `value == 已选中`）
    ///
    /// 为什么读 value 而不是看高度：剪贴板与 Token 页高度都是 331，
    /// 靠高度变化判定「切页成功」在这两页之间必然误判。
    static func selectedTab(of target: AppTarget) -> String? {
        guard let popover = popover(of: target) else { return nil }
        for child in AXReader.children(popover.element) {
            let node = AXReader.node(child)
            guard node.role == "AXButton", tabNames.contains(node.title) else { continue }
            if node.value.contains("已选中") { return node.title }
        }
        return nil
    }

    // MARK: 开合

    /// 开面板的结果：已开（复用）/ 本次打开 / 失败
    enum OpenResult {
        case alreadyOpen
        case opened
        case failed
    }

    /// 幂等开面板：**先查现况**，已经可见就直接复用
    ///
    /// 必须先查：AXPress 在菜单栏 app 上是 toggle 语义，面板开着时再按一次是**关掉**它，
    /// 之后「等面板出现」必然超时（实测踩过：面板从 onscreen=true 变成 false）。
    static func openPanel(_ target: AppTarget, timeoutMilliseconds: Int = 2000) -> OpenResult {
        if panel(of: target) != nil { return .alreadyOpen }
        guard let item = MenuBarReader.primaryStatusItem(of: target) else { return .failed }
        _ = Actions.press(item)
        return waitPanel(target, present: true, timeoutMilliseconds: timeoutMilliseconds) ? .opened : .failed
    }

    /// 幂等关面板：已经不可见就直接返回成功
    static func closePanel(_ target: AppTarget, timeoutMilliseconds: Int = 2000) -> Bool {
        if panel(of: target) == nil { return true }
        guard let item = MenuBarReader.primaryStatusItem(of: target) else { return false }
        _ = Actions.press(item)
        return waitPanel(target, present: false, timeoutMilliseconds: timeoutMilliseconds)
    }

    /// 轮询等面板出现 / 消失；出现后还要等**尺寸稳定**
    ///
    /// 打开瞬间系统会先把窗口标成 onscreen=true 但只给一个中间尺寸（实测 310x297 / 254x243，
    /// 稳定后才是 346x331）。这时算 tab 坐标必然点到面板外，所以必须等到连续两次采样一致。
    static func waitPanel(_ target: AppTarget, present: Bool, timeoutMilliseconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
        repeat {
            guard (panel(of: target) != nil) == present else {
                usleep(40_000)
                continue
            }
            guard present else { return true }
            if let first = panel(of: target)?.bounds {
                usleep(80_000)
                if let second = panel(of: target)?.bounds, first == second { return true }
            }
        } while Date() < deadline
        return (panel(of: target) != nil) == present
    }

    /// 按完状态项后等面板「落定」
    ///
    /// 状态项是 toggle：按一下可能开、也可能关。开合动画期间系统的窗口尺寸是中间态
    /// （实测 254x243 → 346x331），此时算出来的 tab 坐标会落到面板外，
    /// 截出来的图也带着半张面板。所以按完一律等到「可见性不再变、尺寸连续两次一致」。
    static func settleAfterStatusItemPress(_ target: AppTarget, timeoutMilliseconds: Int = 1500) {
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
        var last: CGRect?
        var stable = 0
        while Date() < deadline {
            let current = panel(of: target)?.bounds
            if current == last {
                stable += 1
                if stable >= 3 { return }
            } else {
                stable = 0
                last = current
            }
            usleep(60_000)
        }
    }

    // MARK: 切 tab

    /// 切到第 index 个 tab：坐标点击 + 校验「选中态真的换了」
    ///
    /// 为什么用坐标点击：tab 条是自绘的，AX 里 tab 按钮的坐标恒为脏值（y=954），
    /// 按它算出来的点必然点不中；坐标只依赖「面板宽 346、左右各 25pt、纵向 35pt」这套版式事实，
    /// 每次按 CGWindowList 现查的 bounds 换算。
    ///
    /// 校验优先读 AX 的选中态（`value=已选中`）；AX 取不到时回退到「面板高度变了」。
    @discardableResult
    static func selectTab(_ target: AppTarget, index: Int, settleMilliseconds: Int = 800) -> Bool {
        // 段数与顺序都按面板**当前实际显示**的算（用户可隐藏 / 重排分页）
        let names = visibleTabNames(of: target)
        guard index >= 0, index < names.count else { return false }
        guard let before = panel(of: target) else { return false }
        let expected = names[index]
        if selectedTab(of: target) == expected { return true }
        let point = tabCenter(panel: before.bounds, index: index, count: names.count)
        Actions.click(at: point)
        usleep(UInt32(settleMilliseconds) * 1000)
        guard let after = panel(of: target) != nil ? panel(of: target) : nil else { return false }
        if let selected = selectedTab(of: target) { return selected == expected }
        return abs(after.bounds.height - before.bounds.height) > 1
    }
}
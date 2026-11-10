import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 截图窗口层级

/// 窗口检测的层级白名单、自家进程放行规则与悬停标签文案
///
/// 由 main.swift 统一注册调用：runSnipWindowLayerTests()
func runSnipWindowLayerTests() {
    print("🧪 Testing Snip window layers...")

    // 层级白名单：显式列举 0 / 20 / 24 / 25，其余一律不收
    assertEqual(SnipWindowLayer.isSupported(SnipWindowLayer.normal), true, "普通窗口层级参与检测")
    assertEqual(SnipWindowLayer.isSupported(SnipWindowLayer.dock), true, "程序坞层级参与检测")
    assertEqual(SnipWindowLayer.isSupported(SnipWindowLayer.menuBar), true, "菜单栏层级参与检测")
    assertEqual(SnipWindowLayer.isSupported(SnipWindowLayer.statusItem), true, "状态栏项层级参与检测")
    assertEqual([SnipWindowLayer.normal, SnipWindowLayer.dock,
                 SnipWindowLayer.menuBar, SnipWindowLayer.statusItem],
                [0, 20, 24, 25], "白名单层级数值与实测一致")
    assertEqual(SnipWindowLayer.isSupported(1), false, "浮层级不参与检测")
    assertEqual(SnipWindowLayer.isSupported(3), false, "辅助窗口层级不参与检测")
    assertEqual(SnipWindowLayer.isSupported(8), false, "非白名单中间层不参与检测")
    assertEqual(SnipWindowLayer.isSupported(SnipWindowLayer.overlayFloor), false, "屏幕保护器层级不参与检测")
    assertEqual(SnipWindowLayer.isSupported(SnipWindowLayer.overlayFloor + 5), false, "更高浮层不参与检测")
    assertEqual(SnipWindowLayer.highestSupported, SnipWindowLayer.statusItem, "白名单最高层是状态栏项")

    // 系统层级判定：程序坞 / 菜单栏 / 状态栏项三个，普通窗口不算
    assertEqual(SnipWindowLayer.isSystemLayer(SnipWindowLayer.dock), true, "程序坞是系统层级")
    assertEqual(SnipWindowLayer.isSystemLayer(SnipWindowLayer.menuBar), true, "菜单栏是系统层级")
    assertEqual(SnipWindowLayer.isSystemLayer(SnipWindowLayer.statusItem), true, "状态栏项是系统层级")
    assertEqual(SnipWindowLayer.isSystemLayer(SnipWindowLayer.normal), false, "普通窗口不是系统层级")

    let ownPID: Int32 = 42
    // 自家普通窗口：层级 0，不该因为是自己就被丢掉（队列里排在别的应用窗口前面）
    let ownWindow = SnipWindowInfo(windowID: 1,
                                   frame: CGRect(x: 0, y: 0, width: 900, height: 600),
                                   ownerPID: ownPID, ownerName: "NetworkMonitor", title: "设置")
    // 自家 popover：层级 25，同样保留 —— 用户能看到就该能框到
    let ownPopover = SnipWindowInfo(windowID: 2,
                                    frame: CGRect(x: 900, y: 0, width: 320, height: 480),
                                    ownerPID: ownPID, ownerName: "NetworkMonitor",
                                    title: "详情页", layer: SnipWindowLayer.statusItem)
    // 自家覆盖层：层级 1000，必须排除（它不是可截内容，是截图工具自己的遮罩）
    let ownOverlay = SnipWindowInfo(windowID: 3,
                                    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                    ownerPID: ownPID, ownerName: "NetworkMonitor",
                                    title: "覆盖层", layer: SnipWindowLayer.overlayFloor)
    let otherApp = SnipWindowInfo(windowID: 4,
                                  frame: CGRect(x: 200, y: 100, width: 600, height: 400),
                                  ownerPID: 100, ownerName: "Xcode", title: "main.swift")

    let mixed = SnipWindowHitTesting.usable(windows: [ownWindow, ownPopover, ownOverlay, otherApp],
                                            excludingPID: ownPID)
    assertEqual(mixed.map(\.windowID), [1, 2, 4], "自家普通窗口与自家 popover 保留，自家覆盖层排除")
    assertEqual(mixed.contains { $0.layer == SnipWindowLayer.overlayFloor }, false, "覆盖层量级不进结果集")

    // 系统层级不受最小边长限制：状态栏项 30×24、更小的状态栏项也要留下
    let statusItem = SnipWindowInfo(windowID: 5,
                                     frame: CGRect(x: 1500, y: 0, width: 30, height: 24),
                                     ownerPID: 200, ownerName: "SystemUIServer", title: "",
                                     layer: SnipWindowLayer.statusItem)
    let tinyStatusItem = SnipWindowInfo(windowID: 6,
                                        frame: CGRect(x: 1540, y: 0, width: 12, height: 12),
                                        ownerPID: 200, ownerName: "ControlCenter", title: "",
                                        layer: SnipWindowLayer.statusItem)
    let dock = SnipWindowInfo(windowID: 7,
                              frame: CGRect(x: 0, y: 1000, width: 1920, height: 80),
                              ownerPID: 300, ownerName: "Dock", title: "",
                              layer: SnipWindowLayer.dock)
    let menuBar = SnipWindowInfo(windowID: 8,
                                 frame: CGRect(x: 0, y: 0, width: 1920, height: 24),
                                 ownerPID: 400, ownerName: "Window Server", title: "",
                                 layer: SnipWindowLayer.menuBar)
    let tinyNormal = SnipWindowInfo(windowID: 9,
                                    frame: CGRect(x: 10, y: 10, width: 8, height: 8),
                                    ownerPID: 100, ownerName: "Xcode", title: "")
    let usable = SnipWindowHitTesting.usable(windows: [statusItem, tinyStatusItem, dock, menuBar, tinyNormal],
                                             excludingPID: ownPID, minimumSide: 20)
    assertEqual(usable.map(\.windowID), [5, 6, 7, 8], "系统层级全部保留，普通窗口仍过最小边长")
    // 门槛放大到 100：普通窗口按门槛滤掉，系统层级不受影响
    let shortBar = SnipWindowInfo(windowID: 20,
                                   frame: CGRect(x: 0, y: 200, width: 600, height: 90),
                                   ownerPID: 100, ownerName: "Xcode", title: "内嵌条")
    let strict = SnipWindowHitTesting.usable(windows: [statusItem, dock, menuBar, otherApp, shortBar],
                                             excludingPID: ownPID, minimumSide: 100)
    assertEqual(strict.map(\.windowID), [5, 7, 8, 4], "大尺寸门槛下系统层级照常保留，矮普通窗口被滤掉")

    // 命中顺序：列表首位优先（程序坞叠在普通窗口上时命中的是程序坞）
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 1510, y: 12),
                                            in: [statusItem, menuBar])?.windowID,
                5, "重叠处命中列表首位的状态栏项")

    // 整屏程序坞容器：只在贴边带子里算命中，且不与普通窗口抢命中
    let fullScreenDock = SnipWindowInfo(windowID: 15,
                                        frame: CGRect(x: 0, y: 33, width: 1512, height: 982),
                                        ownerPID: 300, ownerName: "程序坞", title: "",
                                        layer: SnipWindowLayer.dock)
    let centerWindow = SnipWindowInfo(windowID: 16,
                                       frame: CGRect(x: 400, y: 300, width: 700, height: 400),
                                       ownerPID: 100, ownerName: "Xcode", title: "main.swift")
    // 屏幕中央的空白点：整屏程序坞容器在几何上覆盖这里，但它不是用户眼里的「程序坞」
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 200, y: 500), in: [fullScreenDock]) == nil,
                true, "整屏程序坞容器不抢屏幕中央的命中")
    // 贴着底边（Dock 栏所在位置）才命中程序坞
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 700, y: 1000),
                                            in: [fullScreenDock])?.windowID,
                15, "贴底边命中程序坞")
    // 贴边带内程序坞仍按列表序优先（Dock 栏浮在普通窗口之上，视觉上就该先选它）
    let nearDockWindow = SnipWindowInfo(windowID: 17,
                                        frame: CGRect(x: 400, y: 800, width: 700, height: 200),
                                        ownerPID: 100, ownerName: "Xcode", title: "main.swift")
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 700, y: 1000),
                                            in: [fullScreenDock, nearDockWindow])?.windowID,
                15, "贴边带内程序坞按列表序优先")
    assertEqual(SnipWindowHitTesting.isSelectable(centerWindow, at: CGPoint(x: 700, y: 900)), true,
                "非程序坞窗口不受贴边判据限制")
    assertEqual(SnipWindowHitTesting.isSelectable(fullScreenDock, at: CGPoint(x: 700, y: 1000)), true,
                "程序坞在贴边带内命中")
    assertEqual(SnipWindowHitTesting.isSelectable(fullScreenDock, at: CGPoint(x: 10, y: 1000)), true,
                "程序坞竖向贴边（左右侧 Dock）同样命中")
    // 整屏程序坞容器的顶边不算贴边方向：屏幕顶部留给菜单栏，那里不该提示「程序坞」
    assertEqual(SnipWindowHitTesting.isSelectable(fullScreenDock, at: CGPoint(x: 100, y: 60)), false,
                "顶边不属于程序坞的贴边方向")

    // 选区口径：普通窗口整窗，程序坞只取鼠标所在的那条贴边带
    assertEqual(SnipWindowHitTesting.selectionFrame(for: centerWindow, at: CGPoint(x: 700, y: 500)),
                CGRect(x: 400, y: 300, width: 700, height: 400), "普通窗口选区就是整窗")
    let bottomDockSelection = SnipWindowHitTesting.selectionFrame(for: fullScreenDock,
                                                                  at: CGPoint(x: 700, y: 1000))
    assertEqual(bottomDockSelection, CGRect(x: 0, y: fullScreenDock.frame.maxY - SnipWindowHitTesting.dockEdgeBand,
                                            width: 1512, height: SnipWindowHitTesting.dockEdgeBand),
                "底部停靠的程序坞选区取底边带，不截满屏")
    let leftDockSelection = SnipWindowHitTesting.selectionFrame(for: fullScreenDock,
                                                                at: CGPoint(x: 5, y: 500))
    assertEqual(leftDockSelection, CGRect(x: 0, y: 33, width: SnipWindowHitTesting.dockEdgeBand, height: 982),
                "左侧停靠的程序坞选区取左边带")
    let rightDockSelection = SnipWindowHitTesting.selectionFrame(for: fullScreenDock,
                                                                 at: CGPoint(x: 1500, y: 500))
    assertEqual(rightDockSelection,
                CGRect(x: 1512 - SnipWindowHitTesting.dockEdgeBand, y: 33,
                       width: SnipWindowHitTesting.dockEdgeBand, height: 982),
                "右侧停靠的程序坞选区取右边带")

    // 悬停标签：系统层级三种文案 + 普通窗口回退
    // UI 目标不依赖 Core，自有层级常量；断言把两边钉在一起，改一处不改另一处会红
    assertEqual(SnipWindowLabel.normalLayer, SnipWindowLayer.normal, "UI 普通窗口层级与 Core 一致")
    assertEqual(SnipWindowLabel.dockLayer, SnipWindowLayer.dock, "UI 程序坞层级与 Core 一致")
    assertEqual(SnipWindowLabel.menuBarLayer, SnipWindowLayer.menuBar, "UI 菜单栏层级与 Core 一致")
    assertEqual(SnipWindowLabel.statusItemLayer, SnipWindowLayer.statusItem, "UI 状态栏项层级与 Core 一致")
    assertEqual(SnipWindowLabel.layerName(SnipWindowLayer.menuBar), "菜单栏", "菜单栏层级名")
    assertEqual(SnipWindowLabel.layerName(SnipWindowLayer.dock), "程序坞", "程序坞层级名")
    assertEqual(SnipWindowLabel.layerName(SnipWindowLayer.statusItem), "状态栏项", "状态栏项层级名")
    assertEqual(SnipWindowLabel.layerName(SnipWindowLayer.normal), nil, "普通窗口不带层级名")
    assertEqual(snipWindowLabelText(for: menuBar), "菜单栏 — Window Server", "菜单栏标签带应用名")
    assertEqual(snipWindowLabelText(for: dock), "程序坞 — Dock", "程序坞标签带应用名")
    assertEqual(snipWindowLabelText(for: statusItem), "状态栏项 — SystemUIServer", "状态栏项标签带应用名")
    let namelessDock = SnipWindowInfo(windowID: 10,
                                      frame: CGRect(x: 0, y: 1000, width: 1920, height: 80),
                                      ownerPID: 300, ownerName: "", title: "",
                                      layer: SnipWindowLayer.dock)
    assertEqual(snipWindowLabelText(for: namelessDock), "程序坞", "应用名缺失时只写层级名")
    // 真机实测：程序坞窗口的 ownerName 就是「程序坞」，重复时不写两遍
    let dockNamedDock = SnipWindowInfo(windowID: 14,
                                       frame: CGRect(x: 0, y: 1000, width: 1920, height: 80),
                                       ownerPID: 300, ownerName: "程序坞", title: "",
                                       layer: SnipWindowLayer.dock)
    assertEqual(snipWindowLabelText(for: dockNamedDock), "程序坞", "应用名与层级名相同只写一份")
    assertEqual(snipWindowLabelText(for: otherApp), "Xcode — main.swift", "普通窗口标签带应用名与标题")
    let untitled = SnipWindowInfo(windowID: 11,
                                  frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                  ownerPID: 100, ownerName: "Finder", title: "")
    assertEqual(snipWindowLabelText(for: untitled), "Finder", "无标题时只写应用名")
    let anonymous = SnipWindowInfo(windowID: 12,
                                   frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                   ownerPID: 100, ownerName: "  ", title: "  ")
    assertEqual(snipWindowLabelText(for: anonymous), "窗口", "应用名与标题都缺失时回退为窗口")

    // 默认层级：老调用点不传 layer 时按普通窗口处理，不改变既有命中行为
    let legacy = SnipWindowInfo(windowID: 13,
                                frame: CGRect(x: 0, y: 0, width: 500, height: 400),
                                ownerPID: 100, ownerName: "Finder", title: "")
    assertEqual(legacy.layer, SnipWindowLayer.normal, "不传 layer 默认为普通窗口层级")
    assertEqual(SnipWindowHitTesting.usable(windows: [legacy], excludingPID: ownPID).count, 1,
                "默认层级窗口照常参与检测")
}
/// UI 目标只认基础类型入参，这里包一层，让断言写法保持紧凑
/// 名字带前缀：这是 TestRunner 全局命名空间里的顶层函数，避免与其他测试文件撞名
func snipWindowLabelText(for window: SnipWindowInfo) -> String {
    SnipWindowLabel.text(layer: window.layer, ownerName: window.ownerName, title: window.title)
}
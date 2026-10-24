import Foundation
import NetworkMonitorCore

// MARK: - 截图选区几何（多屏 / Retina / 归一化）

func runSnipGeometryTests() {
    print("🧪 Testing Snip selection geometry...")

    // 归一化：正向、反向拖拽结果一致
    assertEqual(SelectionGeometry.normalize(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 30, y: 50)),
                CGRect(x: 10, y: 20, width: 20, height: 30), "正向拖拽归一化")
    assertEqual(SelectionGeometry.normalize(from: CGPoint(x: 30, y: 50), to: CGPoint(x: 10, y: 20)),
                CGRect(x: 10, y: 20, width: 20, height: 30), "反向拖拽归一化")

    // 选区有效性：零宽 / 亚像素一律拒绝
    assertEqual(SnipSelection(rect: CGRect(x: 0, y: 0, width: 0, height: 10)) == nil, true, "零宽选区无效")
    assertEqual(SnipSelection(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)) == nil, true, "亚像素选区无效")
    assertEqual(SnipSelection(rect: CGRect(x: 0, y: 0, width: 1, height: 1)) != nil, true, "1pt 选区有效")

    // 夹取：越界部分被裁掉，完全不相交返回零矩形
    assertEqual(SelectionGeometry.clamp(CGRect(x: -100, y: -100, width: 200, height: 200),
                                        to: CGRect(x: 0, y: 0, width: 100, height: 100)),
                CGRect(x: 0, y: 0, width: 100, height: 100), "越界选区夹取到边界")
    assertEqual(SelectionGeometry.clamp(CGRect(x: 200, y: 200, width: 10, height: 10),
                                        to: CGRect(x: 0, y: 0, width: 100, height: 100)),
                .zero, "完全不相交返回零矩形")

    // 多屏：主屏 2x、左侧副屏负坐标 1x
    let main = SnipDisplay(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                           pixelSize: CGSize(width: 2880, height: 1800),
                           displayID: 1)
    let left = SnipDisplay(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                           pixelSize: CGSize(width: 1920, height: 1080),
                           displayID: 2)
    assertEqual(main.backingScale, 2, "主屏 Retina 缩放比 2")
    assertEqual(left.backingScale, 1, "副屏缩放比 1")
    assertEqual(SelectionGeometry.unionFrame(of: [main, left]),
                CGRect(x: -1920, y: 0, width: 3360, height: 1080), "多屏并集")
    assertEqual(SelectionGeometry.display(containing: CGPoint(x: -100, y: 50), in: [main, left])?.displayID,
                2, "负坐标点命中副屏")
    assertEqual(SelectionGeometry.display(containing: CGPoint(x: 100, y: 50), in: [main, left])?.displayID,
                1, "主屏点命中主屏")

    // AppKit（左下原点）转 CG（左上原点）
    assertEqual(SelectionGeometry.cgRect(fromAppKit: CGRect(x: 100, y: 200, width: 300, height: 400),
                                         primaryHeight: 900),
                CGRect(x: 100, y: 300, width: 300, height: 400), "AppKit 转 CG 坐标")

    // 像素映射：主屏 2x，选区 (100,100,200,100) → 像素 (200,200,400,200)
    assertEqual(SelectionGeometry.pixelRect(of: CGRect(x: 100, y: 100, width: 200, height: 100),
                                            in: main,
                                            imageSize: CGSize(width: 2880, height: 1800)),
                CGRect(x: 200, y: 200, width: 400, height: 200), "Retina 像素映射")
    assertEqual(SelectionGeometry.pixelRect(of: CGRect(x: -1920, y: 0, width: 100, height: 50),
                                            in: left,
                                            imageSize: CGSize(width: 1920, height: 1080)),
                CGRect(x: 0, y: 0, width: 100, height: 50), "负坐标副屏像素映射")

    // 跨屏选区：在副屏上只取交叠部分
    assertEqual(SelectionGeometry.pixelRect(of: CGRect(x: -100, y: 0, width: 200, height: 100),
                                            in: left,
                                            imageSize: CGSize(width: 1920, height: 1080)),
                CGRect(x: 1820, y: 0, width: 100, height: 100), "跨屏选区只取本屏交叠")

    // 像素矩形不越出图像边界
    assertEqual(SelectionGeometry.pixelRect(of: CGRect(x: 1400, y: 800, width: 200, height: 200),
                                            in: main,
                                            imageSize: CGSize(width: 2880, height: 1800)),
                CGRect(x: 2800, y: 1600, width: 80, height: 200), "越界部分被裁到图像内")
}

import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 截图鼠标手势（回归：想拖任意区域却被判成点选整窗）

func runSnipPointerGestureTests() {
    print("🧪 Testing snip pointer gesture...")

    // 没有悬停窗口时，任何手势都是自定义选区
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 10, y: 10),
                                           end: CGPoint(x: 10, y: 10),
                                           hasHoveredWindow: false), .dragSelection,
                "空白处原地点击仍是自定义选区（退化后被丢弃）")

    // 悬停窗口：位移在阈值内算点选整窗
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 200, y: 200),
                                           end: CGPoint(x: 200, y: 200),
                                           hasHoveredWindow: true), .clickWindow,
                "原地点击 = 选整窗")
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 200, y: 200),
                                           end: CGPoint(x: 203, y: 201),
                                           hasHoveredWindow: true), .clickWindow,
                "3 点抖动（阈值内）仍算点击")
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 200, y: 200),
                                           end: CGPoint(x: 204, y: 200),
                                           hasHoveredWindow: true), .clickWindow,
                "位移正好等于阈值仍算点击")

    // 超过阈值算拖拽（用户想拖任意区域，不该被抢成整窗）
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 200, y: 200),
                                           end: CGPoint(x: 205, y: 200),
                                           hasHoveredWindow: true), .dragSelection,
                "5 点位移就进入自定义选区")
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 200, y: 200),
                                           end: CGPoint(x: 400, y: 320),
                                           hasHoveredWindow: true), .dragSelection,
                "大幅拖拽 = 自定义选区")

    // 斜向位移按直线距离判定，不是按单轴
    assertEqual(SnipPointerGesture.outcome(start: CGPoint(x: 0, y: 0),
                                           end: CGPoint(x: 3, y: 3),
                                           hasHoveredWindow: true), .dragSelection,
                "斜向 3+3 点距离 4.24 已超阈值")

    print("✅ 截图鼠标手势测试通过")
}

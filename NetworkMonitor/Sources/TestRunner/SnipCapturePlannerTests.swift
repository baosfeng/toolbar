import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 截图捕获路径降级（回归：macOS 26 新接口失败导致「截了没反应」）

func runSnipCapturePlannerTests() {
    print("🧪 Testing snip capture path planner...")

    // 新系统：三条路径全在，新接口优先、filter 兜底
    assertEqual(SnipCapturePlanner.availablePaths(isMacOS26OrNewer: true, isMacOS15_2OrNewer: true),
                [.screenshotConfiguration, .rect, .filter], "macOS 26+ 路径顺序")
    // 15.2 ~ 26：没有新接口，rect 优先
    assertEqual(SnipCapturePlanner.availablePaths(isMacOS26OrNewer: false, isMacOS15_2OrNewer: true),
                [.rect, .filter], "macOS 15.2+ 路径顺序")
    // 14.x：只剩兜底，且不能被清除
    assertEqual(SnipCapturePlanner.availablePaths(isMacOS26OrNewer: false, isMacOS15_2OrNewer: false),
                [.filter], "macOS 14 只剩兜底路径")
    // 版本标记异常（26 true 但 15.2 false）时仍要保证有兜底
    assertEqual(SnipCapturePlanner.availablePaths(isMacOS26OrNewer: true, isMacOS15_2OrNewer: false),
                [.screenshotConfiguration, .filter], "只有新接口时仍需 filter 兜底")

    // 每条路径都有可读名（日志要能指出失败的是哪条）
    for path in SnipCapturePath.allCasesIfAvailable() {
        assertEqual(path.displayName.isEmpty, false, "路径 \(path) 有可读名")
    }

    print("✅ 截图捕获路径降级测试通过")
}

extension SnipCapturePath {
    /// 测试用：可取值的全集（case 顺序即声明顺序）
    static func allCasesIfAvailable() -> [SnipCapturePath] {
        [.screenshotConfiguration, .rect, .filter]
    }
}

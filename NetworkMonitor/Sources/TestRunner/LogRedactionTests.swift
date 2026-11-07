import Foundation
import NetworkMonitorCore

// MARK: - 日志脱敏

/// 日志脱敏单测：路径隐去用户名、PIN 全隐藏、长凭据只留末 4 位
func runLogRedactionTests() {
    print("🧪 Testing 日志脱敏...")

    // 主目录前缀替换为 ~，相对结构与其他目录保持原样
    let home = NSHomeDirectory()
    assertEqual(LogRedaction.path(home + "/Library/Application Support/macMonitor/monitor.db"),
                "~/Library/Application Support/macMonitor/monitor.db",
                "主目录下的路径隐去用户名")
    assertEqual(LogRedaction.path("/Volumes/External/receive"), "/Volumes/External/receive",
                "非主目录路径原样保留")
    assertEqual(LogRedaction.path(home), "~", "主目录本身替换为 ~")
    assertEqual(LogRedaction.path(""), "", "空串保持空串")

    // 用户名不能出现在结果里（防止 NSHomeDirectory 形态变化时静默放行）
    let leakedUser = (home as NSString).lastPathComponent
    assertEqual(LogRedaction.path(home + "/Documents/a.png").contains(leakedUser), false,
                "隐去后不含用户名")

    // PIN：不保留任何一位数字
    assertEqual(LogRedaction.pin("1234"), "<4 位已隐藏>", "4 位 PIN 只报长度")
    assertEqual(LogRedaction.pin("1234").contains("1"), false, "PIN 不暴露任何数字")

    // 长凭据：只留末 4 位，短凭据整体隐藏
    assertEqual(LogRedaction.secret("abcdefghijkl"), "***ijkl", "长凭据保留末 4 位")
    assertEqual(LogRedaction.secret("short"), "<已隐藏>", "短凭据整体隐藏")
    assertEqual(LogRedaction.secret("  abcdefghijkl  "), "***ijkl", "首尾空白被裁掉后再遮蔽")

    print("✅ 日志脱敏 works")
}

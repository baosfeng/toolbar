#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 贴图右键菜单装配自证（仅 DEBUG）

/// 把「按偏好装配出来的菜单」原样打印出来，证明九项跨组换序在真机菜单里生效
///
/// 触发方式：NM_PIN_MENU_PROBE=1 dist/一览.app/Contents/MacOS/一览
/// 打印内容：每项的标题、是否为分隔线、是否标红（危险项），以及最终顺序。
@MainActor
enum PinMenuProbe {

    static let envKey = "NM_PIN_MENU_PROBE"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    /// 用一份隔离的内存存储模拟用户偏好（不碰真实偏好域）
    static func run(storage: any KeyValueStorage) {
        guard isRequested else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let scenarios: [(String, String?)] = [
                ("缺键（老用户默认）", nil),
                ("把销毁提到第一位", "destroy,close,copy,save,rotate,mirrorHorizontal,mirrorVertical,thumbnail,resetSizeAndAlpha"),
                ("跨组交叉（变换 / 输出 / 危险混排）", "thumbnail,copy,destroy,save,rotate"),
                ("旧偏好（组内换序时代）", "save,copy,thumbnail,rotate,mirrorHorizontal,mirrorVertical,resetSizeAndAlpha,close,destroy")
            ]
            for (name, raw) in scenarios {
                if let raw {
                    storage.set(raw, forKey: PinMenuPreferenceKey.contextMenuOrder)
                } else {
                    storage.removeObject(forKey: PinMenuPreferenceKey.contextMenuOrder)
                }
                let order = PinMenuOrderResolver.load(storage: storage)
                let separators = PinMenuDivider.leadingSeparators(for: order)
                let lines = order.enumerated().map { index, action -> String in
                    let red = action.isDestructive ? "【红字】" : ""
                    return "\(separators[index] ? "————" : "      ") \(index + 1). \(action.title)\(red)"
                }
                print("🔎 [pin-menu] 场景：\(name)")
                print(lines.joined(separator: "\n"))
                print("🔎 [pin-menu] 装配项数=\(order.count)，分隔线=\(separators.filter { $0 }.count) 条")
                print("")
            }
            print("🔎 [pin-menu] 探针完成")
            exit(0)
        }
    }
}
#endif

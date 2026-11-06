#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 快照数值单位档位（仅 DEBUG）

/// 数值单位档位开关 — 从 `MenuPanelSnapshot.swift` 拆出（主文件贴顶 15 KiB 上限）
///
/// 触发方式：`NM_SNAPSHOT_DIR=/tmp/x NM_UNIT_STYLE=chinese <bundle 内可执行>`，
/// 用**内存存储**切成万 / 亿档出图，绝不碰用户真实偏好（进程退出即丢弃）。
/// 文件名加 `-chinese` 后缀，避免覆盖默认档截图。
extension MenuPanelSnapshot {

    /// 环境变量名（取值 = `NumberUnitStyle.rawValue`）
    static let unitStyleEnvKey = "NM_UNIT_STYLE"

    /// 数值单位档位（nil = 不改，跟随真实偏好）
    static var unitStyle: NumberUnitStyle? {
        guard let raw = ProcessInfo.processInfo.environment[unitStyleEnvKey] else { return nil }
        return NumberUnitStyle(rawValue: raw)
    }

    /// 文件名后缀（切档取证时加 "-chinese"，避免覆盖默认档的截图）
    static var unitFileSuffix: String {
        unitStyle == .chinese ? "-chinese" : ""
    }

    /// 按单位档位准备存储：切档时换成内存存储并写入档位（不碰用户真实偏好）
    static func prepareUnitStyleForSnapshot() {
        guard let style = unitStyle else { return }
        let storage = SnapshotKeyValueStorage()
        AppContext.shared.configure(storage: storage)
        NumberUnitPreferences(storage: storage).setStyle(style)
    }
}
#endif

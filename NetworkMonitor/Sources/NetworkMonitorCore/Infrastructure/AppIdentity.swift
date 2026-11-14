import Foundation

// MARK: - 应用对外标识

/// 应用对外显示名 — 用户可见产品名的唯一真源
///
/// 只作用于界面文案、系统弹框与「本应用那一行」的进程名（`ProcessDisplayName` 的兜底映射）；
/// `CFBundleIdentifier` / 签名身份 / 数据目录都不跟随它变化——换这些标识会让 TCC 授权、
/// 本地偏好与已有数据失效。包名与包内可执行名是同源的中文名，实现上走 `build-app.sh` 的
/// `APP_BUNDLE_NAME` / `APP_EXECUTABLE_NAME`（可执行名靠打包时复制改名，SwiftPM target 名仍是 NetworkMonitor）。
///
/// 打包脚本 `Scripts/build-app.sh` 的 `APP_DISPLAY_NAME` 与本常量同源：改名时两处一起改，
/// 脚本侧负责写进 Info.plist（`CFBundleName` / `CFBundleDisplayName` / 权限用途说明）。
public enum AppIdentity {

    /// 产品显示名（退出菜单 / 关于页 / 权限引导 / 通知口径共用）
    public static let displayName = "一览"
}

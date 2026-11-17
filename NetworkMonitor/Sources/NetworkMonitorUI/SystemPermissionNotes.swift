import Foundation
import NetworkMonitorCore

// MARK: - 卡下说明的拼装

public extension SystemPermissionSnapshot {

    /// 卡片下方那几句说明 —— 条数随状态变，全绿时只留「切回应用即刷新」
    ///
    /// 规则放在这里（不是视图里）：说明的措辞与条数跟着权限状态走，
    /// 写成纯函数才能被 TestRunner 逐条钉住；视图只负责把数组渲染成几行字。
    func notes(appPath: String) -> [String] {
        var notes = ["状态在切回本应用时自动刷新，系统设置里勾选后无需重启界面。"]
        for entry in entries where entry.showsManualAddGuide {
            notes.append(entry.manualAddGuide(appPath: appPath))
        }
        for entry in entries where entry.showsRestartHint {
            notes.append(entry.restartHint)
        }
        if let reason = loginItemRollbackReason, !reason.isEmpty, !state(for: .loginItem).isGranted {
            notes.append("开机自启动注册失败已回滚偏好为关（\(reason)），需在系统设置「登录项」里允许。")
        }
        return notes.filter { !$0.isEmpty }
    }
}

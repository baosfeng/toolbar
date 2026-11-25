import Foundation
import NetworkMonitorCore

// MARK: - 按签名态分叉的文案

/// 签名形态相关文案 —— 同一句说明在证书签名与 ad-hoc 下的结论相反，必须分开写
///
/// 为什么抽成枚举：关于页那句「当前使用 ad-hoc 签名，替换后需要重新授权」
/// 在已经用证书签的包上是**错的**（正是本轮的缺陷之一），
/// 判据与措辞收在一处才不会再各写一份、各自漂移。
public enum SigningIdentityText {

    /// 关于页「安装」卡的说明（换包这件事对已授权项意味着什么）
    ///
    /// - Parameter isCertificateSigned: 当前包是否证书签名（`SigningIdentity.isCertificateSigned`）
    public static func installNote(isCertificateSigned: Bool) -> String {
        let head = "安装会把新版本下载到临时目录、校验版本后替换当前应用包并重启。"
        guard isCertificateSigned else {
            return head + "\(AppIdentity.displayName) 当前使用 ad-hoc 签名：替换后 cdhash 变化，"
                + "屏幕录制 / 辅助功能 / 输入监控与登录项可能需要重新授权。"
        }
        return head + "\(AppIdentity.displayName) 使用本地证书签名："
            + "升级不会影响已授权项（切换签名方式的那一次除外）。"
    }

    /// 一行式签名形态描述（关于页 / 诊断日志共用）
    public static func signatureSummary(isCertificateSigned: Bool) -> String {
        isCertificateSigned ? "本地证书签名（升级不影响已授权项）" : "ad-hoc 签名（每次重建都会换身份）"
    }
}

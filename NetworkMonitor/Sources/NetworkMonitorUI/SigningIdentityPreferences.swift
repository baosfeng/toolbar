import Foundation
import NetworkMonitorCore

// MARK: - 签名身份的历史记录

/// 上次启动的签名身份 —— 存在偏好里，下一次启动才有「上一次是什么」可比
///
/// 为什么落在 UI 层：判据（`SigningIdentityChange.detect`）与口径（`SigningIdentityNotice`）
/// 都在这里，持久化跟着它们走，App 层只注入 `KeyValueStorage` 并负责读系统 API。
/// 键名一口价写死在 `Key` 里，缺键 = 首启动 = 不提示（老用户外观零变化）。
public final class SigningIdentityPreferences: @unchecked Sendable {

    private enum Key {
        /// 上次记录的签名身份（`certificate:<hex>` / `adhoc:<hex>`）
        static let lastFingerprint = "permissions.lastSigningFingerprint"
    }

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage) {
        self.storage = storage
    }

    /// 上次记录的签名身份（缺键 / 脏数据都返回 nil = 按首启动处理）
    public var lastIdentity: SigningIdentity? {
        guard let raw = storage.string(forKey: Key.lastFingerprint), !raw.isEmpty else { return nil }
        return SigningIdentity(fingerprint: raw)
    }

    /// 记下本次启动的签名身份
    ///
    /// 只在「读完系统 API 拿到真值」之后调用：拿不到真值就不该覆盖历史，
    /// 否则一次读失败会把历史抹成 nil，下次启动变成「首启动」，真变化被吞掉。
    public func record(_ identity: SigningIdentity) {
        storage.set(identity.fingerprint, forKey: Key.lastFingerprint)
    }

    /// 读出历史 → 与当前比对 → 落盘当前值，返回提示带口径（nil = 不提示）
    ///
    /// 顺序不可换：必须先读历史再覆盖，否则永远比的是「自己」。
    /// 首启动（无历史）只记录不提示 —— 老用户刚装上这一版时权限是好的，
    /// 不该被一条「签名变了」的提示带吓到。
    @discardableResult
    public func reconcile(current: SigningIdentity) -> SigningIdentityNotice? {
        let previous = lastIdentity
        record(current)
        let change = SigningIdentityChange.detect(previous: previous, current: current)
        guard let change else { return nil }
        return SigningIdentityNotice(identity: current, change: change)
    }

    /// 清掉历史（仅测试与「重置偏好」类入口使用）
    public func reset() {
        storage.removeObject(forKey: Key.lastFingerprint)
    }
}

import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 签名身份变化判定测试

/// 签名身份（cdhash / 证书叶子）与「升级后要不要提示重新授权」的判据 —— 全是纯函数
///
/// 覆盖顺序按「最容易报假警的地方优先」排：首启动不提示、证书签名下换版本不提示
/// （cdhash 变了但 DR 没变），这两种情况一旦判错，用户每次正常升级都会被弹一条
/// 「请重新授权」，比不提示更糟。
func runSigningIdentityTests() {
    print("\n🧪 Testing 签名身份与权限失配判定...")

    // MARK: 指纹编解码

    let cert = SigningIdentity(kind: .certificate, token: "A75DA71B2FFA5F24C17723206F1D739940B63521")
    assertEqual(cert.fingerprint, "certificate:a75da71b2ffa5f24c17723206f1d739940b63521",
                "证书签名的指纹带形态前缀且转小写")
    assertEqual(SigningIdentity(fingerprint: cert.fingerprint), cert, "指纹可往返")
    assertEqual(SigningIdentity(fingerprint: "certificate:"), nil, "空 token 认不出（不拿脏数据判变化）")
    assertEqual(SigningIdentity(fingerprint: "unknown:abc"), nil, "未知形态认不出")
    assertEqual(SigningIdentity(fingerprint: "abc"), nil, "没有分隔符认不出")
    assertEqual(cert.isCertificateSigned, true, "证书签名")
    assertEqual(SigningIdentity.adhoc(cdhash: "B950222C").isCertificateSigned, false, "ad-hoc")

    // MARK: 证书 DER → 叶子哈希（与 codesign 输出同形的小写十六进制）

    // 空输入的 SHA-1 是固定值（da39a3ee…）：用它证明「同一个函数、可复现、小写 40 位」
    let emptyHash = SigningIdentity.certificateToken(Data())
    assertEqual(emptyHash.count, 40, "证书 token 是 40 位十六进制")
    assertEqual(emptyHash, emptyHash.lowercased(), "证书 token 一律小写")
    assertEqual(SigningIdentity.certificateToken(Data("a".utf8))
                == SigningIdentity.certificateToken(Data("b".utf8)), false,
                "不同证书 DER 得到不同 token")
    assertEqual(SigningIdentity.certificate(certificateDER: Data()).kind, .certificate,
                "从证书 DER 构造出来的是证书签名身份")

    // MARK: 变化判定（六条路径）

    // 1. 首启动：没有历史 → 不提示（老用户刚装上这一版时权限是好的）
    let currentCert = SigningIdentity(kind: .certificate, token: "aaa")
    assertEqual(SigningIdentityChange.detect(previous: nil, current: currentCert), nil,
                "首启动不提示")

    // 2. 同一张证书、换了版本（cdhash 变）→ 不提示：DR 认证书叶子，授权能继承
    assertEqual(SigningIdentityChange.detect(previous: currentCert, current: currentCert), nil,
                "同证书签名升级不提示")

    // 3. 证书 → 另一张证书：DR 的 certificate leaf 变了，全部失配
    assertEqual(SigningIdentityChange.detect(
        previous: SigningIdentity(kind: .certificate, token: "aaa"),
        current: SigningIdentity(kind: .certificate, token: "bbb")),
        .signedWithCertificateChanged, "换证书要提示")

    // 4. ad-hoc → ad-hoc 但 cdhash 变了：DR 逐字不同，同样全部失配
    assertEqual(SigningIdentityChange.detect(
        previous: SigningIdentity(kind: .adhoc, token: "1111"),
        current: SigningIdentity(kind: .adhoc, token: "2222")),
        .adhocRebuilt, "ad-hoc 重建换 cdhash 要提示")

    // 5. ad-hoc → 同一份二进制（没重建）：不提示
    let adhoc = SigningIdentity(kind: .adhoc, token: "1111")
    assertEqual(SigningIdentityChange.detect(previous: adhoc, current: adhoc), nil,
                "ad-hoc 换版本但内容一致不提示")

    // 6. 两种形态互换：双向都是「DR 互不满足」
    assertEqual(SigningIdentityChange.detect(previous: adhoc, current: currentCert),
                .switchedBetweenModes, "ad-hoc → 证书要提示")
    assertEqual(SigningIdentityChange.detect(previous: currentCert, current: adhoc),
                .switchedBetweenModes, "证书 → ad-hoc 要提示")

    // MARK: 文案（三条路径都要说清「为什么」+「做什么」）

    for change in [SigningIdentityChange.adhocRebuilt, .signedWithCertificateChanged, .switchedBetweenModes] {
        assertContains(change.headline, "签名已变化", "\(change) 标题点名签名变化")
        assertContains(change.headline, "重新确认", "\(change) 标题说明要做什么")
        assertEqual(change.detail.isEmpty, false, "\(change) 有正文")
    }
    assertContains(SigningIdentityChange.adhocRebuilt.detail, "ad-hoc", "ad-hoc 路径点名形态")
    assertContains(SigningIdentityChange.switchedBetweenModes.detail, "另一个应用",
                   "换形态说明 macOS 视为另一个应用")

    // MARK: 待重授清单（只列「没授权」，读不到不报案）

    let mixed = SystemPermissionSnapshot(accessibility: .pending, screenCapture: .pending,
                                         clipboard: .granted, notification: .unknown,
                                         loginItem: .denied)
    assertEqual(SigningIdentityChange.pendingKinds(in: mixed), [.accessibility, .screenCapture, .loginItem],
                "待重授清单只含未授权项（unknown / granted 不算）")
    assertEqual(SigningIdentityChange.pendingSummary(in: mixed),
                "需要重新确认：辅助功能、屏幕录制、开机自启动", "清单一行式文案")
    assertEqual(SigningIdentityChange.pendingSummary(in: .allChecking), "",
                "检测中不算待重授（不凭空报故障）")

    // MARK: 提示带口径

    let notice = SigningIdentityNotice(identity: adhoc, change: .switchedBetweenModes)
    assertEqual(notice.isVisible, true, "有变化就可见")
    assertEqual(notice.lines(in: mixed).count, 3, "标题 + 正文 + 待重授清单三行")
    assertEqual(SigningIdentityNotice(identity: adhoc, change: nil).isVisible, false,
                "没变化不显示")
    assertEqual(SigningIdentityNotice(identity: adhoc, change: nil).lines(in: mixed), [],
                "没变化时没有任何说明行")
    let green = SystemPermissionSnapshot(accessibility: .granted, screenCapture: .granted,
                                         clipboard: .granted, notification: .granted,
                                         loginItem: .granted)
    assertEqual(notice.pendingLine(in: green), "", "全绿时没有待重授清单（只留有说明 + 按钮）")
    assertEqual(notice.lines(in: green).count, 2, "全绿时只有标题 + 正文")

    // MARK: 偏好往返（首启动只记不提示，第二次启动才可比）

    let storage = InMemoryStorage()
    let prefs = SigningIdentityPreferences(storage: storage)
    assertEqual(prefs.lastIdentity, nil, "首次运行没有历史")
    assertEqual(prefs.reconcile(current: adhoc), nil, "首启动只记录不提示")
    assertEqual(prefs.lastIdentity, adhoc, "首启动把身份记下来了")
    assertEqual(prefs.reconcile(current: adhoc), nil, "同一身份再启动不提示")
    assertEqual(prefs.reconcile(current: currentCert)?.change, .switchedBetweenModes,
                "换成证书签名那一次要提示")
    assertEqual(prefs.lastIdentity, currentCert, "提示后历史已更新为新身份")
    prefs.reset()
    assertEqual(prefs.lastIdentity, nil, "reset 清掉历史")

    // MARK: 关于页安装卡文案（证书签名下不许再说「替换即失权」）

    let certNote = SigningIdentityText.installNote(isCertificateSigned: true)
    let adhocNote = SigningIdentityText.installNote(isCertificateSigned: false)
    assertContains(certNote, "不会影响已授权项", "证书签名说升级不影响授权")
    assertNotContains(certNote, "ad-hoc", "证书签名的说明里不许出现 ad-hoc")
    assertContains(adhocNote, "ad-hoc", "ad-hoc 说明点名形态")
    assertContains(adhocNote, "重新授权", "ad-hoc 说明提示要重新授权")
    assertContains(SigningIdentityText.signatureSummary(isCertificateSigned: true), "证书签名",
                   "摘要按形态分叉")
    assertContains(SigningIdentityText.signatureSummary(isCertificateSigned: false), "ad-hoc",
                   "摘要按形态分叉（ad-hoc）")

    print("✅ 签名身份与权限失配判定 works")
}

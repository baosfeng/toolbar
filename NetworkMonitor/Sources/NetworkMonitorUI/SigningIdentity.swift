import CryptoKit
import Foundation

// MARK: - 签名身份

/// 当前进程签名身份的两种形态 —— 决定 TCC 授权能不能跨版本保留
///
/// 为什么必须区分：证书签名的 designated requirement 是「identifier + 证书叶子」，
/// 包内容变了 DR 也不变（实测：两份只差一个字节的二进制 cdhash 不同、DR 逐字相同），
/// 所以升级不会丢授权；ad-hoc 的 DR 是 cdhash 本身，等于「内容的纯函数」，
/// 每重建一次就换一个身份，用户每升级一次都要回系统设置重勾一遍。
public struct SigningIdentity: Equatable, Sendable {

    /// 签名形态
    public enum Kind: String, Sendable {
        /// 无证书（linker 自带或 `codesign --sign -`）
        case adhoc
        /// 证书签名（本机自签或 Developer ID）
        case certificate
    }

    public let kind: Kind
    /// 身份判别串：ad-hoc 用 cdhash；证书签名用证书叶子 SHA-1（两者都是十六进制）
    public let token: String

    public init(kind: Kind, token: String) {
        self.kind = kind
        self.token = token.lowercased()
    }

    /// 是否证书签名（关于页文案与提示带都按它分叉）
    public var isCertificateSigned: Bool { kind == .certificate }

    /// 持久化形如 `certificate:a75da71b…` / `adhoc:b950222c…`
    ///
    /// 为什么把形态编进字符串而不是再存一个布尔：两个字段分开存就有「只写了一半」的
    /// 中间态（指纹新、形态旧），而这里一个键要么完整要么缺失。
    public var fingerprint: String { "\(kind.rawValue):\(token)" }

    /// 从偏好里读回的指纹（格式不认识 = nil，按「没有历史」处理，不拿脏数据判变化）
    public init?(fingerprint: String) {
        let parts = fingerprint.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let parsedKind = Kind(rawValue: String(parts[0])),
              !parts[1].isEmpty else { return nil }
        self.init(kind: parsedKind, token: String(parts[1]))
    }
}

// MARK: - 身份变化判定

/// 上次启动与本次启动的签名身份对比结论 —— 只有「会影响 TCC 命中」的变化才算变化
///
/// 判据全部是纯函数，TestRunner 逐条钉住；App 层只负责读系统 API 与落偏好。
public enum SigningIdentityChange: Equatable, Sendable {

    /// 证书签名 → 换了另一张证书：DR 的 certificate leaf 变了，已授权项全部失配
    case signedWithCertificateChanged
    /// ad-hoc → ad-hoc 但 cdhash 变了：同为「匿名」，但 DR 逐字不同，同样全部失配
    case adhocRebuilt
    /// 证书签名 ⇄ ad-hoc：两种 DR 形态互不满足（实测双向都过不了 code requirement）
    case switchedBetweenModes

    /// 判定变化
    ///
    /// - Parameters:
    ///   - previous: 上次记录的签名身份（nil = 首启动 / 脏数据，一律不提示）
    ///   - current: 本次启动读到的签名身份
    /// - Returns: nil 表示「不需要提示用户重新授权」
    ///
    /// 证书签名的 cdhash 不参与比较：换版本时 cdhash 必然变，但 DR 不变，
    /// 把它算进判据会让每次正常升级都弹一次「请重新授权」，那是假警报。
    public static func detect(previous: SigningIdentity?,
                              current: SigningIdentity) -> SigningIdentityChange? {
        guard let previous else { return nil }
        switch (previous.kind, current.kind) {
        case (.certificate, .certificate):
            return previous.token == current.token ? nil : .signedWithCertificateChanged
        case (.adhoc, .adhoc):
            return previous.token == current.token ? nil : .adhocRebuilt
        case (.certificate, .adhoc), (.adhoc, .certificate):
            return .switchedBetweenModes
        }
    }

    /// 提示带标题（固定口径，三条路径共用同一句主语）
    public var headline: String { "本次更新后应用签名已变化，之前的授权需要重新确认" }

    /// 提示带正文：说明「为什么会这样」，不吓唬人也不轻描淡写
    public var detail: String {
        switch self {
        case .switchedBetweenModes:
            return "新版本换了签名方式，macOS 会把它当成另一个应用，"
                + "已授权的项目需要重新勾选；重新确认一次后即可恢复。"
        case .adhocRebuilt:
            return "当前使用 ad-hoc 签名（无证书）：每次重建都会换一个身份，"
                + "已授权的项目需要重新勾选；配置证书签名后升级不再需要重新授权。"
        case .signedWithCertificateChanged:
            return "签名证书已更换，macOS 认的是证书本身，"
                + "已授权的项目需要重新勾选；同一张证书下的后续升级不受影响。"
        }
    }

    /// 需要用户重新确认的权限（当前未授权的那几项）—— 全绿时返回空数组
    ///
    /// 只在「检测过」的状态上判断：`.unknown` / `.checking` 是读不到结果，
    /// 把它们列进「需要重新确认」等于凭空报故障。
    public static func pendingKinds(in snapshot: SystemPermissionSnapshot) -> [SystemPermissionKind] {
        SystemPermissionKind.allCases.filter { kind in
            switch snapshot.state(for: kind) {
            case .pending, .denied, .unregistered: return true
            case .granted, .unknown, .checking:    return false
            }
        }
    }

    /// 「需要重新确认：屏幕录制、辅助功能」这种一行式清单（无待确认项返回空串）
    public static func pendingSummary(in snapshot: SystemPermissionSnapshot) -> String {
        let kinds = pendingKinds(in: snapshot)
        guard !kinds.isEmpty else { return "" }
        return "需要重新确认：" + kinds.map(\.title).joined(separator: "、")
    }
}

// MARK: - 从系统读数构造（纯函数；系统 API 在 App 层）

public extension SigningIdentity {

    /// ad-hoc：身份判别串就是 cdhash（DR 认它，所以它变 = 身份变）
    static func adhoc(cdhash: String) -> SigningIdentity {
        SigningIdentity(kind: .adhoc, token: cdhash)
    }

    /// 证书签名：身份判别串取证书叶子的 SHA-1
    ///
    /// 为什么统一成十六进制串：ad-hoc 的 cdhash 与证书叶子的 SHA-1 在 DR 里都是
    /// `H"…"` 形态，同一个 token 字段能装两种形态，比较逻辑就只有一条。
    /// - Parameter certificateDER: 证书 DER 字节（`SecCertificateCopyData` 的产物）
    static func certificate(certificateDER: Data) -> SigningIdentity {
        SigningIdentity(kind: .certificate, token: certificateToken(certificateDER))
    }

    /// 证书 DER → 小写十六进制 SHA-1（与 `codesign -d -r-` 输出的 leaf 哈希同形）
    static func certificateToken(_ certificateDER: Data) -> String {
        Insecure.SHA1.hash(data: certificateDER)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - 提示带的合计口径

/// 「签名身份变化」提示带的展示口径 —— 只有真的变了才显示，首启动与正常升级都静默
///
/// 为什么单独一个类型：设置页只该问「要不要显示 / 显示什么」；
/// 判据（哪种变化 / 哪些权限待重授）都在 `SigningIdentityChange` 里，视图不参与任何判断。
public struct SigningIdentityNotice: Equatable, Sendable {

    /// 本次启动读到的签名身份
    public let identity: SigningIdentity
    /// 与上次记录比出来的变化（nil = 首启动 / 没有变化，不提示）
    public let change: SigningIdentityChange?

    public init(identity: SigningIdentity, change: SigningIdentityChange?) {
        self.identity = identity
        self.change = change
    }

    /// 是否要显示提示带
    public var isVisible: Bool { change != nil }

    /// 标题（不可见时空串）
    public var headline: String { change?.headline ?? "" }

    /// 正文（不可见时空串）
    public var detail: String { change?.detail ?? "" }

    /// 「需要重新确认：…」一行（快照全绿时为空串 = 只显示说明 + 打开系统设置）
    public func pendingLine(in snapshot: SystemPermissionSnapshot) -> String {
        guard isVisible else { return "" }
        return SigningIdentityChange.pendingSummary(in: snapshot)
    }

    /// 提示带里的全部说明行（标题 + 正文 + 待确认清单，去掉空串）
    public func lines(in snapshot: SystemPermissionSnapshot) -> [String] {
        guard isVisible else { return [] }
        return [headline, detail, pendingLine(in: snapshot)].filter { !$0.isEmpty }
    }
}

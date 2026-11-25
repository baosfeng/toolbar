import Foundation
import NetworkMonitorCore
import NetworkMonitorUI
import Security

// MARK: - 当前进程的签名身份

/// 读当前进程的签名身份 —— Security framework 的唯一调用点
///
/// 为什么放在 App 层：`SecCodeCopySelf` / `SecCodeCopySigningInformation` 是安全框架的
/// 运行时 API，判定与文案都在 `NetworkMonitorUI` 的纯类型里，这里只做「系统 API → 值类型」。
///
/// 读两份信息：
/// - cdhash（`kSecCodeInfoUnique`）：ad-hoc 下它就是 designated requirement 本身
/// - 证书链（`kSecCodeInfoCertificates`）：有证书时取叶子证书，DR 认的是它的哈希
///
/// ad-hoc 的判定**不看 flags**：flag 只说明「有没有 CS_ADHOC 位」，而真正的分叉在
/// 「DR 认 cdhash 还是认证书叶子」。这里按「有没有证书」判 —— 有证书就用证书身份，
/// 没有就是 ad-hoc，与 `codesign -d -r-` 的输出形态一一对应。
enum SigningIdentityReader {

    /// 读当前进程的签名身份（失败返回 nil：读不到时一律「不提示」，不造结论）
    ///
    /// - Parameter logger: 日志出口（读失败只记 warning，不影响启动）
    ///
    /// 失败不是异常：本应用在 DEBUG 下可能从 "swift run" 直接起（没有签名），
    /// 那种情况下没有任何身份可比，静默跳过比报警更合理。
    static func current(logger: LoggingService) -> SigningIdentity? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            logger.warning("签名身份读取失败：无法取得自身的 SecCode")
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            logger.warning("签名身份读取失败：无法取得静态代码对象")
            return nil
        }
        // 默认 flag 即可拿到完整签名信息（含 cdhash 与证书链）：
        // SecCSFlags 没有「要 cdhash」这类按需位，按需位是 SecCSFlags 之外的 API 参数
        guard let info = try? infoDictionary(of: staticCode, flags: []) else {
            logger.warning("签名身份读取失败：签名信息不可读（未签名的二进制）")
            return nil
        }
        if let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certificates.first {
            let der = SecCertificateCopyData(leaf) as Data
            return SigningIdentity.certificate(certificateDER: der)
        }
        // kSecCodeInfoUnique 是 CFData；转成小写十六进制与 codesign 输出同形
        if let unique = info[kSecCodeInfoUnique as String] as? Data, !unique.isEmpty {
            return SigningIdentity.adhoc(cdhash: unique.map { String(format: "%02x", $0) }.joined())
        }
        logger.warning("签名身份读取失败：既没有证书也没有 cdhash")
        return nil
    }

    /// 取签名信息字典（`SecCSFlags` 由调用方给：只要证书时不必算 cdhash）
    private static func infoDictionary(of code: SecStaticCode,
                                       flags: SecCSFlags) throws -> [String: Any] {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, flags, &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else {
            throw SigningIdentityReadError(status: status)
        }
        return dict
    }
}

// MARK: - 异常

/// 签名信息读取失败（OSStatus 带出来，日志里能直接看到原因）
struct SigningIdentityReadError: Error, CustomStringConvertible {
    let status: OSStatus

    var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
        return "SecCodeCopySigningInformation 失败（\(status)：\(message)）"
    }
}

import CryptoKit
import Foundation

// MARK: - 校验和

/// 安装包校验和 —— 下完先算 SHA-256 再解压，挡住「下了一半 / 被中间页替换」的包
///
/// 为什么值得做：安装器的后果是替换用户正在用的 .app。以前只校验「包内版本号 == tag」，
/// 一个被截断的 dmg 也能在挂载阶段才失败，或者在更糟的情况下让替换后的包起不来。
/// 清单里带 SHA-256 后，下载完成即可判定完整性，失败时当前应用包一个字节都没动。
public enum UpdateChecksum {

    /// 数据的 SHA-256 小写十六进制
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 与期望值比对
    ///
    /// 期望值缺失（旧发布没有校验和 / 发布方没给）时返回 true：
    /// 「没有校验和」不等于「校验失败」，否则兼容通道会整条走不通。
    public static func matches(_ data: Data, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        return sha256Hex(of: data).caseInsensitiveCompare(expected) == .orderedSame
    }
}

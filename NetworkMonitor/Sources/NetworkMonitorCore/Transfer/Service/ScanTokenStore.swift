import Foundation
import Security

// MARK: - 扫码 token 存储

/// 扫码 token 存储 — 纯逻辑、时钟与随机源可注入，便于测试
///
/// 规则（与设计契约一致）：
/// - 每次签发 16 字节随机数 → 32 位小写 hex
/// - 有效期 10 分钟（构造可改），过期条目在读取时惰性清理
/// - 同时活跃上限 5 个，超出后淘汰最旧的一条
public final class ScanTokenStore: @unchecked Sendable {

    /// 一次签发结果
    public struct Issued: Sendable, Equatable {
        public let token: String
        public let issuedAt: Date
        public let expiresAt: Date

        public init(token: String, issuedAt: Date, expiresAt: Date) {
            self.token = token
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
    }

    private struct Entry {
        let token: String
        let issuedAt: Date
        let expiresAt: Date
    }

    private let lock = NSLock()
    private let ttl: TimeInterval
    private let maxActive: Int
    private let now: @Sendable () -> Date
    private let randomBytes: @Sendable () -> [UInt8]
    /// 按签发时间升序（最旧在前）
    private var entries: [Entry] = []

    /// - Parameters:
    ///   - ttl: 有效期（秒）
    ///   - maxActive: 同时活跃上限
    ///   - now: 时钟注入（测试用）
    ///   - randomBytes: 16 字节随机源注入（测试用）
    public init(ttl: TimeInterval = ScanProtocol.tokenTTL,
                maxActive: Int = ScanProtocol.maxActiveTokens,
                now: @escaping @Sendable () -> Date = { Date() },
                randomBytes: (@Sendable () -> [UInt8])? = nil) {
        self.ttl = max(1, ttl)
        self.maxActive = max(1, maxActive)
        self.now = now
        self.randomBytes = randomBytes ?? ScanTokenStore.secureRandomBytes
    }

    // MARK: - 签发与校验

    /// 签发一个新 token（自动淘汰过期条目；仍超限时淘汰最旧）
    public func issue() -> Issued {
        lock.lock()
        defer { lock.unlock() }
        let issuedAt = now()
        purgeLocked(now: issuedAt)
        while entries.count >= maxActive {
            entries.removeFirst()
        }
        var token = ""
        for _ in 0..<4 {
            token = Self.hexEncoded(randomBytes())
            let duplicated = entries.contains { $0.token == token }
            if token.count == ScanProtocol.tokenHexLength, !duplicated { break }
        }
        let expiresAt = issuedAt.addingTimeInterval(ttl)
        entries.append(Entry(token: token, issuedAt: issuedAt, expiresAt: expiresAt))
        return Issued(token: token, issuedAt: issuedAt, expiresAt: expiresAt)
    }

    /// 是否有效（存在、未过期；不消耗）
    public func isValid(_ token: String) -> Bool {
        guard ScanLinkBuilder.isHexToken(token) else { return false }
        lock.lock()
        defer { lock.unlock() }
        let current = now()
        purgeLocked(now: current)
        guard let entry = entries.first(where: { $0.token == token }) else { return false }
        return entry.expiresAt > current
    }

    /// 剩余有效秒数（无效或过期返回 0）
    public func remainingSeconds(_ token: String) -> Int {
        guard ScanLinkBuilder.isHexToken(token) else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        let current = now()
        purgeLocked(now: current)
        guard let entry = entries.first(where: { $0.token == token }) else { return 0 }
        guard entry.expiresAt > current else { return 0 }
        return max(0, Int(entry.expiresAt.timeIntervalSince(current).rounded(.up)))
    }

    /// 当前活跃 token 数量（过期条目不计）
    public func activeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        purgeLocked(now: now())
        return entries.count
    }

    /// 立即作废全部 token（服务停止 / 用户关闭弹窗时可选调用）
    public func revokeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    // MARK: - 内部

    /// 清理过期条目（调用前必须持锁）
    private func purgeLocked(now current: Date) {
        entries.removeAll { $0.expiresAt <= current }
    }

    /// 字节转小写 hex
    private static func hexEncoded(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 系统安全随机数（失败时回落 `SystemRandomNumberGenerator`）
    public static func secureRandomBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
        guard status == errSecSuccess else {
            var generator = SystemRandomNumberGenerator()
            return (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        }
        return bytes
    }
}

import Foundation

// MARK: - /24 网段扫描地址生成

/// 网段扫描纯逻辑 — 由本机 IPv4 推导同网段待探测地址
///
/// 设计文档兜底第 3 级：对本机 `/24` 网段逐 IP 单播 `discover`，
/// 并发 128、单 IP 超时 300ms。地址生成独立成纯函数，便于单测。
public enum SubnetScan {

    /// 单批并发上限（文档值 128）
    public static let batchSize = 128
    /// 单批间隔（文档值 300ms，等价单 IP 超时）
    public static let batchInterval: TimeInterval = 0.3

    /// 由本机 IPv4 生成同 `/24` 网段的其它主机地址（排除本机与网络/广播地址）
    ///
    /// - Parameter localIP: 形如 `192.168.1.23`
    /// - Returns: 253 个地址；输入非法时返回空数组
    public static func hosts(inSubnetOf localIP: String) -> [String] {
        guard let octets = octets(of: localIP) else { return [] }
        let (a, b, c, selfHost) = (octets[0], octets[1], octets[2], octets[3])
        // 排除网络地址 .0 与广播地址 .255
        return (1...254).filter { $0 != selfHost }.map { "\(a).\(b).\(c).\($0)" }
    }

    /// 按并发上限切批（保持原顺序）
    public static func batches(_ hosts: [String], size: Int = batchSize) -> [[String]] {
        guard size > 0 else { return hosts.isEmpty ? [] : [hosts] }
        var result: [[String]] = []
        var index = 0
        while index < hosts.count {
            let end = min(index + size, hosts.count)
            result.append(Array(hosts[index..<end]))
            index = end
        }
        return result
    }

    /// 解析点分十进制 IPv4（每段 0…255，不接受前导零以外的怪值）
    public static func octets(of ip: String) -> [Int]? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard part.count <= 3, let value = Int(part), value >= 0, value <= 255 else { return nil }
            values.append(value)
        }
        return values
    }
}

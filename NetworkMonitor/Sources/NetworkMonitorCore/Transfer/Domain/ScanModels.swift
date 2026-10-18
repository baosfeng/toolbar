import Foundation

// MARK: - 扫码接收协议常量

/// 扫码接收常量 — 绕过 UDP 发现的浏览器直传通道（扫码即用）
public enum ScanProtocol {

    /// 上传页路径（`GET /scan?t=<token>`）
    public static let pagePath = "/scan"
    /// 上传接口路径（`POST /scan/upload?t=<token>&name=<urlencoded>`）
    public static let uploadPath = "/scan/upload"

    /// 单文件大小上限（2 GiB）
    public static let maxFileBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// token 有效期（10 分钟）
    public static let tokenTTL: TimeInterval = 10 * 60
    /// 同时活跃的 token 上限
    public static let maxActiveTokens = 5
    /// token 长度（16 字节 → 32 位 hex）
    public static let tokenHexLength = 32
}

// MARK: - 扫码会话

/// 一次扫码接收的入口信息（UI 展示二维码与地址用）
public struct ScanSessionInfo: Codable, Sendable, Equatable {
    /// 32 位小写 hex
    public var token: String
    /// `http://<局域网IPv4>:<端口>/scan?t=<token>`
    public var url: String
    /// token 失效时刻
    public var expiresAt: Date

    public init(token: String, url: String, expiresAt: Date) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

/// `POST /scan/upload` 成功后的 data
public struct ScanUploadResult: Codable, Sendable, Equatable {
    /// 收件目录中的最终文件名（已清洗、已去重）
    public var savedAs: String

    public init(savedAs: String) {
        self.savedAs = savedAs
    }
}

// MARK: - 链接构造

/// 扫码链接构造 — 必须是局域网 IPv4，回环 / APIPA 地址不参与二维码
public enum ScanLinkBuilder {

    /// 是否为可用于二维码的局域网 IPv4
    public static func isValidLANIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, let value = Int(part), (0...255).contains(value) else {
                return false
            }
            octets.append(value)
        }
        // 回环、0.0.0.0、APIPA（169.254/16）对手机不可达
        if octets[0] == 0 || octets[0] == 127 { return false }
        if octets[0] == 169 && octets[1] == 254 { return false }
        return true
    }

    /// 是否为合法 token（32 位 hex）
    public static func isHexToken(_ token: String) -> Bool {
        token.count == ScanProtocol.tokenHexLength && token.allSatisfy(\.isHexDigit)
    }

    /// 构造上传页地址；IP 非法或端口越界返回 nil
    public static func pageURL(token: String, ip: String?, port: Int) -> String? {
        guard let ip, isValidLANIPv4(ip), (1...65_535).contains(port),
              isHexToken(token) else { return nil }
        return "http://\(ip):\(port)\(ScanProtocol.pagePath)?t=\(token)"
    }
}

// MARK: - 文件名清洗

/// 扫码上传的文件名清洗 — 跨信任边界输入，先取 basename 再限长
public enum ScanFileNaming {

    /// 清洗后文件名的最大 UTF-8 字节数（留出目录与去重后缀余量）
    public static let maxNameBytes = 200

    /// 清洗外部文件名：basename + 去 `..` / 分隔符 / 控制字符 + 限长
    public static func resolve(_ rawName: String) -> String {
        let sanitized = FileNameResolver.sanitize(rawName)
        return truncate(sanitized, maxBytes: maxNameBytes)
    }

    /// 按 UTF-8 字节截断并保留扩展名（避免超长名写盘失败）
    public static func truncate(_ name: String, maxBytes: Int = maxNameBytes) -> String {
        guard maxBytes > 0 else { return name }
        guard name.utf8.count > maxBytes else { return name }

        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        let base = (name as NSString).deletingPathExtension
        let budget = maxBytes - suffix.utf8.count

        if budget <= 0 {
            // 扩展名本身超长：直接按字节截断整串
            return bytePrefix(name, limit: maxBytes)
        }
        var kept = ""
        var used = 0
        for character in base {
            let width = String(character).utf8.count
            if used + width > budget { break }
            kept.append(character)
            used += width
        }
        if kept.isEmpty { return bytePrefix(name, limit: maxBytes) }
        let candidate = kept + suffix
        return candidate.utf8.count <= maxBytes ? candidate : bytePrefix(candidate, limit: maxBytes)
    }

    /// 按 UTF-8 字节前缀解码（找不到合法边界时逐字节回退）
    private static func bytePrefix(_ text: String, limit: Int) -> String {
        var bytes = Array(text.utf8.prefix(limit))
        while !bytes.isEmpty {
            if let value = String(bytes: bytes, encoding: .utf8) { return value }
            bytes.removeLast()
        }
        return "未命名"
    }
}

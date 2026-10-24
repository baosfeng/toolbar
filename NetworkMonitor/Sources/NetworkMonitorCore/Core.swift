import Foundation

// MARK: - Formatting

/// Formats a byte-per-second value into a short string like "1.2M", "340K", "500B".
public func formatSpeedShort(_ bps: Double) -> String {
    let absBps = abs(bps)
    switch absBps {
    case 1_000_000_000...:
        return String(format: "%.1fG", absBps / 1_000_000_000)
    case 1_000_000...:
        return String(format: "%.1fM", absBps / 1_000_000)
    case 1_000...:
        return String(format: "%.0fK", absBps / 1_000)
    default:
        return String(format: "%.0fB", absBps)
    }
}

/// Formats bytes in full form (e.g., "1.2 MB").
///
/// 0 单独处理为 "0 KB"：ByteCountFormatter 对 0 会返回本地化文案 "Zero KB"，
/// 菜单/面板里看着像异常值（实机反馈「Zero KB」）。
public func formatBytesFull(_ bytes: UInt64) -> String {
    guard bytes > 0 else { return "0 KB" }
    let f = ByteCountFormatter()
    f.countStyle = .decimal
    f.includesUnit = true
    f.includesCount = true
    f.allowedUnits = [.useAll]
    f.isAdaptive = true
    return f.string(fromByteCount: Int64(bytes))
}

// MARK: - IP Address

/// Get the local IP address of the primary network interface.
public func getLocalIPAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr = first
    while true {
        let addr = ptr.pointee.ifa_addr
        let name = String(cString: ptr.pointee.ifa_name)

        // Only consider en0/en1 (Wi-Fi / Ethernet), IPv4
        if (name == "en0" || name == "en1"),
           let addr = addr,
           addr.pointee.sa_family == AF_INET
        {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            let cStr = hostname
            return cStr.withUnsafeBufferPointer { buf in
                buf.baseAddress.flatMap { String(validatingCString: $0) }
            }
        }

        guard let next = ptr.pointee.ifa_next else { break }
        ptr = next
    }
    return nil
}

// MARK: - Sparkline (Trend Mini-Chart)

/// Unicode block characters for sparkline, low → high.
private let sparkChars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

/// Generate a sparkline string from an array of values (most recent last).
/// Each value is mapped to one of 8 block heights.
/// Down-samples automatically if values exceed `maxChars`.
/// - Parameters:
///   - values: The data points (0 = smallest, max = largest).
///   - maxChars: Maximum characters in the output (default 20).
/// - Returns: A string of Unicode block characters.
public func sparkline(from values: [Double], maxChars: Int = 20) -> String {
    guard !values.isEmpty else { return "" }

    // Down-sample if too many data points
    let sampled: [Double]
    if values.count > maxChars {
        let step = Double(values.count) / Double(maxChars)
        sampled = (0..<maxChars).map { i -> Double in
            let idx = Int(Double(i) * step)
            return values[min(idx, values.count - 1)]
        }
    } else {
        sampled = values
    }

    let maxVal = sampled.max() ?? 1
    guard maxVal > 0 else { return String(repeating: "▁", count: sampled.count) }

    let levelCount = sparkChars.count
    return sampled.map { v -> Character in
        let idx = min(Int(v / maxVal * Double(levelCount - 1)), levelCount - 1)
        return sparkChars[idx]
    }.map { String($0) }.joined()
}

// MARK: - Process Network Usage

/// Network usage of a single process at a point in time.
public struct ProcessNetUsage: Comparable {
    public let name: String
    public let pid: Int32
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public var total: UInt64 { bytesIn + bytesOut }

    public init(name: String, pid: Int32, bytesIn: UInt64, bytesOut: UInt64) {
        self.name = name
        self.pid = pid
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public static func < (lhs: ProcessNetUsage, rhs: ProcessNetUsage) -> Bool {
        lhs.total < rhs.total
    }
}

/// 解析一行 nettop 原始输出。
///
/// 支持两种列布局：
/// - 默认 -x：time  name.PID  bytes_in  bytes_out  ...（首列为时间戳，后续追加 rx_dupe / re-tx 等列）
/// - -J bytes_in,bytes_out：name.PID  bytes_in  bytes_out（列数固定，无时间戳）
///
/// 进程名可能含空格（如 "Google Chrome H"），因此把末两列之前的全部 token 拼回 name.PID。
/// 表头行、空行、缺列行返回 nil。
public func parseNettopLine(_ line: String) -> ProcessNetUsage? {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 3 else { return nil }

    guard let bytesIn = UInt64(parts[parts.count - 2]),
          let bytesOut = UInt64(parts[parts.count - 1])
    else { return nil }

    // 首列为 HH:MM:SS.ffffff 时间戳时跳过；含两个冒号的进程名几乎不存在
    let firstIsTimestamp = parts[0].filter { $0 == ":" }.count >= 2 && parts[0].first?.isNumber == true
    let nameStart = firstIsTimestamp ? 1 : 0
    let nameEnd = parts.count - 2
    guard nameStart < nameEnd else { return nil }

    let namePid = parts[nameStart..<nameEnd].joined(separator: " ")

    guard let dotIndex = namePid.lastIndex(of: ".") else { return nil }
    let name = String(namePid[namePid.startIndex..<dotIndex])
    let pidStr = String(namePid[namePid.index(after: dotIndex)...])
    guard !name.isEmpty, let pid = Int32(pidStr) else { return nil }

    return ProcessNetUsage(name: name, pid: pid, bytesIn: bytesIn, bytesOut: bytesOut)
}

/// nettop 单次快照参数（回归护栏，勿随意改动）。
///
/// - 不传 `-m`：nettop 默认同时监控 TCP 与 UDP；重复传 `-m` 只保留最后一个（`-m udp`），
///   会让所有 TCP 流量（浏览器、IM、下载器）从进程列表里消失。
/// - `-J bytes_in,bytes_out`：只回两列字节数，列数固定，避免 TCP 模式追加的 rx_dupe / re-tx 把末两列挤成非字节列。
public let nettopSnapshotArguments = ["-P", "-l", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]

/// Run `nettop` once and return per-process cumulative byte counts.
public func runNettopSnapshot() throws -> [ProcessNetUsage] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
    process.arguments = nettopSnapshotArguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0,
          let output = String(data: data, encoding: .utf8)
    else { return [] }

    return output
        .components(separatedBy: "\n")
        .compactMap { parseNettopLine($0) }
}

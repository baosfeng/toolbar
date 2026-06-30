import Foundation
import IOKit.ps

// MARK: - Battery Status

/// Battery state information.
public struct BatteryStatus: Equatable, Sendable {
    public let percentage: Int          // 0-100
    public let isCharging: Bool
    public let isCharged: Bool
    public let timeRemaining: Int       // minutes, 0 = calculating, -1 = unlimited (AC)
    public let powerSource: String      // "AC Power" or "Battery Power"
    public let health: String
    public let cycleCount: Int
    public let temperature: Double      // Celsius, 0 if unavailable

    public var timeLabel: String {
        if isCharged { return "已充满" }
        if isCharging {
            if timeRemaining <= 0 { return "充电中…" }
            let h = timeRemaining / 60
            let m = timeRemaining % 60
            return h > 0 ? "剩余\(h)时\(m)分" : "剩余\(m)分"
        }
        // 使用电池
        if powerSource == "AC Power" { return "已接通电源" }
        if timeRemaining <= 0 { return "计算中…" }
        let h = timeRemaining / 60
        let m = timeRemaining % 60
        return h > 0 ? "剩余\(h)时\(m)分" : "剩余\(m)分"
    }

    public var percentageLabel: String {
        "\(percentage)%"
    }

    public static let unavailable = BatteryStatus(
        percentage: 0, isCharging: false, isCharged: false,
        timeRemaining: -1, powerSource: "—", health: "—",
        cycleCount: 0, temperature: 0
    )
}

/// Monitor battery status using IOKit power sources API.
public final class BatteryMonitor {
    public private(set) var status: BatteryStatus = .unavailable

    public init() {}

    public func poll() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [Any],
              let first = list.first as? [String: Any] else { return }

        let capacity = first["Current Capacity"] as? Int ?? 0
        let maxCap = first["Max Capacity"] as? Int ?? 100
        let percentage = maxCap > 0 ? min(Int(round(Double(capacity) / Double(maxCap) * 100)), 100) : 0
        let isCharging = first["Is Charging"] as? Bool ?? false
        let isCharged = first["Is Charged"] as? Bool ?? false
        let timeToEmpty = first["Time to Empty"] as? Int ?? 0
        let timeToFull = first["Time to Full Charge"] as? Int ?? 0
        let powerSource = first["Power Source State"] as? String ?? "—"
        let health = first["BatteryHealth"] as? String
            ?? (first["Health"] as? String)
            ?? "—"
        let cycleCount = first["CycleCount"] as? Int ?? 0

        let timeRemaining: Int
        if isCharged {
            timeRemaining = -1
        } else if isCharging {
            timeRemaining = timeToFull
        } else if powerSource == "AC Power" {
            timeRemaining = -1
        } else {
            timeRemaining = timeToEmpty
        }

        status = BatteryStatus(
            percentage: percentage,
            isCharging: isCharging,
            isCharged: isCharged,
            timeRemaining: timeRemaining,
            powerSource: powerSource,
            health: health,
            cycleCount: cycleCount,
            temperature: 0
        )
    }
}

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
public func formatBytesFull(_ bytes: UInt64) -> String {
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

/// Parse a single line of `nettop -x` output.
/// Format: `timestamp  name.PID  bytes_in  bytes_out` (space-padded columns).
/// Process names may contain spaces (e.g. "Google Chrome H").
/// Returns nil for header lines or unparseable lines.
public func parseNettopLine(_ line: String) -> ProcessNetUsage? {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 4 else { return nil }

    guard let bytesIn = UInt64(parts[parts.count - 2]),
          let bytesOut = UInt64(parts[parts.count - 1])
    else { return nil }

    let namePidParts = parts[1..<parts.count - 2]
    let namePid = namePidParts.joined(separator: " ")

    guard let dotIndex = namePid.lastIndex(of: ".") else { return nil }
    let name = String(namePid[namePid.startIndex..<dotIndex])
    let pidStr = String(namePid[namePid.index(after: dotIndex)...])
    guard !name.isEmpty, let pid = Int32(pidStr) else { return nil }

    return ProcessNetUsage(name: name, pid: pid, bytesIn: bytesIn, bytesOut: bytesOut)
}

/// Run `nettop` once and return per-process cumulative byte counts.
public func runNettopSnapshot() throws -> [ProcessNetUsage] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
    process.arguments = ["-P", "-m", "tcp", "-m", "udp", "-l", "1", "-x", "-n"]

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

// MARK: - Log Entry

/// A single log entry recording network state at a point in time.
public struct NetworkLogEntry {
    public let timestamp: Date
    public let downSpeed: Double
    public let upSpeed: Double
    public let totalRx: UInt64
    public let totalTx: UInt64
    public let ip: String?

    public init(timestamp: Date, downSpeed: Double, upSpeed: Double,
                totalRx: UInt64, totalTx: UInt64, ip: String?) {
        self.timestamp = timestamp
        self.downSpeed = downSpeed
        self.upSpeed = upSpeed
        self.totalRx = totalRx
        self.totalTx = totalTx
        self.ip = ip
    }

    /// CSV header line.
    public static var csvHeader: String {
        "时间,下载(bps),上传(bps),累计下载,累计上传,IP"
    }

    /// CSV row.
    public var csvRow: String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(df.string(from: timestamp)),\(Int(downSpeed)),\(Int(upSpeed)),\(totalRx),\(totalTx),\(ip ?? "")"
    }
}

import Foundation

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
/// Format: `timestamp\tname.PID\tbytes_in\tbytes_out`
/// Returns nil for header lines or unparseable lines.
public func parseNettopLine(_ line: String) -> ProcessNetUsage? {
    let parts = line.split(separator: "\t", omittingEmptySubsequences: true)
    guard parts.count >= 4 else { return nil }

    // Field 1: name.PID (the PID is everything after the last dot)
    let namePid = String(parts[1])
    guard let dotIndex = namePid.lastIndex(of: ".") else { return nil }
    let name = String(namePid[namePid.startIndex..<dotIndex])
    let pidStr = String(namePid[namePid.index(after: dotIndex)...])
    guard !name.isEmpty,
          let pid = Int32(pidStr),
          let bytesIn = UInt64(parts[2]),
          let bytesOut = UInt64(parts[3])
    else { return nil }

    return ProcessNetUsage(name: name, pid: pid, bytesIn: bytesIn, bytesOut: bytesOut)
}

/// Run `nettop` once and return per-process cumulative byte counts.
/// - Throws: If nettop fails or returns no data.
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

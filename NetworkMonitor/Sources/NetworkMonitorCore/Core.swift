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

import Foundation
import NetworkMonitorCore

/// Simple assertion helper.
func assertEqual(_ actual: String, _ expected: String, file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ \(expected)")
    } else {
        print("❌ \(file):\(line) — expected \"\(expected)\", got \"\(actual)\"")
        exit(1)
    }
}

// Test cases for formatSpeedShort
let cases: [(bps: Double, expected: String)] = [
    (0.0, "0B"),
    (500.0, "500B"),
    (1_500.0, "2K"),
    (42_000.0, "42K"),
    (999_000.0, "999K"),
    (1_200_000.0, "1.2M"),
    (55_000_000.0, "55.0M"),
    (2_300_000_000.0, "2.3G"),
]

print("🧪 Testing formatSpeedShort...")
for (bps, expected) in cases {
    assertEqual(formatSpeedShort(bps), expected)
}
print("\n🎉 所有测试通过！")

import Foundation
import NetworkMonitorCore

// MARK: - Core 纯函数：速度 / nettop / 迷你图 / 字节格式化（从 main.swift 拆出）

// MARK: - 格式化与解析

func runCoreFormattingTests() {
    let speedCases: [(bps: Double, expected: String)] = [
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
    for (bps, expected) in speedCases {
        assertEqual(formatSpeedShort(bps), expected)
    }


    print("\n🧪 Testing parseNettopLine...")

    let line1 = "23:46:47.674162 Google Chrome H.51129                                   16218            4096"
    let r1 = parseNettopLine(line1)
    assertNotNil(r1, "should parse normal line")
    if let r = r1 {
        assertEqual(r.name, "Google Chrome H", "name")
        assertEqual(r.pid, Int32(51129), "pid")
        assertEqual(r.bytesIn, UInt64(16218), "bytesIn")
        assertEqual(r.bytesOut, UInt64(4096), "bytesOut")
    }

    let lineMulti = "23:46:48.123456 Microsoft Excel T.12345                                   98765           43210"
    let rMulti = parseNettopLine(lineMulti)
    assertNotNil(rMulti, "multi-word name")
    if let r = rMulti {
        assertEqual(r.name, "Microsoft Excel T", "multi-word name")
        assertEqual(r.pid, Int32(12345), "multi-word pid")
        assertEqual(r.bytesIn, UInt64(98765), "multi-word bytesIn")
    }

    let line2 = "23:46:47.674152 airportd.649                                                                                   0               0"
    let r2 = parseNettopLine(line2)
    assertNotNil(r2, "should parse zero line")
    if let r = r2 {
        assertEqual(r.name, "airportd")
        assertEqual(r.bytesIn, UInt64(0))
    }

    let line3 = "23:46:47.674157 mDNSResponder.689                                                                  105434952       59651139"
    let r3 = parseNettopLine(line3)
    assertNotNil(r3, "should parse large numbers")
    if let r = r3 {
        assertEqual(r.bytesIn, UInt64(105434952))
        assertEqual(r.bytesOut, UInt64(59651139))
    }

    let header = parseNettopLine("time                                                                            interface   type        bytes_in       bytes_out   rcvsize  tc_class arch")
    assertEqual(header, nil, "header should return nil")

    // -J bytes_in,bytes_out 布局：无时间戳列，这是修复 TCP 流量漏记后实际使用的格式
    let lineJ = "Google Chrome H.51129                                   16218            4096"
    let rJ = parseNettopLine(lineJ)
    assertNotNil(rJ, "-J 布局应能解析")
    if let r = rJ {
        assertEqual(r.name, "Google Chrome H", "-J 布局进程名")
        assertEqual(r.pid, Int32(51129), "-J 布局 pid")
        assertEqual(r.bytesIn, UInt64(16218), "-J 布局 bytesIn")
        assertEqual(r.bytesOut, UInt64(4096), "-J 布局 bytesOut")
    }

    let lineJSimple = "apsd.609                                                                                        6631           38164"
    let rJSimple = parseNettopLine(lineJSimple)
    assertNotNil(rJSimple, "-J 单段进程名应能解析")
    if let r = rJSimple {
        assertEqual(r.name, "apsd", "-J 单段进程名")
        assertEqual(r.pid, Int32(609), "-J 单段 pid")
    }

    let headerJ = parseNettopLine("                                                                                            bytes_in       bytes_out")
    assertEqual(headerJ, nil, "-J 表头应返回 nil")

    // 参数护栏：重复传 -m 只会保留最后一个（-m udp），导致 TCP 流量全部漏记
    assertEqual(nettopSnapshotArguments.contains("-m"), false, "nettop 参数不应传 -m")
    assertEqual(nettopSnapshotArguments.contains("-J"), true, "nettop 参数应固定列")

    let empty = parseNettopLine("")
    assertEqual(empty, nil, "empty should return nil")


    print("\n🧪 Testing sparkline...")

    assertEqual(sparkline(from: []), "", "empty")

    let allSame = sparkline(from: [0, 0, 0])
    assertEqual(allSame, "▁▁▁", "all zero")

    let linear = sparkline(from: [0, 1, 2, 3, 4, 5, 6, 7])
    assertEqual(linear, "▁▂▃▄▅▆▇█", "linear 0-7")

    let single = sparkline(from: [42])
    assertEqual(single, "█", "single peak")

    let desc = sparkline(from: [5, 4, 3, 2, 1, 0])
    assertEqual(desc, "█▆▅▃▂▁", "descending")


    print("\n🧪 Testing formatBytesFull...")
    assertEqual(formatBytesFull(0), "0 KB", "0 字节显示 0 KB（不再出现 Zero KB）")
    assertEqual(formatBytesFull(1024), "1 KB")
    assertEqual(formatBytesFull(1_000_000), "1 MB")
    assertEqual(formatBytesFull(2_500_000_000), "2.5 GB")

}


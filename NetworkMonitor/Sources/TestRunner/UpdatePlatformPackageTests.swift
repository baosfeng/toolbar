import Foundation
import NetworkMonitorCore

// MARK: - 清单按架构的包表（platforms）

/// platforms 表 —— 「用户只下自己那一半」全靠这套解析与回落
///
/// 覆盖的失败面都是真实会踩的：
/// - 发布侧在表里多写一个架构键（universal / 拼错的 arm64_bad），不能让整份清单作废；
/// - 某个架构条目缺下载地址，不能把猜出来的空地址交给下载器；
/// - 表和 asset 打架时以表为准，但表里没有本机架构必须回落到 universal ——
///   「新版本但装不上」比「多下几兆」严重得多。
func runUpdatePlatformPackageTests() {
    testPlatformArtifactsParsing()
    testPlatformFallbackToUniversal()
}

// MARK: 解析

private func testPlatformArtifactsParsing() {
    let json = """
    {
      "schemaVersion": 1,
      "tag": "v1.32.0",
      "version": "1.32.0",
      "notes": "本次更新",
      "asset": {
        "name": "Yilan-1.32.0.dmg",
        "url": "https://github.com/owner/repo/releases/download/v1.32.0/Yilan-1.32.0.dmg",
        "sha256": "AAAA",
        "byteCount": 12000000,
        "architecture": "universal"
      },
      "platforms": {
        "arm64": {
          "name": "Yilan-1.32.0-arm64.dmg",
          "url": "https://github.com/owner/repo/releases/download/v1.32.0/Yilan-1.32.0-arm64.dmg",
          "sha256": "BBBB",
          "byteCount": 6100000
        },
        "x86_64": {
          "name": "Yilan-1.32.0-x86_64.dmg",
          "url": "https://github.com/owner/repo/releases/download/v1.32.0/Yilan-1.32.0-x86_64.dmg",
          "sha256": "CCCC",
          "byteCount": 6800000
        },
        "universal": {
          "name": "ignored.dmg",
          "url": "https://example.com/ignored.dmg"
        },
        "arm64_bad": {
          "name": "缺下载地址.dmg"
        }
      }
    }
    """
    guard let parsed = try? UpdateManifestParser.manifest(fromJSON: Data(json.utf8)) else {
        assertEqual(false, true, "带 platforms 的清单应当解析成功")
        return
    }
    assertEqual(parsed.artifact.name, "Yilan-1.32.0.dmg", "asset 仍是 universal 那份（旧版本照常升级）")
    assertEqual(parsed.platformArtifacts.count, 2,
                "只收认得的架构键（universal / 字段不全的条目丢弃，不让整份清单作废）")
    assertEqual(parsed.artifact(for: .arm64).name, "Yilan-1.32.0-arm64.dmg", "arm64 取单架构包")
    assertEqual(parsed.artifact(for: .x86_64).name, "Yilan-1.32.0-x86_64.dmg", "x86_64 取单架构包")
    assertEqual(parsed.artifact(for: .arm64).sha256, "bbbb", "按架构包同样把校验和归一化成小写")
    assertEqual(parsed.artifact(for: .arm64).byteCount, 6_100_000, "按架构包带字节数")

    // 界面模型必须把表一起带过去，否则 Locator 拿到的还是 universal
    let release = parsed.release
    assertEqual(release.artifact(for: .arm64)?.name, "Yilan-1.32.0-arm64.dmg", "界面模型带上按架构包")
}

// MARK: 回落与选包

private func testPlatformFallbackToUniversal() {
    // 1.31 及更早的清单没有 platforms：行为必须与改造前完全一致
    let legacyJSON = """
    {"schemaVersion": 1, "tag": "v1.31.0", "version": "1.31.0",
     "asset": {"name": "Yilan-1.31.0.dmg", "url": "https://example.com/Yilan-1.31.0.dmg",
               "sha256": "DDDD", "byteCount": 12792314, "architecture": "universal"}}
    """
    guard let legacy = try? UpdateManifestParser.manifest(fromJSON: Data(legacyJSON.utf8)) else {
        assertEqual(false, true, "旧清单仍应解析成功")
        return
    }
    assertEqual(legacy.platformArtifacts.isEmpty, true, "旧清单没有按架构包")
    assertEqual(legacy.artifact(for: .arm64).name, "Yilan-1.31.0.dmg", "缺表时回落到 universal")

    // 发布侧只给了 arm64：Intel 机器不能没包，必须回落到 universal
    let universal = UpdateArtifact(name: "Yilan-1.32.0.dmg",
                                   url: URL(string: "https://example.com/Yilan-1.32.0.dmg")!,
                                   sha256: "eeee",
                                   byteCount: 12_000_000)
    let armOnly = UpdateArtifact(name: "Yilan-1.32.0-arm64.dmg",
                                 url: URL(string: "https://example.com/Yilan-1.32.0-arm64.dmg")!,
                                 sha256: "ffff",
                                 byteCount: 6_100_000)
    let release = UpdateRelease(tagName: "v1.32.0", htmlURL: nil, notes: "", publishedAt: nil,
                                artifact: universal,
                                platformArtifacts: [.arm64: armOnly])

    let armTarget = try? UpdatePackageLocator.target(for: release, architecture: .arm64)
    assertEqual(armTarget?.name, "Yilan-1.32.0-arm64.dmg", "有本机架构 → 下单架构包")
    assertEqual(armTarget?.byteCount, 6_100_000, "下载目标带上单包字节数")
    assertEqual(armTarget?.sha256, "ffff", "下载目标带上单包校验和")

    let intelTarget = try? UpdatePackageLocator.target(for: release, architecture: .x86_64)
    assertEqual(intelTarget?.name, "Yilan-1.32.0.dmg", "清单缺本机架构 → 回落 universal（不能没包）")
    assertEqual(intelTarget?.sha256, "eeee", "回落时用 universal 的校验和")
}

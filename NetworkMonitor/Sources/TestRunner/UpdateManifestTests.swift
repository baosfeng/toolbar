import Foundation
import NetworkMonitorCore

// MARK: - 更新清单

/// 更新清单 / 下载目标 / 校验和 —— 这三条决定了「用户能不能装上正确的包」
///
/// 覆盖的失败面都是发版侧真实会踩的：
/// - 清单 schema 变了但旧版更新器照读（半懂地解析出新字段）；
/// - 资产名与版本不一致（装了 1.30.0 却是 1.29.0 的包）；
/// - 下载被截断（没有校验和时只能到安装阶段才炸）。
func runUpdateManifestTests() {
    testManifestParsing()
    testManifestRejections()
    testBundleTargetSelection()
    testPackageKind()
    testChecksum()
}

// MARK: 解析

private func testManifestParsing() {
    let json = """
    {
      "schemaVersion": 1,
      "tag": "v1.30.0",
      "version": "1.30.0",
      "publishedAt": "2026-11-22T00:00:00Z",
      "minimumSystemVersion": "14.0",
      "pageURL": "https://github.com/owner/repo/releases/tag/v1.30.0",
      "notes": "本次更新",
      "asset": {
        "name": "Yilan-1.30.0.dmg",
        "url": "https://github.com/owner/repo/releases/download/v1.30.0/Yilan-1.30.0.dmg",
        "sha256": "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789",
        "byteCount": 12345678,
        "architecture": "universal"
      }
    }
    """
    guard let parsed = try? UpdateManifestParser.manifest(fromJSON: Data(json.utf8)) else {
        assertEqual(false, true, "合法清单应当解析成功")
        return
    }
    assertEqual(parsed.tag, "v1.30.0", "tag 原样保留")
    assertEqual(parsed.version, "1.30.0", "version 原样保留")
    assertEqual(parsed.notes, "本次更新", "notes 原样保留")
    assertEqual(parsed.minimumSystemVersion, "14.0", "最低系统版本")
    assertEqual(parsed.artifact.name, "Yilan-1.30.0.dmg", "资产名")
    assertEqual(parsed.artifact.sha256,
                "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                "sha256 归一化为小写（比对不因大小写失败）")
    assertEqual(parsed.artifact.byteCount, 12_345_678, "字节数")
    assertEqual(parsed.pageURL?.absoluteString,
                "https://github.com/owner/repo/releases/tag/v1.30.0",
                "发布页地址")
    assertEqual(parsed.publishedAt != nil, true, "发布时间可解析")

    // 清单 → 界面模型：下载对象收敛成唯一 artifact，assets 留空
    let release = parsed.release
    assertEqual(release.tagName, "v1.30.0", "界面模型沿用 tag")
    assertEqual(release.artifact?.name, "Yilan-1.30.0.dmg", "界面模型带上唯一资产")
    assertEqual(release.assets.count, 0, "清单通道不再有资产列表")
}

// MARK: 拒绝路径

private func testManifestRejections() {
    // schema 版本不认识：宁可判失败，也不要半懂地解析（新字段可能改变了语义）
    let futureSchema = """
    {"schemaVersion": 2, "tag": "v1.31.0", "version": "1.31.0",
     "asset": {"name": "Yilan-1.31.0.dmg", "url": "https://example.com/a.dmg"}}
    """
    assertEqual(expectedCheckError(from: futureSchema),
                .invalidResponse("更新清单版本 2 不受支持（当前支持 1）"),
                "未知 schema 版本判失败")

    // 缺 tag：没有版本号的发布无法判定新旧
    let noTag = """
    {"schemaVersion": 1, "version": "1.31.0",
     "asset": {"name": "Yilan-1.31.0.dmg", "url": "https://example.com/a.dmg"}}
    """
    assertEqual(isInvalidResponse(expectedCheckError(from: noTag)), true, "缺 tag 判失败")

    // 缺下载地址：清单给了版本却装不了，必须当场报错而不是等到下载
    let noURL = """
    {"schemaVersion": 1, "tag": "v1.31.0", "version": "1.31.0",
     "asset": {"name": "Yilan-1.31.0.dmg"}}
    """
    assertEqual(isInvalidResponse(expectedCheckError(from: noURL)), true, "缺下载地址判失败")

    // 不是 JSON
    assertEqual(isInvalidResponse(expectedCheckError(from: "not json")), true, "非 JSON 判失败")
}

/// 抽出「解析失败时的错误」，让上面的断言读起来是一条线
private func expectedCheckError(from json: String) -> UpdateCheckError? {
    do {
        _ = try UpdateManifestParser.manifest(fromJSON: Data(json.utf8))
        return nil
    } catch {
        // manifest(fromJSON:) 只抛 UpdateCheckError，catch 里的 error 已是该类型：
        // 曾经的 `error as? UpdateCheckError` 被编译器判为「必然成功」，每轮构建多一条告警。
        return error
    }
}

private func isInvalidResponse(_ error: UpdateCheckError?) -> Bool {
    if case .invalidResponse = error { return true }
    return false
}

// MARK: 下载目标

private func testBundleTargetSelection() {
    // 清单通道优先：唯一 universal dmg，带校验和
    let artifact = UpdateArtifact(name: "Yilan-1.30.0.dmg",
                                  url: URL(string: "https://example.com/Yilan-1.30.0.dmg")!,
                                  sha256: "abc",
                                  byteCount: 42)
    let manifestRelease = UpdateRelease(tagName: "v1.30.0",
                                        htmlURL: nil,
                                        notes: "",
                                        publishedAt: nil,
                                        artifact: artifact)
    let target = try? UpdatePackageLocator.target(for: manifestRelease, architecture: .arm64)
    assertEqual(target?.name, "Yilan-1.30.0.dmg", "清单通道给 dmg，与架构无关")
    assertEqual(target?.sha256, "abc", "下载目标带上校验和")
    assertEqual(target?.byteCount, 42, "下载目标带上字节数")

    // 旧发布回退：没有 artifact 时按架构挑 zip（1.29 及更早）
    let legacy = UpdateRelease(tagName: "v1.29.0",
                               htmlURL: nil,
                               notes: "",
                               publishedAt: nil,
                               assets: [UpdateAsset(name: "Yilan-arm64.app.zip",
                                                    downloadURL: URL(string: "https://example.com/a.zip")),
                                        UpdateAsset(name: "Yilan-x86_64.app.zip",
                                                    downloadURL: URL(string: "https://example.com/b.zip"))])
    let legacyTarget = try? UpdatePackageLocator.target(for: legacy, architecture: .x86_64)
    assertEqual(legacyTarget?.name, "Yilan-x86_64.app.zip", "旧发布按架构挑包")
    assertEqual(legacyTarget?.sha256, nil, "旧发布没有校验和（跳过完整性校验）")

    // 清单不可用回退 API、且发布只有 dmg：必须也能装
    // （否则 update.json 上传失败的那次发布，所有人都卡在「缺少 Yilan-arm64.app.zip」）
    let dmgOnly = UpdateRelease(tagName: "v1.30.0", htmlURL: nil, notes: "", publishedAt: nil,
                                assets: [UpdateAsset(name: "Yilan-1.30.0.dmg",
                                                     downloadURL: URL(string: "https://example.com/a.dmg"),
                                                     digest: "sha256:ABC123")])
    let dmgTarget = try? UpdatePackageLocator.target(for: dmgOnly, architecture: .x86_64)
    assertEqual(dmgTarget?.name, "Yilan-1.30.0.dmg", "回退路径也认 dmg（不按架构挑）")
    assertEqual(dmgTarget?.sha256, "abc123", "API 的 digest 归一化成小写 hex 后当校验和")

    // 只认 sha256 摘要：其它算法宁可当「没有校验和」，也不误判成内容不符
    assertEqual(UpdateAsset(name: "x", downloadURL: nil, digest: "md5:abc").sha256, nil,
                "非 sha256 摘要不当作校验和")

    // 旧发布 + 缺本机架构包 → 明确报 assetMissing，不静默装错架构
    let armOnly = UpdateRelease(tagName: "v1.29.0", htmlURL: nil, notes: "", publishedAt: nil,
                                assets: [UpdateAsset(name: "Yilan-arm64.app.zip",
                                                     downloadURL: URL(string: "https://example.com/a.zip"))])
    var missing: UpdateInstallError?
    do { _ = try UpdatePackageLocator.target(for: armOnly, architecture: .x86_64) }
    catch { missing = error as? UpdateInstallError }
    if case .assetMissing = missing {
        assertEqual(true, true, "缺本机架构包 → assetMissing")
    } else {
        assertEqual(false, true, "缺本机架构包应当报 assetMissing")
    }
}

// MARK: 包形态

private func testPackageKind() {
    assertEqual(UpdatePackageKind(name: "Yilan-1.30.0.dmg"), .diskImage, "dmg 走挂载")
    assertEqual(UpdatePackageKind(name: "Yilan-1.30.0.DMG"), .diskImage, "扩展名大小写不敏感")
    assertEqual(UpdatePackageKind(name: "Yilan-arm64.app.zip"), .zip, "zip 走解压（旧发布）")
    assertEqual(UpdatePackageKind(name: "package"), .zip, "认不出的按 zip（旧行为）")
}

// MARK: 校验和

private func testChecksum() {
    let data = Data("yilan".utf8)
    assertEqual(UpdateChecksum.sha256Hex(of: data).count, 64, "SHA-256 是 64 位十六进制")

    assertEqual(UpdateChecksum.matches(data, expected: UpdateChecksum.sha256Hex(of: data)), true,
                "自己算出的值必须匹配")
    assertEqual(UpdateChecksum.matches(data, expected: UpdateChecksum.sha256Hex(of: data).uppercased()), true,
                "大小写不影响比对")
    assertEqual(UpdateChecksum.matches(data, expected: nil), true,
                "没有校验和时放行（旧发布通道）")
    assertEqual(UpdateChecksum.matches(data, expected: ""), true,
                "空校验和等同没有")

    let other = Data("yilan!".utf8)
    assertEqual(UpdateChecksum.matches(data, expected: UpdateChecksum.sha256Hex(of: other)), false,
                "内容不同必然不匹配")
}

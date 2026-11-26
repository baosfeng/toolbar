import Foundation

// MARK: - 清单 JSON 形状

/// update.json 的 JSON 子集 —— 缺失字段一律按「没给」处理，必填项由解析方逐条判
///
/// 为什么单独成文件：清单里现在有两种位置放安装包（顶层的 asset 与按架构的 platforms 表），
/// 两处字段完全一样。把形状抽出来，解析口径才能只有一份，
/// 否则迟早出现「universal 校验了 SHA-256、按架构那份忘了校验」。
struct ManifestPayload: Decodable {
    let schemaVersion: Int
    let tag: String?
    let version: String?
    let publishedAt: String?
    let minimumSystemVersion: String?
    let pageURL: String?
    let notes: String?
    let asset: Package?
    /// 按架构给出的单包（键为 arm64 / x86_64；1.32 起的清单才有）
    let platforms: [String: Package]?

    /// 单个安装包的字段（asset 与 platforms 表共用同一套）
    struct Package: Decodable {
        let name: String?
        let url: String?
        let sha256: String?
        let byteCount: Int64?
        let architecture: String?
    }
}

// MARK: - 包表解析

/// 清单里的包表 → 安装域类型
///
/// 只做「字段够不够」的判定，不决定「该下哪个」：选包口径在 UpdatePackageLocator，
/// 那里同时要兼容旧发布的 zip 与 API 回退通道。
enum UpdateManifestPackages {

    /// 单个包 → UpdateArtifact（名字与下载地址缺一即视为不可用）
    ///
    /// 为什么不给默认值兜底：缺失意味着发布侧写错了清单，
    /// 拿一个猜出来的地址去下载只会把错误推到用户点安装的那一刻。
    static func artifact(from package: ManifestPayload.Package) -> UpdateArtifact? {
        guard let name = package.name, !name.isEmpty,
              let urlString = package.url, let url = URL(string: urlString) else {
            return nil
        }
        return UpdateArtifact(name: name,
                              url: url,
                              sha256: package.sha256?.lowercased(),
                              byteCount: package.byteCount)
    }

    /// platforms 表 → 按架构的包（认不出的架构键、字段不全的条目一律丢弃）
    ///
    /// 丢条目而不是判失败：多出来的架构键（将来加 `universal` / 别的平台）不该让整份清单作废；
    /// 本机架构缺包的情况由 Locator 回落到 universal 包处理。
    static func artifacts(from table: [String: ManifestPayload.Package]?) -> [UpdateArchitecture: UpdateArtifact] {
        guard let table else { return [:] }
        var result: [UpdateArchitecture: UpdateArtifact] = [:]
        for (key, package) in table {
            guard let architecture = UpdateArchitecture(rawValue: key.lowercased()),
                  let artifact = artifact(from: package) else { continue }
            result[architecture] = artifact
        }
        return result
    }
}

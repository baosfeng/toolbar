import Foundation

// MARK: - 要下载的安装包

/// 安装包 —— 清单里那一个（universal dmg），带校验和
///
/// 为什么单独成类型而不是复用 UpdateAsset：UpdateAsset 是 GitHub Releases API
/// 的原始形状（资产名 + 下载地址），本类型是「我该下哪个、下完怎么验」，属于安装域。
public struct UpdateArtifact: Equatable, Sendable {
    /// 资产名（Yilan-1.30.0.dmg）
    public let name: String
    /// 下载地址
    public let url: URL
    /// 内容的 SHA-256（小写十六进制；缺失表示发布方没给，安装器跳过校验）
    public let sha256: String?
    /// 字节数（缺失表示发布方没给，只用来显示大小）
    public let byteCount: Int64?

    public init(name: String, url: URL, sha256: String? = nil, byteCount: Int64? = nil) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

// MARK: - 更新清单

/// 更新清单 —— 发布时随资产上传的静态更新通道
///
/// 数据源是固定地址 https://github.com/<owner>/<repo>/releases/latest/download/update.json：
/// 这一条 URL 永远指向最新一次发布的资产（GitHub 的 latest 重定向），走 CDN、
/// 不吃 API 额度。相比之下，匿名 /releases/latest 每个 IP 每小时只有 60 次，
/// 用户一多就集体「无法检查」——这是把更新通道从 API 换成静态清单的主要原因。
///
/// 清单里同时带下载地址与 SHA-256，更新器一次请求就能拿到「要不要更新 + 下哪个 + 怎么验」，
/// 不再像以前那样：先查 API 知道版本 → 再从资产列表里挑本机架构的 zip。
///
/// 从 1.32 起清单多一张 `platforms` 表：同一版本按架构各给一个单架构 dmg，
/// 用户只下自己那一半（实测体积少一半）。`asset` 仍是 universal 那份、字段不变，
/// 它同时承担两个作用：旧版本（只认 asset）照常升级；清单缺本机架构时回落到它，
/// 宁可多下几兆也不能出现「新版本但装不上」。
public struct UpdateManifest: Equatable, Sendable {
    /// 清单格式版本（不认识的大版本直接判失败，避免半懂地解析出新字段）
    public let schemaVersion: Int
    /// 发布 tag（v1.30.0）
    public let tag: String
    /// 语义化三段版本（1.30.0）
    public let version: String
    /// 发布时间（解析失败为 nil，不阻塞版本判定）
    public let publishedAt: Date?
    /// 最低系统版本（macOS 14.0）
    public let minimumSystemVersion: String?
    /// 发布页（「打开发布页」的目标）
    public let pageURL: URL?
    /// 发布说明正文（未截断）
    public let notes: String
    /// 要下载的安装包（universal 那份：旧版本与「缺本机架构」时的回落）
    public let artifact: UpdateArtifact
    /// 按架构给出的单包（1.32 起的清单才有；空表示这份清单只有 universal 包）
    public let platformArtifacts: [UpdateArchitecture: UpdateArtifact]

    public init(schemaVersion: Int,
                tag: String,
                version: String,
                publishedAt: Date?,
                minimumSystemVersion: String?,
                pageURL: URL?,
                notes: String,
                artifact: UpdateArtifact,
                platformArtifacts: [UpdateArchitecture: UpdateArtifact] = [:]) {
        self.schemaVersion = schemaVersion
        self.tag = tag
        self.version = version
        self.publishedAt = publishedAt
        self.minimumSystemVersion = minimumSystemVersion
        self.pageURL = pageURL
        self.notes = notes
        self.artifact = artifact
        self.platformArtifacts = platformArtifacts
    }

    /// 本机架构对应的包；清单没给这一架构时回落到 universal 包
    ///
    /// 回落而不是报错：清单是发布侧手写的 JSON，漏一个架构键的代价不该是
    /// 「这批用户彻底升不了级」——他们只是多下几兆。
    public func artifact(for architecture: UpdateArchitecture) -> UpdateArtifact {
        platformArtifacts[architecture] ?? artifact
    }
}

// MARK: - 解析

/// 更新清单解析 —— 把 JSON 变成值，版本号怎么比较不在这里（口径在 UI 的 UpdateVersionLogic）
public enum UpdateManifestParser {

    /// 本版本能读懂的清单格式；发布端升级 schema 时这里必须同步，否则新清单会被静默误读
    public static let supportedSchemaVersion = 1

    /// JSON → UpdateManifest
    ///
    /// - Note: typed throws（SE-0413）：失败种类封闭在 UpdateCheckError 里，
    ///   新增抛出点若不属于这个错误域，编译期即报红。
    public static func manifest(fromJSON data: Data) throws(UpdateCheckError) -> UpdateManifest {
        let payload: ManifestPayload
        do {
            payload = try JSONDecoder().decode(ManifestPayload.self, from: data)
        } catch {
            throw UpdateCheckError.invalidResponse("更新清单不是预期 JSON")
        }
        guard payload.schemaVersion == supportedSchemaVersion else {
            throw UpdateCheckError.invalidResponse(
                "更新清单版本 \(payload.schemaVersion) 不受支持（当前支持 \(supportedSchemaVersion)）")
        }
        guard let tag = payload.tag, !tag.isEmpty else {
            throw UpdateCheckError.invalidResponse("更新清单缺少 tag")
        }
        guard let version = payload.version, !version.isEmpty else {
            throw UpdateCheckError.invalidResponse("更新清单缺少 version")
        }
        guard let asset = payload.asset, let artifact = UpdateManifestPackages.artifact(from: asset) else {
            throw UpdateCheckError.invalidResponse("更新清单缺少可用的下载地址")
        }
        return UpdateManifest(schemaVersion: payload.schemaVersion,
                              tag: tag,
                              version: version,
                              publishedAt: payload.publishedAt.flatMap { try? Date($0, strategy: .iso8601) },
                              minimumSystemVersion: payload.minimumSystemVersion,
                              pageURL: payload.pageURL.flatMap { URL(string: $0) },
                              notes: payload.notes ?? "",
                              artifact: artifact,
                              platformArtifacts: UpdateManifestPackages.artifacts(from: payload.platforms))
    }

    /// JSON → 界面用的 UpdateRelease
    ///
    /// 清单与 API 两条通道在这里汇合：界面只认 UpdateRelease，
    /// 「这份发布从哪来」不影响检查 / 安装逻辑。
    public static func release(fromJSON data: Data) throws(UpdateCheckError) -> UpdateRelease {
        try manifest(fromJSON: data).release
    }
}

// MARK: - 汇成界面模型

extension UpdateManifest {
    /// 清单 → UpdateRelease（assets 留空：下载对象已收敛成 artifact + 按架构的包表）
    public var release: UpdateRelease {
        UpdateRelease(tagName: tag,
                      htmlURL: pageURL,
                      notes: notes,
                      publishedAt: publishedAt,
                      assets: [],
                      artifact: artifact,
                      platformArtifacts: platformArtifacts)
    }
}

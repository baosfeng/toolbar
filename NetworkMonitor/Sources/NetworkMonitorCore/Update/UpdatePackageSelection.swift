import Foundation

// MARK: - 安装架构

/// 安装架构 —— 只用于「旧发布回退」时挑 zip，新发布是 universal 单一包，不需要选
///
/// 为什么留着它：1.29 及更早的发布只有 Yilan-<arch>.app.zip 两个单架构包，
/// 用户从这些版本升级到第一个 universal 版本时，安装器仍要能按架构挑对包。
public enum UpdateArchitecture: String, Equatable, Sendable, CaseIterable {
    /// Apple Silicon
    case arm64
    /// Intel
    case x86_64

    /// macOS 机器串 → 架构（认不出的按 x86_64 处理，与 Rosetta 下 uname -m 一致）
    public static func from(machine: String) -> UpdateArchitecture {
        machine.lowercased().contains("arm64") ? .arm64 : .x86_64
    }

    /// 旧发布的下载资产名（与 1.29 及更早的 release.yml 产物命名一致；新发布不再产出）
    public var assetName: String { "Yilan-\(rawValue).app.zip" }
}

// MARK: - 资产选择（旧发布）

/// 资产选择 —— 旧发布里有两个 zip，按本机架构挑一个
///
/// 为什么单独成纯函数：选错资产的下场是「装上另一个架构的包」，在 Intel 上直接起不来；
/// 这条判据必须能被断言，不能埋在下载代码里。
public enum UpdateAssetSelector {

    /// 从发布的资产名列表里挑出本机架构对应的那个（找不到 → nil，由调用方报「缺少安装包」）
    public static func select(from names: [String], architecture: UpdateArchitecture) -> String? {
        let expected = architecture.assetName.lowercased()
        return names.first { $0.lowercased() == expected }
    }
}

// MARK: - 安装目标

/// 安装目标 —— 到底要下载哪一个文件
///
/// 三种来源收敛成一种形状：
/// - 静态清单（新发布）：唯一 universal dmg，带 SHA-256；
/// - 旧发布 API：按架构挑出的 zip，没有校验和（GitHub 当时不返回 digest）。
public struct UpdatePackageTarget: Equatable, Sendable {
    /// 资产名（Yilan-1.30.0.dmg / Yilan-arm64.app.zip）
    public let name: String
    /// 下载地址
    public let url: URL
    /// 内容的 SHA-256（nil = 没有校验和，安装器跳过校验）
    public let sha256: String?
    /// 字节数（nil = 未知，只影响进度提示文案）
    public let byteCount: Int64?

    public init(name: String, url: URL, sha256: String? = nil, byteCount: Int64? = nil) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    /// 安装包形态（按扩展名判，决定解压还是挂载）
    public var packageKind: UpdatePackageKind {
        UpdatePackageKind(name: name)
    }
}

// MARK: - 安装包形态

/// 安装包形态 —— 展开方式只有两种
public enum UpdatePackageKind: String, Equatable, Sendable {
    /// 磁盘映像（挂载 → 拷贝 → 卸载）
    case diskImage
    /// zip 压缩包（ditto 解压）
    case zip

    /// 按文件名判形态；认不出的按 zip 处理（旧行为，失败时安装器会明确报「解压失败」）
    public init(name: String) {
        self = name.lowercased().hasSuffix(".dmg") ? .diskImage : .zip
    }
}

// MARK: - 定位

/// 从发布里定位要下载的安装包 —— 名字 + 下载地址都有才算可用
public enum UpdatePackageLocator {

    /// 清单通道优先，旧发布回退按架构选 zip
    public static func target(for release: UpdateRelease,
                              architecture: UpdateArchitecture) throws -> UpdatePackageTarget {
        if let artifact = release.artifact {
            return UpdatePackageTarget(name: artifact.name,
                                       url: artifact.url,
                                       sha256: artifact.sha256,
                                       byteCount: artifact.byteCount)
        }
        guard let name = UpdateAssetSelector.select(from: release.assetNames,
                                                    architecture: architecture) else {
            throw UpdateInstallError.assetMissing(expected: "Yilan-<版本>.dmg 或 " + architecture.assetName,
                                                  available: release.assetNames)
        }
        guard let asset = release.assets.first(where: { $0.name == name }),
              let url = asset.downloadURL else {
            throw UpdateInstallError.assetUnavailable(name)
        }
        return UpdatePackageTarget(name: name, url: url)
    }
}

// MARK: - 安装包校验

/// 安装包校验 —— 展开出来的 .app 必须就是「提示的那个版本」
///
/// 校验口径（tag → 版本号的语义化解析）在 UI 库的 UpdateInstallVerification，
/// 那是展示层已有的版本解析；Core 不重复实现，改成注入协议由 App 层组装。
public protocol UpdatePackageVerifying: Sendable {
    /// 校验失败抛 UpdateInstallError；通过则返回包内版本号
    func verify(appURL: URL, tag: String) throws -> String
}

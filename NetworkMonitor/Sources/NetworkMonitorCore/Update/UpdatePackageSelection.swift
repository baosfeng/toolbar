import Foundation

// MARK: - 安装架构

/// 安装包架构 —— 决定下载哪个 zip 资产
///
/// 为什么在 Core 而不是 UI 库：安装器本身在 Core，而依赖方向是「UI → Core」，
/// Core 反向引用 UI 是硬违规；这条判据是领域规则（发布资产怎么选），与文案无关。
public enum UpdateArchitecture: String, Equatable, Sendable, CaseIterable {
    /// Apple Silicon
    case arm64
    /// Intel
    case x86_64

    /// macOS 机器串 → 架构（认不出的按 x86_64 处理，与 Rosetta 下 uname -m 一致）
    public static func from(machine: String) -> UpdateArchitecture {
        machine.lowercased().contains("arm64") ? .arm64 : .x86_64
    }

    /// 下载资产名（与 .github/workflows/release.yml 的产物命名一致）
    public var assetName: String { "Yilan-\(rawValue).app.zip" }
}

// MARK: - 资产选择

/// 资产选择 —— 发布里有两个 zip，按本机架构挑一个
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

// MARK: - 资产定位

/// 从发布资产里挑本机安装包 —— 名字 + 下载地址都有才算可用
public enum UpdatePackageLocator {

    public static func package(for release: UpdateRelease,
                               architecture: UpdateArchitecture) throws -> (name: String, url: URL) {
        guard let name = UpdateAssetSelector.select(from: release.assetNames,
                                                    architecture: architecture) else {
            throw UpdateInstallError.assetMissing(expected: architecture.assetName,
                                                  available: release.assetNames)
        }
        guard let asset = release.assets.first(where: { $0.name == name }),
              let url = asset.downloadURL else {
            throw UpdateInstallError.assetUnavailable(name)
        }
        return (name, url)
    }
}

// MARK: - 安装包校验

/// 安装包校验 —— 解压出来的 .app 必须就是「提示的那个版本」
///
/// 校验口径（tag → 版本号的语义化解析）在 UI 库的 `UpdateInstallVerification`，
/// 那是展示层已有的版本解析；Core 不重复实现，改成注入协议由 App 层组装。
public protocol UpdatePackageVerifying: Sendable {
    /// 校验失败抛 `UpdateInstallError`；通过则返回包内版本号
    func verify(appURL: URL, tag: String) throws -> String
}

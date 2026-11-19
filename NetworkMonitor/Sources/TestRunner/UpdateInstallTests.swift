import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 资产选择 / 版本校验 / 状态文案

func runUpdateInstallLogicTests() {
    print("🧪 Testing 更新安装的纯逻辑（架构 / 资产 / 版本校验 / 文案 / 偏好）...")

    // MARK: 架构与资产

    assertEqual(UpdateArchitecture.from(machine: "arm64"), .arm64, "arm64 机器")
    assertEqual(UpdateArchitecture.from(machine: "x86_64"), .x86_64, "Intel 机器")
    assertEqual(UpdateArchitecture.from(machine: "unknown"), .x86_64, "认不出的按 x86_64（Rosetta 口径）")
    assertEqual(UpdateArchitecture.arm64.assetName, "Yilan-arm64.app.zip", "资产名与发版产物一致")
    assertEqual(UpdateArchitecture.x86_64.assetName, "Yilan-x86_64.app.zip", "Intel 资产名")

    let names = ["Yilan-x86_64.app.zip", "Yilan-arm64.app.zip"]
    assertEqual(UpdateAssetSelector.select(from: names, architecture: .arm64), "Yilan-arm64.app.zip",
                "按架构挑包")
    assertEqual(UpdateAssetSelector.select(from: names, architecture: .x86_64), "Yilan-x86_64.app.zip",
                "Intel 挑包")
    assertEqual(UpdateAssetSelector.select(from: ["dmg-1.zip"], architecture: .arm64), nil,
                "没有对应资产 → nil（由调用方报缺少安装包）")

    // MARK: 版本校验

    assertEqual(UpdateInstallVerification.expectedVersion(fromTag: "v1.29.0"), "1.29.0", "tag → 版本号")
    assertEqual(UpdateInstallVerification.expectedVersion(fromTag: "bad"), nil, "坏 tag → nil，不猜")
    assertEqual(UpdateInstallVerification.matches(bundleVersion: "1.29.0", tag: "v1.29.0"), true,
                "包内版本与 tag 一致")
    assertEqual(UpdateInstallVerification.matches(bundleVersion: "1.28.9", tag: "v1.29.0"), false,
                "包内版本不一致 → 拒绝安装")
    assertEqual(UpdateInstallVerification.matches(bundleVersion: nil, tag: "v1.29.0"), false,
                "读不出版本 → 拒绝安装（不猜）")

    // MARK: 状态文案

    assertEqual(UpdateInstallText.statusLine(.idle), nil, "未开始时状态行不占字")
    assertEqual(UpdateInstallText.statusLine(UpdateInstallState(stage: .downloading)), "正在下载安装包…",
                "下载中文案")
    assertEqual(UpdateInstallText.statusLine(UpdateInstallState(stage: .verifying)), "正在校验安装包…",
                "校验中文案")
    assertEqual(UpdateInstallText.statusLine(UpdateInstallState(stage: .installing)),
                "正在安装（备份当前版本）…", "安装中文案")
    assertEqual(UpdateInstallText.statusLine(UpdateInstallState(stage: .readyToRelaunch)),
                "已安装，即将重启", "待重启文案")
    assertEqual(UpdateInstallText.statusLine(.failed("解压失败")), "安装失败（解压失败）", "失败文案带原因")
    assertEqual(UpdateInstallText.statusLine(.manual("应用目录里没有 一览.app")),
                "需手动安装（应用目录里没有 一览.app）", "手动安装口径")

    assertEqual(UpdateInstallText.buttonTitle(.idle), "下载并安装", "初始按钮")
    assertEqual(UpdateInstallText.buttonTitle(UpdateInstallState(stage: .downloading)), "下载中…", "下载中按钮")
    assertEqual(UpdateInstallText.buttonTitle(.failed("x")), "重试安装", "失败后按钮改重试")
    assertEqual(UpdateInstallText.buttonTitle(.manual("x")), "下载并安装", "手动安装不叫重试")

    assertEqual(UpdateInstallText.canInstall(.idle), true, "未开始可点")
    assertEqual(UpdateInstallText.canInstall(UpdateInstallState(stage: .downloading)), false, "下载中不可重复点")
    assertEqual(UpdateInstallText.canInstall(UpdateInstallState(stage: .readyToRelaunch)), false,
                "待重启时不可重复点")
    assertEqual(UpdateInstallText.canInstall(.failed("x")), true, "失败后可以重试")

    // MARK: 那句必须显示的授权提示

    assertContains(UpdateInstallText.reauthorizationNotice, "屏幕录制", "授权提示点名屏幕录制")
    assertContains(UpdateInstallText.reauthorizationNotice, "辅助功能", "授权提示点名辅助功能")
    assertContains(UpdateInstallText.reauthorizationNotice, "输入监控", "授权提示点名输入监控")
    assertEqual(UpdateInstallText.footnote(UpdateInstallState(stage: .readyToRelaunch), autoInstallEnabled: false),
                UpdateInstallText.reauthorizationNotice, "待重启时显示授权提示")
    assertEqual(UpdateInstallText.footnote(.failed("x"), autoInstallEnabled: true),
                UpdateInstallText.reauthorizationNotice, "失败时同样显示授权提示")
    assertContains(UpdateInstallText.footnote(.idle, autoInstallEnabled: false), "默认关闭",
                   "未开启自动安装时说明它是关的")

    // MARK: 自动安装偏好（默认关）

    let storage = InMemoryStorage()
    let preferences = UpdateCheckPreferences(storage: storage)
    assertEqual(preferences.autoInstallEnabled, false, "缺键 = 关（破坏性动作默认关）")
    preferences.setAutoInstallEnabled(true)
    assertEqual(preferences.autoInstallEnabled, true, "写入后可读回")
    assertEqual(storage.object(forKey: UpdateCheckPreferences.autoInstallKey) != nil, true,
                "键名落库：\(UpdateCheckPreferences.autoInstallKey)")
    preferences.setAutoInstallEnabled(false)
    assertEqual(preferences.autoInstallEnabled, false, "可以再关掉")
    assertEqual(UpdateCheckPreferences.autoInstallKey, "update.autoInstall", "偏好键名")

    // MARK: 发布资产解码

    let json = #"{"tag_name":"v1.29.0","html_url":"https://github.com/baosfeng/toolbar/releases/tag/v1.29.0","body":"x","assets":[{"name":"Yilan-arm64.app.zip","browser_download_url":"https://example.com/a.zip"},{"name":"Yilan-x86_64.app.zip"},{"browser_download_url":"https://example.com/c.zip"}]}"#
    guard let release = try? GitHubUpdateChecker.release(fromJSON: Data(json.utf8)) else {
        assertNotNil(nil as UpdateRelease?, "release 解码失败")
        return
    }
    assertEqual(release.assetNames, ["Yilan-arm64.app.zip", "Yilan-x86_64.app.zip"],
                "只收有名字的资产（无名资产丢弃）")
    assertEqual(release.assets.first?.downloadURL?.absoluteString, "https://example.com/a.zip",
                "下载地址透传")
    assertEqual(release.assets.last?.downloadURL, nil, "缺 browser_download_url → nil")

    // 资产定位：名字与地址都在才算可用
    let located = try? UpdatePackageLocator.package(for: release, architecture: .arm64)
    assertEqual(located?.name, "Yilan-arm64.app.zip", "定位到 arm64 包")
    assertEqual(located?.url.absoluteString, "https://example.com/a.zip", "定位包带回下载地址")
    var missing: UpdateInstallError?
    do { _ = try UpdatePackageLocator.package(for: release, architecture: .x86_64) }
    catch { missing = error as? UpdateInstallError }
    assertEqual(missing, .assetUnavailable("Yilan-x86_64.app.zip"), "有名字没地址 → assetUnavailable")

    print("✅ 更新安装纯逻辑 works")
}
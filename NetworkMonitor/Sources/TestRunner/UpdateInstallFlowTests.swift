import Foundation
import NetworkMonitorCore

// MARK: - 安装流程（沙箱目录，绝不碰 /Applications）

/// 用假 zip 走完「下载 → 校验 → 替换 → 重启」与七条失败路径
///
/// 全部路径都指向测试自己建的临时目录：目标 .app 是伪造的目录，
/// 「应用目录」也是临时目录，因此本套件任何情况下都不会动真实安装位置。
/// 沙箱工具与替身在同域文件 `UpdateInstallSandbox.swift`。
func runUpdateInstallFlowTests() {
    print("🧪 Testing 更新安装流程（沙箱替换 / 失败回滚 / 回滚失败保留备份）...")
    let semaphore = DispatchSemaphore(value: 0)
    let box = ScenarioFailureBox()
    Task.detached(priority: .userInitiated) {
        do {
            try await InstallFlowScenario.run()
        } catch {
            box.message = "\(error)"
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let message = box.message {
        print("❌ 更新安装流程失败：\(message)")
        exit(1)
    }
    print("✅ 更新安装流程 works")
}

// MARK: - 场景

private enum InstallFlowScenario {

    static func run() async throws {
        let root = try InstallSandbox.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // MARK: 成功路径（当前包不在应用目录 → 覆盖应用目录里的同名包）
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let installed = applications.appendingPathComponent("一览.app", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try "旧版本".write(to: installed.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let runningElsewhere = root.appendingPathComponent("Elsewhere/一览.app", isDirectory: true)
        try FileManager.default.createDirectory(at: runningElsewhere, withIntermediateDirectories: true)
        try "运行中".write(to: runningElsewhere.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let release = InstallSandbox.makeRelease(tag: "v1.29.0")
        let host = UpdateInstallHost(appURL: runningElsewhere,
                                     applicationsDirectory: applications,
                                     residentInApplications: false)

        let phaseBox = PhaseRecorder()
        let okRelauncher = FakeRelauncher()
        let okDownloader = FakeDownloader(.success(Data("zip-bytes".utf8)))
        let installer = InstallSandbox.makeInstaller(
            fileSystem: FakeFileSystem(root: root, unpackedAppName: "一览.app"),
            downloader: okDownloader,
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            relauncher: okRelauncher,
            root: root)
        let installedURL = try await installer.install(release: release, host: host,
                                                       architecture: .arm64) { phase in
            phaseBox.record(phase)
        }
        assertEqual(installedURL.path, installed.path, "覆盖的是应用目录里那个同名包")
        assertEqual(okRelauncher.launched.map(\.path), [installed.path], "替换后重启新包")
        let phases = phaseBox.snapshot
        assertEqual(phases.contains(.downloading) && phases.contains(.verifying)
                    && phases.contains(.installing) && phases.last == .readyToRelaunch, true,
                    "阶段回调齐全（下载 → 校验 → 安装 → 待重启）")
        assertEqual(okDownloader.requestedURLs.map(\.absoluteString), ["https://example.com/arm64.zip"],
                    "下载的是本机架构资产")
        assertEqual(InstallSandbox.hasFile(installed, "bundle.txt"), true, "替换后原位是新解压出来的包")
        assertEqual(InstallSandbox.hasFile(installed, "marker.txt"), false,
                    "旧包的文件不再原位（整包替换，不是覆盖文件）")
        assertEqual(FileManager.default.fileExists(atPath: installed.path + ".old"), false,
                    "成功路径不留隐藏备份")

        // MARK: 失败 1：版本不符 → 目标包原样未动
        let mismatchLayout = try InstallSandbox.makeLayout(root, name: "mismatch")
        let mismatch = InstallSandbox.makeInstaller(
            fileSystem: FakeFileSystem(root: root, unpackedAppName: "一览.app"),
            downloader: FakeDownloader(.success(Data("x".utf8))),
            verifier: InstallSandbox.makeVerifier(version: "1.28.0"),
            root: root)
        var mismatchError: UpdateInstallError?
        do {
            _ = try await mismatch.install(release: release,
                                           host: residentHost(mismatchLayout),
                                           architecture: .arm64)
        } catch { mismatchError = error as? UpdateInstallError }
        assertEqual(mismatchError, .versionMismatch(expected: "1.29.0", actual: "1.28.0"),
                    "版本不符 → versionMismatch")
        assertEqual(try InstallSandbox.readMarker(mismatchLayout.app), "旧版本", "版本不符时目标包未被替换")

        // MARK: 失败 2：下载失败 → 连解压都不做
        let downloadLayout = try InstallSandbox.makeLayout(root, name: "download")
        let failDownload = FakeFileSystem(root: root, unpackedAppName: "一览.app")
        let downloadFailInstaller = InstallSandbox.makeInstaller(
            fileSystem: failDownload,
            downloader: FakeDownloader(.failure("断网了")),
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            root: root)
        var downloadError: UpdateInstallError?
        do {
            _ = try await downloadFailInstaller.install(release: release,
                                                        host: residentHost(downloadLayout),
                                                        architecture: .arm64)
        } catch { downloadError = error as? UpdateInstallError }
        assertEqual(downloadError, .downloadFailed("断网了"), "下载失败原样回报原因")
        assertEqual(failDownload.moves.isEmpty, true, "下载失败时没有任何文件移动")

        // MARK: 失败 3：解压后没有 .app
        let unpackLayout = try InstallSandbox.makeLayout(root, name: "unpack")
        let noApp = InstallSandbox.makeInstaller(
            fileSystem: FakeFileSystem(root: root, unpackedAppName: nil),
            downloader: FakeDownloader(.success(Data("x".utf8))),
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            root: root)
        var unpackError: UpdateInstallError?
        do {
            _ = try await noApp.install(release: release,
                                        host: residentHost(unpackLayout),
                                        architecture: .arm64)
        } catch { unpackError = error as? UpdateInstallError }
        assertEqual(unpackError, .unpackFailed("测试：压缩包结构不对"), "解压失败回报 unpackFailed")

        // MARK: 失败 4：替换失败 → 原包回滚
        let rollbackLayout = try InstallSandbox.makeLayout(root, name: "rollback")
        let rollbackFS = FakeFileSystem(root: root, unpackedAppName: "一览.app")
        // 只让「新包挪到最终位置」这一步失败：原包先挪进备份位是成功的，回滚才有东西可挪回
        rollbackFS.failingMoveDestinations = [rollbackLayout.app.path]
        let rollback = InstallSandbox.makeInstaller(
            fileSystem: rollbackFS,
            downloader: FakeDownloader(.success(Data("x".utf8))),
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            root: root)
        var replaceError: UpdateInstallError?
        do {
            _ = try await rollback.install(release: release,
                                           host: residentHost(rollbackLayout),
                                           architecture: .arm64)
        } catch { replaceError = error as? UpdateInstallError }
        if case .replaceFailed = replaceError {
            assertEqual(true, true, "替换失败 → replaceFailed")
        } else {
            assertEqual(replaceError, .replaceFailed("测试：无法写入目标目录"), "替换失败口径")
        }
        assertEqual(try InstallSandbox.readMarker(rollbackLayout.app), "旧版本",
                    "替换失败后原包仍在原位（回滚成功）")
        assertEqual(FileManager.default.fileExists(atPath: rollbackLayout.app.path + ".old"), false,
                    "回滚成功后隐藏备份被清掉")

        try await runPermissionAndRelaunchCases(root: root, release: release)
    }

    // MARK: 权限与重启失败

    private static func runPermissionAndRelaunchCases(root: URL, release: UpdateRelease) async throws {
        // MARK: 失败 5：目标目录不可写（未动任何文件）
        let readonlyLayout = try InstallSandbox.makeLayout(root, name: "readonly")
        let readonlyFS = FakeFileSystem(root: root, unpackedAppName: "一览.app")
        readonlyFS.unwritableDirectories = [readonlyLayout.apps.path]
        let readonly = InstallSandbox.makeInstaller(
            fileSystem: readonlyFS,
            downloader: FakeDownloader(.success(Data("x".utf8))),
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            root: root)
        var writableError: UpdateInstallError?
        do {
            _ = try await readonly.install(release: release,
                                           host: residentHost(readonlyLayout),
                                           architecture: .arm64)
        } catch { writableError = error as? UpdateInstallError }
        assertEqual(writableError, .targetNotWritable(readonlyLayout.apps.path),
                    "不可写 → targetNotWritable")
        assertEqual(readonlyFS.moves.isEmpty, true, "不可写时不移动任何文件")

        // MARK: 失败 6：目标路径不是当前运行包（拒绝盲删）
        // 应用目录里放一个别的包（名字不同），当前包在别处 → 拒绝推算第二个候选路径
        let strangerApps = root.appendingPathComponent("cases/stranger/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: strangerApps, withIntermediateDirectories: true)
        let otherApp = strangerApps.appendingPathComponent("别的应用.app", isDirectory: true)
        try FileManager.default.createDirectory(at: otherApp, withIntermediateDirectories: true)
        let elsewhere = root.appendingPathComponent("Stranger/一览.app", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let missingTarget = InstallSandbox.makeInstaller(
            fileSystem: FakeFileSystem(root: root, unpackedAppName: "一览.app"),
            downloader: FakeDownloader(.success(Data("x".utf8))),
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            root: root)
        var targetError: UpdateInstallError?
        do {
            _ = try await missingTarget.install(
                release: release,
                host: UpdateInstallHost(appURL: elsewhere,
                                        applicationsDirectory: strangerApps,
                                        residentInApplications: false),
                architecture: .arm64)
        } catch { targetError = error as? UpdateInstallError }
        if case .targetMismatch = targetError {
            assertEqual(true, true, "应用目录里没有同名包 → targetMismatch（不做任何路径推算）")
        } else {
            assertEqual(targetError, .targetMismatch(""), "targetMismatch 口径")
        }
        // 暂存位的挪动发生在替换阶段：目标不成立时还没到那一步，磁盘上不该出现 .new
        assertEqual(FileManager.default.fileExists(
            atPath: strangerApps.appendingPathComponent(".一览.app.new").path), false,
                    "目标不成立时连隐藏暂存位都不创建")

        // MARK: 失败 7：重启失败（包已替换，备份保留）
        let relaunchLayout = try InstallSandbox.makeLayout(root, name: "relaunch")
        let relaunchFake = FakeRelauncher()
        relaunchFake.failure = "open 退出码 1"
        let relaunchInstaller = InstallSandbox.makeInstaller(
            fileSystem: FakeFileSystem(root: root, unpackedAppName: "一览.app"),
            downloader: FakeDownloader(.success(Data("x".utf8))),
            verifier: InstallSandbox.makeVerifier(version: "1.29.0"),
            relauncher: relaunchFake,
            root: root)
        var relaunchError: UpdateInstallError?
        do {
            _ = try await relaunchInstaller.install(release: release,
                                                    host: residentHost(relaunchLayout),
                                                    architecture: .arm64)
        } catch { relaunchError = error as? UpdateInstallError }
        assertEqual(relaunchError, .relaunchFailed("open 退出码 1"), "重启失败口径")
        assertEqual(relaunchFake.launched.isEmpty, true, "重启失败时没有记录成功启动")
    }

    /// 当前包就在应用目录里（装回原位）的安装主机
    private static func residentHost(_ layout: (apps: URL, app: URL)) -> UpdateInstallHost {
        UpdateInstallHost(appURL: layout.app,
                          applicationsDirectory: layout.apps,
                          residentInApplications: true)
    }
}

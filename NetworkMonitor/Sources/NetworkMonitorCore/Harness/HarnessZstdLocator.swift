import Foundation

// MARK: - zstd 可执行文件定位

/// zstd 可执行文件定位 —— 探测链集中在一处，供流式读取与设置页诊断共用
///
/// 为什么需要这么一条链（第三方机器「看不到数据」的根因之一）：
/// 由 LaunchServices 启动的 .app 继承系统默认 PATH（/usr/bin:/bin:/usr/sbin:/sbin），
/// **不含 Homebrew 的 /opt/homebrew/bin** —— 用户机器上装了 zstd 也照样 toolMissing。
/// 因此探测顺序固定为：
/// 1. **应用包内自带**（`Contents/Resources/zstd`）：不依赖任何环境变量与安装位置；
/// 2. 固定绝对路径（Apple Silicon / Intel 两个 Homebrew 前缀、MacPorts、系统目录）；
/// 3. 传入的 PATH 逐目录扫描；
/// 4. 最后问一次登录 shell 的真实 PATH（用户可能装在前缀之外）。
///
/// 前两级纯文件系统判定，是「第三方机器能跑」的保证；后两级只是尽力而为。
public enum HarnessZstdLocator {

    /// 包内自带的解压器文件名（`Contents/Resources/zstd`）
    public static let bundledExecutableName = "zstd"

    /// 默认探测的绝对路径
    ///
    /// 顺序即优先级：Homebrew（Apple Silicon）→ Homebrew（Intel）→ MacPorts → 系统目录。
    public static let defaultExecutableCandidates = [
        "/opt/homebrew/bin/zstd",
        "/usr/local/bin/zstd",
        "/opt/local/bin/zstd",
        "/usr/bin/zstd",
    ]

    /// 应用包内的资源目录（非 .app 运行时为 nil，不影响其余探测）
    public static func bundledDirectory(bundle: Bundle = .main) -> String? {
        bundle.resourcePath
    }

    /// 登录 shell 里 `command -v zstd` 的结果（进程内只跑一次）
    ///
    /// .app 的 PATH 与用户终端里的 PATH 是两套：Homebrew 装在非默认前缀、或用户在
    /// `~/.zshrc` 里改过 PATH 时，只有问一次登录 shell 才知道真实位置。
    /// 查不到同样缓存为 nil —— 每轮索引都起一个子进程去问是不可接受的。
    public static let loginShellExecutable: String? = locateViaLoginShell()

    /// 按探测链定位 zstd；找不到返回 nil
    ///
    /// - Parameters:
    ///   - candidates: 绝对路径候选（顺序即优先级）
    ///   - searchPath: PATH 原值（nil = 不扫 PATH）
    ///   - bundledDirectory: 包内资源目录（nil = 没有包内自带）
    ///   - loginShellLookup: 是否允许最后问一次登录 shell（测试关闭它以保证确定性）
    public static func locate(candidates: [String],
                              searchPath: String?,
                              bundledDirectory: String?,
                              loginShellLookup: Bool) -> String? {
        for path in orderedCandidates(candidates: candidates,
                                      searchPath: searchPath,
                                      bundledDirectory: bundledDirectory,
                                      loginShellLookup: loginShellLookup)
        where isExecutable(path) {
            return path
        }
        return nil
    }

    /// 探测过的路径列表（去重并限制条数，避免错误文案过长）
    public static func searchedPaths(candidates: [String],
                                     searchPath: String?,
                                     bundledDirectory: String?,
                                     loginShellLookup: Bool) -> [String] {
        var seen = Set<String>()
        return orderedCandidates(candidates: candidates,
                                 searchPath: searchPath,
                                 bundledDirectory: bundledDirectory,
                                 loginShellLookup: loginShellLookup)
            .filter { seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    /// 探测链展开成一条有序路径列表（locate 与 searchedPaths 共用，避免两套顺序漂移）
    private static func orderedCandidates(candidates: [String],
                                          searchPath: String?,
                                          bundledDirectory: String?,
                                          loginShellLookup: Bool) -> [String] {
        var paths: [String] = []
        if let bundledDirectory, !bundledDirectory.isEmpty {
            paths.append(bundledDirectory + "/" + bundledExecutableName)
        }
        paths.append(contentsOf: candidates)
        if let searchPath {
            for directory in searchPath.split(separator: ":") where !directory.isEmpty {
                paths.append(String(directory) + "/" + bundledExecutableName)
            }
        }
        if loginShellLookup, let shellPath = loginShellExecutable {
            paths.append(shellPath)
        }
        return paths
    }

    /// 是否是可执行文件（判定收敛到这里，不要在调用点各写一遍）
    public static func isExecutable(_ path: String) -> Bool {
        !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
    }

    /// 问登录 shell 要 zstd 路径（失败一律返回 nil）
    private static func locateViaLoginShell() -> String? {
        let shell = "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v zstd"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return isExecutable(text) ? text : nil
    }
}

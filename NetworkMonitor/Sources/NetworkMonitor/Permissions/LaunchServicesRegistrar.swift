import AppKit
import NetworkMonitorCore

// MARK: - LaunchServices 登记

/// 把本应用包重新登记进 LaunchServices —— 让「系统设置」的权限清单能搜到它
///
/// 为什么需要：自签名 / 手工部署的 .app 没走过安装流程时，LaunchServices 库里可能没有
/// 这个包的记录，系统设置的「+」选择框与 Spotlight 都会找不到它（用户口径：
/// 「都不支持把我们的 app 放入进去，还要到系统应用里面去选」）。`lsregister -f`
/// 强制按路径重建这条记录，是唯一不依赖安装器的补救手段。
///
/// 失败只记日志、不阻塞启动：登记失败不影响应用本身可用，只是清单里可能仍搜不到。
enum LaunchServicesRegistrar {

    /// lsregister 的绝对路径（不在 PATH 里，只能按固定路径调用）
    static let toolPath = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks"
        + "/LaunchServices.framework/Versions/A/Support/lsregister"

    /// 异步登记（启动装配阶段调用，不阻塞首帧）
    static func registerInBackground(appPath: String, logger: LoggingService) {
        Task.detached(priority: .utility) {
            let result = register(appPath: appPath)
            switch result {
            case .success:
                logger.info("LaunchServices 已登记应用包：\(appPath)")
            case .failure(let reason):
                logger.warning("LaunchServices 登记失败（不影响应用本身可用）：\(reason)")
            }
        }
    }

    /// 同步登记（供组合根与命令行自证复用）
    ///
    /// - Parameter appPath: 应用包绝对路径
    /// - Returns: 成功，或带原因的失败
    static func register(appPath: String) -> Result<Void, LaunchServicesError> {
        guard FileManager.default.fileExists(atPath: toolPath) else {
            return .failure(.toolMissing(toolPath))
        }
        guard FileManager.default.fileExists(atPath: appPath) else {
            return .failure(.appMissing(appPath))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["-f", appPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return .failure(.nonzeroExit(Int(process.terminationStatus)))
        }
        return .success(())
    }
}

// MARK: - 失败原因

/// 登记失败的三种情形 —— 各自给一句能定位的说明，不吞成一句「失败了」
enum LaunchServicesError: Error, Equatable {
    /// 系统里没有 lsregister（非标准系统布局）
    case toolMissing(String)
    /// 应用包不存在（开发态尚未打包）
    case appMissing(String)
    /// 进程起不来（权限 / 资源不足）
    case launchFailed(String)
    /// lsregister 返回非 0
    case nonzeroExit(Int)

    /// 日志用的中文说明
    var message: String {
        switch self {
        case .toolMissing(let path):   return "找不到 lsregister（\(path)）"
        case .appMissing(let path):    return "应用包不存在（\(path)），开发态未打包时属正常"
        case .launchFailed(let reason): return "lsregister 启动失败（\(reason)）"
        case .nonzeroExit(let code):   return "lsregister 退出码 \(code)"
        }
    }
}

extension LaunchServicesRegistrar {

    /// 失败原因的中文说明（日志与回报共用）
    static func describe(_ result: Result<Void, LaunchServicesError>) -> String {
        switch result {
        case .success: return "exit 0"
        case .failure(let error): return error.message
        }
    }
}

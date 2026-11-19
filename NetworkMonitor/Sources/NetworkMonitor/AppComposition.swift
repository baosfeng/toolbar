import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 装配环境

/// 装配阶段之间传递的共享状态
///
/// 现在只有组合根本身（各阶段按声明把装配出的服务写回它的属性），
/// 但阶段签名先定成 inout 环境：以后需要跨阶段传值（如把某个连接句柄直接递给下个阶段）
/// 时，加字段即可，不必改所有阶段签名。
struct AppEnvironment {
    let coordinator: AppCoordinator
}

// MARK: - 装配阶段

/// 一个装配阶段 = 声明（名字 + 依赖）+ 执行闭包 + 可选的反向清理闭包
///
/// 顺序**不再由代码位置决定**：执行顺序由 `requires` 拓扑排序给出（见 AssembleTopology），
/// 停止顺序由装配器按启动顺序逆序调用各阶段的 teardown。
struct AssembleStage {
    let name: String
    /// 依赖的阶段名：这些阶段必须全部先于本阶段执行
    let requires: [String]
    /// 启动动作（依赖已就位）
    let run: (inout AppEnvironment) throws -> Void
    /// 停止动作（由装配器按启动顺序逆序调用；nil = 该阶段无需清理）
    let teardown: ((AppEnvironment) -> Void)?

    init(name: String,
         requires: [String] = [],
         run: @escaping (inout AppEnvironment) throws -> Void,
         teardown: ((AppEnvironment) -> Void)? = nil) {
        self.name = name
        self.requires = requires
        self.run = run
        self.teardown = teardown
    }

    /// 只保留声明部分交给纯排序器（闭包不进 UI target，故排序在 UI target 做）
    var spec: AssembleStageSpec { AssembleStageSpec(name: name, requires: requires) }
}

// MARK: - 装配器

/// 声明式装配器 —— 组合根只声明阶段与依赖，顺序与清理由它负责
///
/// 失败口径：声明有错（重名 / 缺依赖 / 成环）**启动即失败**——logger.error 打出带名字的
/// 明确原因并抛 `AppAssemblyError`，不静默跳过（静默跳过会得到一个「少了某条链路但看起来
/// 正常」的进程，比直接崩更难查）。
@MainActor
final class AppComposition {
    let stages: [AssembleStage]
    private let logger: LoggingService
    /// 已实际执行过的阶段（停止时只逆序清理它们，未跑到的阶段不清理）
    private(set) var executed: [AssembleStage] = []

    init(stages: [AssembleStage], logger: LoggingService) {
        self.stages = stages
        self.logger = logger
    }

    /// 解析启动顺序；声明有错即抛错（不执行任何阶段）
    func resolveOrder() throws -> [String] {
        switch AssembleTopology.plan(stages.map(\.spec)) {
        case .success(let order):
            return order
        case .failure(let error):
            logger.error(error.message)
            throw AppAssemblyError.invalidDeclaration(error)
        }
    }

    /// 按拓扑顺序执行全部阶段
    func run(in environment: inout AppEnvironment) throws {
        let order = try resolveOrder()
        let byName = Dictionary(uniqueKeysWithValues: stages.map { ($0.name, $0) })
        executed = []
        for name in order {
            guard let stage = byName[name] else {
                let error = AssemblePlanError.missingDependency(stage: name, missing: name)
                logger.error(error.message)
                throw AppAssemblyError.invalidDeclaration(error)
            }
            logger.debug("装配阶段开始：\(stage.name)")
            try stage.run(&environment)
            executed.append(stage)
        }
    }

    /// 按启动顺序**逆序**调用各阶段 teardown（执行失败时只清理已执行过的）
    func teardown(in environment: AppEnvironment) {
        for name in AssembleTopology.teardownOrder(executed.map(\.name)) {
            guard let stage = executed.first(where: { $0.name == name }),
                  let teardown = stage.teardown else { continue }
            teardown(environment)
        }
        executed = []
    }
}

// MARK: - 装配错误

/// 装配失败 —— 两类：声明有错（重名 / 缺依赖 / 成环）、阶段缺前提（依赖阶段跑过却没产出实例）
///
/// 两类都带阶段名与缺失对象名：装配链路的错误最怕「只说失败、不说谁缺什么」。
enum AppAssemblyError: Error, CustomStringConvertible {
    case invalidDeclaration(AssemblePlanError)
    case missingService(stage: String, detail: String)

    var description: String {
        switch self {
        case .invalidDeclaration(let error):
            return "应用装配失败：\(error.message)"
        case .missingService(let stage, let detail):
            return "应用装配失败：阶段「\(stage)」缺少依赖——\(detail)"
        }
    }
}

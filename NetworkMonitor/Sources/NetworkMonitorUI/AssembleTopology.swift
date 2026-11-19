import Foundation

// MARK: - 装配拓扑（声明 + 依赖排序）

/// 一个装配阶段的**声明**（只有元数据，执行闭包在 App 侧）
///
/// 为什么要它：组合根过去靠「代码位置 + 注释」维持启动顺序，新增模块必须靠人记住
/// 两处（start() 的顺序与 stop() 的逆序）。这里把顺序变成可判定的数据，
/// 排序结果由算法给出，声明错位（重名 / 缺依赖 / 成环）在启动时立刻带出名字失败。
///
/// 纯值放在 UI target：TestRunner 能直接断言排序与失败口径，不必 import 可执行 target。
public struct AssembleStageSpec: Sendable, Equatable {
    /// 阶段名（唯一标识，也是依赖引用用的名字）
    public let name: String
    /// 依赖的阶段名：这些阶段必须全部先于本阶段执行
    public let requires: [String]

    public init(name: String, requires: [String] = []) {
        self.name = name
        self.requires = requires
    }
}

/// 装配声明错误 —— 三类都是启动期即失败，不做「跳过这个阶段继续启动」
public enum AssemblePlanError: Error, Equatable, CustomStringConvertible {
    /// 阶段名重复（重名会让依赖解析到错误的阶段，必须当场拒绝）
    case duplicateName(String)
    /// 依赖的阶段名不存在
    case missingDependency(stage: String, missing: String)
    /// 依赖成环（列出所有卡在环上的阶段）
    case cycle(stages: [String])

    /// 面向人的明确失败文案：一律带出阶段名，否则排查只能靠猜
    public var message: String {
        switch self {
        case .duplicateName(let name):
            return "装配阶段名重复：\(name)（阶段名必须唯一）"
        case .missingDependency(let stage, let missing):
            return "装配阶段「\(stage)」依赖的阶段「\(missing)」不存在"
        case .cycle(let stages):
            let path = (stages + stages.prefix(1)).joined(separator: " → ")
            return "装配依赖成环：\(path)"
        }
    }

    public var description: String { message }
}

public enum AssembleTopology {

    /// 稳定拓扑排序
    ///
    /// 规则：每轮从**声明序**里挑第一个「依赖已全部就位」的阶段。
    /// 因此同层（互不依赖）阶段保持声明序；已按依赖写好的声明表，排序结果 == 声明序本身
    /// —— 这正是不改变启动顺序的前提。
    public static func plan(_ specs: [AssembleStageSpec]) -> Result<[String], AssemblePlanError> {
        // 重名先判：后面按名字建索引，重名会让依赖静默解析到另一个阶段
        var seenNames = Set<String>()
        for spec in specs where !seenNames.insert(spec.name).inserted {
            return .failure(.duplicateName(spec.name))
        }

        let byName = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0) })
        // 缺依赖：直接点名「谁的哪个依赖不存在」
        for spec in specs {
            for dependency in spec.requires where byName[dependency] == nil {
                return .failure(.missingDependency(stage: spec.name, missing: dependency))
            }
        }

        var ordered: [String] = []
        var satisfied = Set<String>()
        var pending = specs

        while !pending.isEmpty {
            var picked: Int?
            for (index, spec) in pending.enumerated()
            where spec.requires.allSatisfy({ satisfied.contains($0) }) {
                picked = index
                break
            }
            guard let index = picked else {
                // 剩下的阶段互相等待：只可能是成环（缺依赖已在上面判掉）
                return .failure(.cycle(stages: pending.map(\.name)))
            }
            let stage = pending.remove(at: index)
            ordered.append(stage.name)
            satisfied.insert(stage.name)
        }
        return .success(ordered)
    }

    /// 停止顺序 = 启动顺序的镜像（装配器据此逆序调用各阶段 teardown）
    public static func teardownOrder(_ order: [String]) -> [String] {
        order.reversed()
    }
}

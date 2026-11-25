import Foundation
import NetworkMonitorCore

// MARK: - 阶段清单（界面口径）

/// 阶段清单的一行 —— 五段固定，用户看的是「在哪、还剩几段」
///
/// 为什么 5 行而不是 4 行（Core 只有 downloading / verifying / installing / readyToRelaunch）：
/// 校验与展开在 Core 里同属 verifying，但前者毫秒级、后者要挂 dmg 再拷 16MB，
/// 两者合成一行时用户看到的是「校验」卡好几秒 —— 拆开才解释得清。
public enum UpdateInstallStepKind: String, Equatable, Sendable, CaseIterable {
    /// 下载安装包
    case download
    /// 校验完整性（SHA-256）
    case verify
    /// 展开安装包（挂载 / 解压 / 拷贝 / 卸载）
    case expand
    /// 替换应用（备份 + 原子换包）
    case replace
    /// 重启应用
    case relaunch

    /// 行标题（阶段列表左侧那一列）
    public var title: String {
        switch self {
        case .download: return "下载安装包"
        case .verify: return "校验完整性"
        case .expand: return "展开安装包"
        case .replace: return "替换应用"
        case .relaunch: return "重启应用"
        }
    }
}

/// 一行阶段的四态 —— 只有「当前」与「失败」着色，其余靠勾与灰
public enum UpdateInstallStepState: Equatable, Sendable {
    /// 已完成（打勾）
    case done
    /// 进行中（高亮 + 当前行文案）
    case current
    /// 还没到
    case pending
    /// 卡在这一行（红）
    case failed
}

/// 阶段清单里的一行（供视图直接渲染）
public struct UpdateInstallStepItem: Equatable, Sendable {
    public let kind: UpdateInstallStepKind
    public let state: UpdateInstallStepState

    public init(kind: UpdateInstallStepKind, state: UpdateInstallStepState) {
        self.kind = kind
        self.state = state
    }
}

// MARK: - 进度文案

/// 安装进度文案 —— 阶段清单 / 百分比 / 字节详情 / 剩余时间（纯函数，可被 TestRunner 断言）
///
/// 派生全部在这里：视图只做「读字符串 → 赋值」，改口径不用碰 AppKit 代码。
public enum UpdateInstallProgressText {

    /// 阶段清单（idle 时返回空数组 = 整块隐藏）
    ///
    /// - Parameters:
    ///   - stage: 当前阶段
    ///   - subStep: 展开阶段的子步骤（nil = 还在校验，或不是展开段）
    ///   - failedAt: 失败时卡在哪一段（nil = 不知道，此时不标红任何一行）
    public static func steps(stage: UpdateInstallStage,
                             subStep: UpdateUnpackStep? = nil,
                             failedAt: UpdateInstallStage? = nil) -> [UpdateInstallStepItem] {
        guard stage != .idle else { return [] }
        let order = UpdateInstallStepKind.allCases
        // 失败：只把卡住那一行标红，前面已完成的照常打勾 —— 「卡在哪」就是靠这个读出来的
        if stage == .failed {
            let stuck = row(for: failedAt, subStep: subStep)
            return order.map { kind in
                guard let stuck else { return UpdateInstallStepItem(kind: kind, state: .pending) }
                if kind == stuck { return UpdateInstallStepItem(kind: kind, state: .failed) }
                return UpdateInstallStepItem(kind: kind,
                                             state: index(kind) < index(stuck) ? .done : .pending)
            }
        }
        guard let current = row(for: stage, subStep: subStep) else {
            return order.map { UpdateInstallStepItem(kind: $0, state: .pending) }
        }
        return order.map { kind in
            let position = index(kind)
            if kind == current { return UpdateInstallStepItem(kind: kind, state: .current) }
            return UpdateInstallStepItem(kind: kind, state: position < index(current) ? .done : .pending)
        }
    }

    /// 当前阶段的补充说明（阶段列表下方那行小字；nil = 不用说明）
    public static func stepDetail(stage: UpdateInstallStage, subStep: UpdateUnpackStep?) -> String? {
        switch stage {
        case .verifying:
            switch subStep {
            case .mountingDiskImage: return "正在挂载安装包…"
            case .copyingApp: return "正在拷贝应用…"
            case .detachingDiskImage: return "正在卸载安装包…"
            case .unzipping: return "正在解压安装包…"
            case nil: return "正在核对 SHA-256 与版本号…"
            }
        case .installing: return "先备份当前版本，再原子换包"
        case .readyToRelaunch: return "新版本已就位，即将重启"
        case .downloading, .idle, .failed: return nil
        }
    }

    /// 百分比文案（"42%"；没有分母为 nil —— 界面此时走不定态，不给假百分比）
    public static func percentText(_ progress: UpdateDownloadProgress?) -> String? {
        guard let percent = progress?.percent else { return nil }
        return "\(percent)%"
    }

    /// 详情行：「已下载 6.2 MB / 12.2 MB · 2.1 MB/s · 剩余约 3 秒」
    ///
    /// 三段各自「有才写」：没有分母就只写已下载，没有速度就省掉速度与剩余，
    /// 不拼占位符 —— 一行里出现三个「—」比不显示更难看。
    public static func detailText(_ progress: UpdateDownloadProgress?) -> String? {
        guard let progress, progress.receivedBytes > 0 else { return nil }
        var parts = ["已下载 " + bytes(progress.receivedBytes) + totalSuffix(progress.totalBytes)]
        if progress.bytesPerSecond > 0 {
            parts.append(bytes(Int64(progress.bytesPerSecond)) + "/s")
        }
        if let remaining = progress.estimatedSecondsRemaining, progress.bytesPerSecond > 0 {
            parts.append("剩余" + duration(remaining))
        }
        return parts.joined(separator: " · ")
    }

    /// 进度条的不定态判据（没有分母 / 已到 100% 后切到下一段）
    public static func isIndeterminate(_ progress: UpdateDownloadProgress?) -> Bool {
        progress?.fraction == nil
    }

    // MARK: 私有

    /// 阶段 → 清单行（verifying 要按子步骤拆成「校验」与「展开」两行）
    private static func row(for stage: UpdateInstallStage?,
                            subStep: UpdateUnpackStep?) -> UpdateInstallStepKind? {
        switch stage {
        case .downloading: return .download
        case .verifying: return subStep == nil ? .verify : .expand
        case .installing: return .replace
        case .readyToRelaunch: return .relaunch
        case .idle, .failed, nil: return nil
        }
    }

    private static func index(_ kind: UpdateInstallStepKind) -> Int {
        UpdateInstallStepKind.allCases.firstIndex(of: kind) ?? 0
    }

    /// 字节文本（1000 进位、与 Finder 一致；复用 Core 的唯一实现，不另写单位换算）
    private static func bytes(_ value: Int64) -> String {
        ByteFormatting.fullDecimal(UInt64(max(0, value)))
    }

    private static func totalSuffix(_ total: Int64?) -> String {
        guard let total, total > 0 else { return "" }
        return " / " + bytes(total)
    }

    /// 剩余时间：1 分钟内给秒，超过给分（"约 3 秒" / "约 1 分 5 秒"）
    private static func duration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        guard rounded >= 1 else { return "不到 1 秒" }
        guard rounded >= 60 else { return "约 \(rounded) 秒" }
        let minutes = rounded / 60
        let rest = rounded % 60
        return rest == 0 ? "约 \(minutes) 分" : "约 \(minutes) 分 \(rest) 秒"
    }
}

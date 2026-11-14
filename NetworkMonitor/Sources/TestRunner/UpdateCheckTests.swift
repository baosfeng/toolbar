import Foundation
import NetworkMonitorUI

// MARK: - 更新检查：版本比较与状态文案

/// 版本比较与状态机守卫
///
/// 这一组是「新版本检测」的纯口径：版本号怎么解析、怎么比、五种状态各显示什么。
/// 全部可在 TestRunner 里断言，不需要网络、不需要 AppKit。
func runUpdateVersionTests() {
    print("🧪 Testing update version logic (semver compare / tag / prerelease / invalid)...")

    // MARK: 为什么不能用字符串比较（反例本身也断言）

    assertEqual("1.24.9" > "1.24.10", true,
                "字典序把 1.24.9 判成比 1.24.10 大 —— 这就是必须按数值比较的原因")

    // MARK: 解析

    guard case .success(let v12410) = UpdateVersionLogic.parse("1.24.10") else {
        print("❌ 1.24.10 解析失败"); exit(1)
    }
    assertEqual(v12410.major, 1, "主版本")
    assertEqual(v12410.minor, 24, "次版本")
    assertEqual(v12410.patch, 10, "修订号")
    assertEqual(v12410.displayText, "1.24.10", "展示文本")
    assertEqual(v12410.isPrerelease, false, "正式版不是预发布")

    guard case .success(let fromTag) = UpdateVersionLogic.version(fromTag: "v1.24.10") else {
        print("❌ v1.24.10 解析失败"); exit(1)
    }
    assertEqual(fromTag, v12410, "tag 的 v 前缀被容忍，与无前缀同值")

    guard case .success(let withBuild) = UpdateVersionLogic.parse("1.24.10+build.7") else {
        print("❌ 1.24.10+build.7 解析失败"); exit(1)
    }
    assertEqual(withBuild, v12410, "构建元数据不参与比较")

    guard case .success(let spaced) = UpdateVersionLogic.parse("  v1.24.10  ") else {
        print("❌ 带空白 v1.24.10 解析失败"); exit(1)
    }
    assertEqual(spaced, v12410, "前后空白被容忍")

    // MARK: 比较（必含 1.24.9 < 1.24.10 经典反例）

    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.9", latest: "1.24.10"), true,
                "1.24.9 → 1.24.10 是新版本（字符串比较会漏判）")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.10", latest: "1.24.9"), false,
                "反向不是更新")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.2", latest: "1.24.2"), false,
                "相等版本不算更新")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.99", latest: "1.25.0"), true,
                "次版本优先于修订号（1.25.0 > 1.24.99）")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.25.0", latest: "1.24.99"), false,
                "次版本小的不是更新，哪怕修订号更大")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "0.9.99", latest: "1.0.0"), true,
                "主版本优先于其余段")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "v1.24.2", latest: "v1.24.10"), true,
                "两端都带 v 前缀时同样按数值比较")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.2", latest: "v1.24.10"), true,
                "一侧带 v 前缀不影响判定")

    // MARK: 预发布

    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3", latest: "1.24.3-beta.1"), false,
                "预发布小于正式版：1.24.3-beta.1 < 1.24.3")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-beta.1", latest: "1.24.3"), true,
                "从预发布升到正式版算更新")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-beta.1", latest: "1.24.3-beta.2"), true,
                "预发布数字标识符按数值比较（beta.1 → beta.2）")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-beta.10", latest: "1.24.3-beta.9"), false,
                "beta.10 大于 beta.9，不能按字符串比")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-alpha", latest: "1.24.3-beta"), true,
                "字母标识符按字典序（alpha < beta）")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-beta", latest: "1.24.3-beta.1"), true,
                "前缀相同则标识符多的更大（beta < beta.1）")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-1", latest: "1.24.3-alpha"), true,
                "数字标识符小于字母标识符（1 < alpha），所以 alpha 那版更新")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.3-alpha", latest: "1.24.3-1"), false,
                "反向：字母标识符大于数字标识符")

    // MARK: 非法输入（明确失败，不当 0）

    assertEqual(UpdateVersionLogic.parse(""), .failure(.empty), "空串是明确的解析失败")
    assertEqual(UpdateVersionLogic.parse("   "), .failure(.empty), "全空白同样是空")
    assertEqual(UpdateVersionLogic.parse("1.24"), .failure(.notThreeSegments("1.24")),
                "只有两段 → 解析失败（不静默补 0）")
    assertEqual(UpdateVersionLogic.parse("1"), .failure(.notThreeSegments("1")),
                "只有一段 → 解析失败")
    assertEqual(UpdateVersionLogic.parse("1.24.2.3"), .failure(.notThreeSegments("1.24.2.3")),
                "四段 → 解析失败（不静默丢段）")
    assertEqual(UpdateVersionLogic.parse("1.24.x"), .failure(.nonNumeric("x")),
                "非数字段 → 解析失败并指出哪一段")
    assertEqual(UpdateVersionLogic.parse("1..2"), .failure(.nonNumeric("1..2")),
                "空段 → 解析失败")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "1.24.2", latest: ""), nil,
                "远端版本非法 → 返回 nil（不能当「没有更新」）")
    assertEqual(UpdateVersionLogic.isUpdateAvailable(current: "", latest: "1.24.10"), nil,
                "当前版本非法 → 返回 nil")
}

func runUpdateCheckStateTests() {
    print("🧪 Testing update check state (presentation / relative time / cadence / notes)...")

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 五种状态的界面文案

    let idle = UpdateCheckText.presentation(for: .idle, lastCheckAt: nil, now: now)
    assertEqual(idle.latestVersionText, "—", "从未检查时最新版本是占位符")
    assertEqual(idle.statusText, "尚未检查", "idle 文案")
    assertEqual(idle.canCheck, true, "idle 允许点检查")
    assertEqual(idle.checkButtonTitle, "检查更新", "idle 按钮标题")

    let idleWithHistory = UpdateCheckText.presentation(for: .idle,
                                                       lastCheckAt: now.addingTimeInterval(-7200),
                                                       now: now)
    assertEqual(idleWithHistory.statusText, "尚未检查 · 上次检查 2 小时前",
                "重启后本次未查但上次查过：时间要带上，不能写成「从没查过」")

    let checking = UpdateCheckText.presentation(for: .checking, lastCheckAt: nil, now: now)
    assertEqual(checking.statusText, "正在检查…", "在途文案")
    assertEqual(checking.canCheck, false, "在途时按钮置灰（避免重复打接口）")
    assertEqual(checking.checkButtonTitle, "检查中…", "在途按钮标题")

    let upToDate = UpdateCheckText.presentation(for: .upToDate(latest: "1.24.10"),
                                               lastCheckAt: now.addingTimeInterval(-120),
                                               now: now)
    assertEqual(upToDate.latestVersionText, "1.24.10", "已是最新时显示远端版本")
    assertEqual(upToDate.statusText, "已是最新版本 · 上次检查 2 分钟前", "最新文案带相对时间")
    assertEqual(upToDate.notesText, "—", "无更新时说明用占位符")
    assertEqual(upToDate.highlightsLatest, false, "无更新时不高亮版本")
    assertEqual(upToDate.canCheck, true, "已是最新仍可再查")

    let available = UpdateCheckText.presentation(for: .available(latest: "1.24.11", notes: "修复网速单位"),
                                                lastCheckAt: now.addingTimeInterval(-120),
                                                now: now)
    assertEqual(available.latestVersionText, "1.24.11", "有新版本显示版本号")
    assertEqual(available.statusText, "发现新版本 · 上次检查 2 分钟前", "有新版本文案")
    assertEqual(available.notesText, "修复网速单位", "说明摘要透传")
    assertEqual(available.highlightsLatest, true, "有新版本时版本号高亮")

    let availableNoNotes = UpdateCheckText.presentation(for: .available(latest: "1.24.11", notes: ""),
                                                       lastCheckAt: now, now: now)
    assertEqual(availableNoNotes.notesText, "—", "release 没有说明时用占位符")

    let failed = UpdateCheckText.presentation(for: .failed(reason: "请求超时"), lastCheckAt: nil, now: now)
    assertEqual(failed.statusText, "无法检查（请求超时）", "失败只显示一行原因")
    assertEqual(failed.checkButtonTitle, "重试", "失败后按钮改「重试」")
    assertEqual(failed.canCheck, true, "失败不锁死按钮")
    assertEqual(failed.latestVersionText, "—", "失败时不留旧版本号")

    let noTime = UpdateCheckText.presentation(for: .upToDate(latest: "1.24.10"),
                                             lastCheckAt: nil, now: now)
    assertEqual(noTime.statusText, "已是最新版本 · 上次检查时间未知", "没有时间戳时不输出「从未」这种怪句子")

    // MARK: 相对时间分档

    assertEqual(UpdateRelativeTime.describe(since: nil, now: now), "从未", "从未检查")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(-30), now: now), "刚刚", "30 秒")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(-60), now: now), "1 分钟前", "60 秒")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(-3599), now: now), "59 分钟前", "59:59")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(-3600), now: now), "1 小时前", "整 1 小时")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(-86400), now: now), "1 天前", "整 1 天")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(-86400 * 3), now: now), "3 天前", "3 天")
    assertEqual(UpdateRelativeTime.describe(since: now.addingTimeInterval(120), now: now), "刚刚",
                "时钟回拨（未来时间戳）不显示负数")

    // MARK: 24 小时自动检查限频

    assertEqual(UpdateCheckCadence.isAutoCheckDue(lastCheckAt: nil, now: now), true, "从未检查 → 立即查")
    assertEqual(UpdateCheckCadence.isAutoCheckDue(lastCheckAt: now.addingTimeInterval(-3600), now: now), false,
                "1 小时前查过 → 不自动查")
    assertEqual(UpdateCheckCadence.isAutoCheckDue(lastCheckAt: now.addingTimeInterval(-86399), now: now), false,
                "差 1 秒到 24 小时 → 仍不查")
    assertEqual(UpdateCheckCadence.isAutoCheckDue(lastCheckAt: now.addingTimeInterval(-86400), now: now), true,
                "整 24 小时 → 到点")
    assertEqual(UpdateCheckCadence.isAutoCheckDue(lastCheckAt: now.addingTimeInterval(-86400 * 5), now: now), true,
                "多日未查 → 到点")

    // MARK: 发布说明摘要

    assertEqual(UpdateNotes.summary(""), "", "空说明压成空串（界面再降级成占位符）")
    assertEqual(UpdateNotes.summary("修复 A\n\n- 修复 B\t\t说明"), "修复 A 修复 B 说明",
                "换行、制表符与行首 markdown 标记（- ）一起清掉")
    assertEqual(UpdateNotes.summary("## 更新内容\n> 注意\n* 修复 C"), "更新内容 注意 修复 C",
                "行首 # / > / * 全部剥掉（界面不显示 markdown 符号）")
    assertEqual(UpdateNotes.summary("abcdefg", limit: 5), "abcde…", "超长按限制截断并补省略号")
    assertEqual(UpdateNotes.summary("abcde", limit: 5), "abcde", "刚好等于限制不截断")
    let longNotes = String(repeating: "更", count: UpdateNotes.summaryLimit + 20)
    assertEqual(UpdateNotes.summary(longNotes).count, UpdateNotes.summaryLimit + 1,
                "默认上限 160 字符 + 省略号")
}

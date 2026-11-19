import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 发布说明分段的真实样例（人工触发）

/// 五个真实样例的分段自证 — `swift run ... TestRunner --update-notes-samples`
///
/// 不进默认测试流程：其中两个样例来自真实 GitHub 响应（需要网络）。
/// 没网时用 `NM_NOTES_RAW` 传一段 body 进来也能跑（离线复核分段口径）。
func runUpdateNotesSamplesProbe() {
    print("🧪 Live probe: 发布说明分段（真实 body 与边界样例）...")
    let box = ProbeLineBox()
    let semaphore = DispatchSemaphore(value: 0)

    Task.detached {
        var samples: [(String, String)] = []

        // 1) 真实远端最新 release body（分段的主要真实来源）
        do {
            let checker = GitHubUpdateChecker(userAgent: "一览/notes-probe")
            let release = try await checker.fetchLatestRelease()
            samples.append(("远端 \(release.tagName) 的完整 body（\(release.notes.count) 字符）", release.notes))
            samples.append(("远端 body 的前 12 行",
                            release.notes.split(separator: "\n").prefix(12).joined(separator: "\n")))
        } catch {
            box.append("远端取 body 失败：\(error)（继续跑离线样例）")
        }

        // 2) 生成脚本写出的真实开头（下载说明 + HTML 注释 + 粗体行 + 条目 + 提交链接）
        let generatedHead = [
            "**下载**：`Yilan-arm64.app.zip` 面向 Apple Silicon，`Yilan-x86_64.app.zip` 面向 Intel。",
            "",
            "<!-- 自动生成：NetworkMonitor/Scripts/generate-release-notes.sh（v1.27.0...v1.29.0） -->",
            "",
            "### 新增",
            "",
            "- 新增 Scripts/release.sh，把发版流程做成一条命令（[`8413a6b`](https://github.com/baosfeng/toolbar/commit/8413a6b)）",
            "- 提醒只在额度用尽时触发，恢复通知只针对用尽过的额度（[`3e38fa0`](https://github.com/baosfeng/toolbar/commit/3e38fa0)）",
            "- 内建合成反馈音（咔嚓系）替换系统默认音（[`48695d9`](https://github.com/baosfeng/toolbar/commit/48695d9)）",
        ].joined(separator: "\n")
        samples.append(("生成脚本的真实开头", generatedHead))

        // 3) markdown 全标记样例（标题 / 粗体 / 引用 / 有序列表 / 链接）
        let marked = [
            "## 修复",
            "",
            "**重要**：这一版只修 bug。",
            "",
            "> 注意：重启后生效。",
            "",
            "1. 修了窗口位置",
            "2. 修了单位显示",
            "",
            "详见 [发布说明](https://github.com/baosfeng/toolbar/releases)。",
        ].joined(separator: "\n")
        samples.append(("全标记样例", marked))

        // 4) 只有标题
        samples.append(("只有标题", "## 更新内容"))

        // 5) 空说明（release body 为空）
        samples.append(("空说明", ""))

        if let extra = ProcessInfo.processInfo.environment["NM_NOTES_RAW"], !extra.isEmpty {
            samples.append(("NM_NOTES_RAW 传入的 body", extra))
        }

        for (index, sample) in samples.enumerated() {
            let blocks = UpdateNotes.blocks(sample.1)
            let lines = UpdateNotes.lines(from: blocks)
            box.append("样例 \(index + 1)「\(sample.0)」：\(blocks.count) 块 / \(lines.count) 行")
            for line in lines.prefix(12) {
                switch line.style {
                case .heading:  box.append("      [标题] \(line.text)")
                case .bullet:   box.append("      [条目] \(line.text)")
                case .paragraph: box.append("      [段落] \(line.text)")
                case .truncationNotice: box.append("      [截断] \(line.text)")
                }
            }
            if lines.count > 12 { box.append("      …（其余 \(lines.count - 12) 行省略）") }
        }
        semaphore.signal()
    }
    semaphore.wait()
    for line in box.all { print("   " + line) }
}

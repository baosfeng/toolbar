import Foundation
import NetworkMonitorUI

// MARK: - 发布说明分块

/// 分块器口径 —— 正常 / 空 / 只有标题 / 超长 / markdown 标记 五类都得钉住
///
/// 说明区能不能读，取决于「body 分成了什么块」；这条判据在界面里看不出来，
/// 所以全部压成纯函数在这里断言，并顺带打印每个样例的分段结果（人工可复核）。
func runUpdateNotesBlockTests() {
    print("🧪 Testing 发布说明分块（标题 / 条目 / 段落 / 行内标记 / 上限）...")

    // MARK: 空与只有标题

    assertEqual(UpdateNotes.blocks(""), [], "空串 → 零块")
    assertEqual(UpdateNotes.blocks("   \n\n  "), [], "全空白 → 零块")
    assertEqual(UpdateNotes.blocks("<!-- 自动生成 -->"), [], "整行 HTML 注释不产出块")
    assertEqual(UpdateNotes.blocks("## 更新内容"), [.heading("更新内容")], "只有一个标题")
    assertEqual(UpdateNotes.lines("## 更新内容").map(\.style), [.heading], "只有标题时只有一行")

    // MARK: 正常结构

    let normal = """
    ## 新增

    - 截图动作按钮支持自定义排序
    - 额度 Provider 新增三家

    这一轮还修了一些小问题，具体见提交记录。
    """
    assertEqual(UpdateNotes.blocks(normal), [
        .heading("新增"),
        .bullet("- 截图动作按钮支持自定义排序"),
        .bullet("- 额度 Provider 新增三家"),
        .paragraph("这一轮还修了一些小问题，具体见提交记录。"),
    ], "标题 / 条目 / 段落各自成块，空行分段")

    // 连续段落行合成一段（GitHub 的 body 常把一句话折成多行）
    assertEqual(UpdateNotes.blocks("第一行\n第二行"), [.paragraph("第一行 第二行")], "连续行合成一段")

    // MARK: markdown 标记

    assertEqual(UpdateNotes.blocks("### 子标题"), [.heading("子标题")], "三级标题同样识别")
    assertEqual(UpdateNotes.blocks("#没有空格"), [.paragraph("#没有空格")], "井号后无空格不是标题")
    assertEqual(UpdateNotes.blocks("**下载**：两个包"), [.paragraph("**下载**：两个包")],
                "粗体行不是条目")
    assertEqual(ReleaseNoteInline.plain("**下载**：两个包"), "下载：两个包", "粗体标记剥掉")
    assertEqual(UpdateNotes.blocks("* 星号条目"), [.bullet("- 星号条目")], "星号 + 空白是条目，符号归一成 -")
    assertEqual(UpdateNotes.blocks("1. 有序条目"), [.bullet("1. 有序条目")], "有序列表保留序号")
    assertEqual(UpdateNotes.blocks("> 注意：这条是引用"), [.paragraph("注意：这条是引用")], "引用前缀剥掉")
    assertEqual(ReleaseNoteInline.plain("新增 Scripts/release.sh，一条命令发版（[`8413a6b`](https://github.com/a/b/commit/8413a6b)）"),
                "新增 Scripts/release.sh，一条命令发版（8413a6b）", "链接只留文字")
    assertEqual(ReleaseNoteInline.firstLink("见 [`8413a6b`](https://github.com/a/b/commit/8413a6b)"),
                "https://github.com/a/b/commit/8413a6b", "链接地址能单独取出")
    assertEqual(ReleaseNoteInline.firstLink("没有链接"), nil, "无链接 → nil")

    // MARK: 行数上限

    let many = (1...30).map { "- 第 \($0) 条" }.joined(separator: "\n")
    let limited = UpdateNotes.lines(many, limit: 10)
    assertEqual(limited.count, 10, "超上限时总行数等于上限")
    assertEqual(limited.last?.style, .truncationNotice, "最后一行是截断提示")
    assertEqual(limited.last?.text, UpdateNotes.truncationNotice, "截断提示文案固定")
    assertEqual(UpdateNotes.lines(many, limit: 30).count, 30, "正好等于上限时不截断")
    assertEqual(UpdateNotes.lines(many, limit: 1).map(\.style), [.truncationNotice],
                "上限为 1 时只剩截断提示（不展示半条内容）")
    assertEqual(UpdateNotes.lines(many, limit: 0).count, 30, "上限 0 视为不限")

    // MARK: 五个真实样例（含远端 v1.29.0 的节选）

    let samples: [(String, String)] = [
        ("生成脚本的真实开头（含注释与粗体行）", """
        **下载**：`Yilan-arm64.app.zip` 面向 Apple Silicon，`Yilan-x86_64.app.zip` 面向 Intel。

        <!-- 自动生成：NetworkMonitor/Scripts/generate-release-notes.sh（v1.27.0...v1.29.0） -->

        ### 新增

        - 新增 Scripts/release.sh，把发版流程做成一条命令（[`8413a6b`](https://github.com/baosfeng/toolbar/commit/8413a6b)）
        - 提醒只在额度用尽时触发，恢复通知只针对用尽过的额度（[`3e38fa0`](https://github.com/baosfeng/toolbar/commit/3e38fa0)）
        """),
        ("只有正文", "修了一些小问题。"),
        ("只有条目", "- 甲\n- 乙\n- 丙"),
        ("标题 + 段落（无条目）", "## 修复\n\n重启后窗口位置会复原。"),
        ("空说明", ""),
    ]
    for (index, sample) in samples.enumerated() {
        let blocks = UpdateNotes.blocks(sample.1)
        let rendered = UpdateNotes.lines(from: blocks).map { line -> String in
            switch line.style {
            case .heading: return "H:" + line.text
            case .bullet: return "B:" + line.text
            case .paragraph: return "P:" + line.text
            case .truncationNotice: return "T:" + line.text
            }
        }
        print("   样例 \(index + 1)「\(sample.0)」共 \(blocks.count) 块 → \(rendered.joined(separator: " | "))")
    }
    // 样例 1：粗体行成段、注释行被跳过、标题 + 两条条目
    let first = UpdateNotes.blocks(samples[0].1)
    assertEqual(first.count, 4, "样例 1：段落 + 标题 + 两条条目（注释不计数）")
    assertEqual(first.first, .paragraph("**下载**：`Yilan-arm64.app.zip` 面向 Apple Silicon，`Yilan-x86_64.app.zip` 面向 Intel。"),
                "样例 1 首块是下载说明段")
    assertEqual(UpdateNotes.blocks(samples[4].1).isEmpty, true, "样例 5 空说明 → 零块（界面回落占位）")

    print("✅ 发布说明分块 works")
}
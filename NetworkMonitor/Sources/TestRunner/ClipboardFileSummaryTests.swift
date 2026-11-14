import Foundation
import NetworkMonitorCore

// MARK: - 文件条目分类聚合摘要（A1 验收）

/// 覆盖第三批规格 5 节 A1 的全部断言项：单文件格式 / 跨族顺序稳定 / 同族合并写法 /
/// 中文与空格不乱码 / 按条目边界截断 / 空数组空串，外加零散边界（未知扩展名、跨族分隔符）。
func runClipboardFileSummaryTests() {
    print("🧪 Testing Clipboard file summary...")

    // 1) 单个文件 → 「族名: 文件名」，不带前缀也不带计数
    assertEqual(ClipboardFileSummary.summarize(paths: ["/Users/me/Desktop/季度报告.pdf"]), "文档: 季度报告.pdf",
                "单个文件 → 文档: 季度报告.pdf")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/shot.PNG"]), "图片: shot.PNG",
                "单文件保留原大小写与扩展名")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/main.swift"]), "代码: main.swift", "单代码文件")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/Makefile"]), "文件: Makefile",
                "无扩展名落 other 族名「文件」")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/a.unknownext"]), "文件: a.unknownext",
                "未知扩展名落 other 族名")

    // 2) 多文件跨族：族按首次出现顺序排列（顺序稳定），跨族用「; 」分隔
    let crossFamily = ClipboardFileSummary.summarize(paths: ["/tmp/a.pdf", "/tmp/b.png", "/tmp/c.zip"])
    assertEqual(crossFamily, "文件 (3个): 文档: a.pdf; 图片: b.png; 压缩包: c.zip",
                "跨族顺序即路径顺序")
    let reversed = ClipboardFileSummary.summarize(paths: ["/tmp/c.zip", "/tmp/b.png", "/tmp/a.pdf"])
    assertEqual(reversed, "文件 (3个): 压缩包: c.zip; 图片: b.png; 文档: a.pdf",
                "换顺序后族序跟着换，稳定不随机")
    let shuffled = ClipboardFileSummary.summarize(paths: ["/tmp/a.pdf", "/tmp/b.png", "/tmp/c.zip"])
    assertEqual(shuffled, crossFamily, "同一输入多次调用结果稳定")

    // 3) 同族多个文件合并成一段：「族 ×N: 名1、名2」
    //    （规格示例给的是「文档 ×2: a.docx、b.docx」，分隔符按规格用顿号）
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/a.docx", "/tmp/b.docx"]),
                "文件 (2个): 文档 ×2: a.docx、b.docx", "同族两文件合并写法")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"]),
                "文件 (3个): 图片 ×3: a.png、b.png、c.png", "同族三文件合并写法")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/a.pdf", "/tmp/b.png", "/tmp/c.docx"]),
                "文件 (3个): 文档 ×2: a.pdf、c.docx; 图片: b.png",
                "跨族 + 同族混排：同族仍合并为一段且位于首现族位置")

    // 4) 中文与空格不乱码：文件名原样保留（不折叠空格、不做 URL 转义）
    assertEqual(ClipboardFileSummary.summarize(paths: ["/Users/me/我的 文件/截图 2026.png"]),
                "图片: 截图 2026.png", "中文路径 + 空格文件名原样保留")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/季度 报告 终稿 v2.xlsx",
                                                       "/tmp/预算 表 v3.csv"]),
                "文件 (2个): 文档 ×2: 季度 报告 终稿 v2.xlsx、预算 表 v3.csv",
                "多文件中文空格不乱码")
    assertEqual(ClipboardFileSummary.fileName(ofPath: "/tmp/带 空格 的名字.md"), "带 空格 的名字.md",
                "取文件名保留内部空格")
    assertEqual(ClipboardFileSummary.fileName(ofPath: "  /tmp/前导空白.txt  "), "前导空白.txt",
                "路径首尾空白被去掉")

    // 5) 超长按条目边界截断：不出现半个文件名，末尾补省略号，长度不超过 previewMaxLength
    var manyPaths: [String] = []
    for index in 1...40 { manyPaths.append("/tmp/文档_\(index)_很长的名字.pdf") }
    let truncated = ClipboardFileSummary.summarize(paths: manyPaths)
    assertEqual(truncated.count <= ClipboardLimit.previewMaxLength, true,
                "超长摘要长度不超过 previewMaxLength")
    assertEqual(truncated.hasSuffix("…"), true, "超长摘要末尾补省略号")
    assertEqual(truncated.hasPrefix("文件 (40个): 文档 ×40: 文档_1_很长的名字.pdf"), true,
                "截断保留头部完整条目")
    // 截断点必须落在条目边界：去掉省略号后，结果不能停在某个文件名的中间
    let body = String(truncated.dropLast())
    let lastSegment = body.components(separatedBy: ClipboardFileSummary.intraFamilySeparator).last ?? ""
    assertEqual(lastSegment.hasPrefix("文档_"), true, "截断停在条目边界（最后一段是完整文件名）")
    assertEqual(lastSegment.hasSuffix(".pdf"), true, "截断不会把文件名切成半个")

    // 跨族超长：后面的族整段被丢弃，而不是切一半（且不为被丢的族留下悬挂分隔符）
    var crossPaths = ["/tmp/起点.pdf"]
    for index in 1...30 { crossPaths.append("/tmp/图片_\(index)_很长很长很长很长.png") }
    let crossTruncated = ClipboardFileSummary.summarize(paths: crossPaths)
    assertEqual(crossTruncated.count <= ClipboardLimit.previewMaxLength, true, "跨族超长同样不超上限")
    assertEqual(crossTruncated.contains("; ;"), false, "截断不留空的跨族分隔符")
    assertEqual(crossTruncated.hasPrefix("文件 (31个): 文档: 起点.pdf; 图片 ×30: 图片_1_"), true,
                "跨族截断保留首族与次族完整开头")

    // 5b) 单个文件名本身就超长：放不下就只留族头，绝不把文件名切成半个
    let longName = String(repeating: "超", count: 260) + ".pdf"
    let singleLong = ClipboardFileSummary.summarize(paths: ["/tmp/" + longName])
    assertEqual(singleLong.count <= ClipboardLimit.previewMaxLength, true, "超长单文件不超上限")
    assertEqual(singleLong.contains(String(longName.prefix(20))), false,
                "超长单文件不显示半个文件名")
    assertEqual(singleLong.hasPrefix("文档: "), true, "超长单文件保留族头")

    // 5c) 采集侧兜底入口：摘要为空时回落到原始文本（旧口径），不会变成空卡片
    assertEqual(ClipboardFileSummary.summarize(paths: [], fallbackText: "/tmp/a.pdf\n/tmp/b.pdf"),
                "/tmp/a.pdf /tmp/b.pdf", "摘要为空时回落到原始文本（既有换行折叠口径）")
    assertEqual(ClipboardFileSummary.summarize(paths: ["/tmp/x.pdf"], fallbackText: "ignored"),
                "文档: x.pdf", "有摘要时忽略回落文本")
    assertEqual(ClipboardFileSummary.summarize(paths: [""], fallbackText: "  "), "",
                "摘要与回落文本都为空 → 空串")

    // 6) 空数组 → 空串；取不到文件名的路径同样返回空串
    assertEqual(ClipboardFileSummary.summarize(paths: []), "", "空数组 → 空串")
    assertEqual(ClipboardFileSummary.summarize(paths: [""]), "", "空路径 → 空串")
    assertEqual(ClipboardFileSummary.summarize(paths: ["   "]), "", "纯空白路径 → 空串")
    assertEqual(ClipboardFileSummary.fileName(ofPath: ""), "", "空路径取文件名为空串")

    // 7) 族名映射：八类齐全且都能落到短名（分类判据仍由 ClipboardFileClassifier 唯一决定）
    let families = ClipboardFileCategory.allCases.map { ClipboardFileSummary.familyName(for: $0) }
    assertEqual(families.count, 8, "八类族名齐全")
    assertEqual(families.allSatisfy { !$0.isEmpty }, true, "每类都有中文短名")
    assertEqual(ClipboardFileSummary.familyName(for: .other), "文件", "other 族名沿用「文件」")
    assertEqual(ClipboardFileSummary.familyName(for: .document), "文档", "document 短名「文档」")
    assertEqual(ClipboardFileSummary.familyName(forPath: "/tmp/x.pdf"),
                ClipboardFileSummary.familyName(for: ClipboardFileClassifier.category(forPath: "/tmp/x.pdf")),
                "按路径取族名与分类器同源")

    print("✅ Clipboard 文件摘要 works")
}

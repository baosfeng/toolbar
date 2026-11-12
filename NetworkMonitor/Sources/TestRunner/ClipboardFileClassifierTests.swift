import Foundation
import NetworkMonitorCore

// MARK: - 文件条目类型细分（Core 纯函数）

/// 覆盖验收标准 C 组：扩展名白名单分类 / 无扩展名 / 多文件同异类别 / 大小写与空白归一 / 空数组
func runClipboardFileClassifierTests() {
    print("🧪 Testing Clipboard file category classifier...")

    // 1) 七类各至少两个样本（白名单命中）
    let imageSamples = ["a.png", "b.JPG", "c.jpeg", "d.heic"]
    let videoSamples = ["a.mp4", "b.MOV", "c.mkv"]
    let audioSamples = ["a.mp3", "b.WAV", "c.flac"]
    let documentSamples = ["a.pdf", "b.docx", "c.xlsx", "d.md"]
    let codeSamples = ["a.swift", "b.ts", "c.json", "d.sh"]
    let archiveSamples = ["a.zip", "b.7z", "c.tar", "d.dmg"]
    let executableSamples = ["a.app", "b.pkg", "c.exe", "d.bin"]

    for path in imageSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .image, "\(path) 判为图片")
    }
    for path in videoSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .video, "\(path) 判为视频")
    }
    for path in audioSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .audio, "\(path) 判为音频")
    }
    for path in documentSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .document, "\(path) 判为文档")
    }
    for path in codeSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .code, "\(path) 判为代码")
    }
    for path in archiveSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .archive, "\(path) 判为压缩包")
    }
    for path in executableSamples {
        assertEqual(ClipboardFileClassifier.category(forPath: path), .executable, "\(path) 判为可执行")
    }

    // 2) 无扩展名 / 未知扩展名 / 空串一律 other（不做黑名单推断）
    assertEqual(ClipboardFileClassifier.category(forPath: "README"), .other, "无扩展名 → other")
    assertEqual(ClipboardFileClassifier.category(forPath: "/tmp/Makefile"), .other, "目录内无扩展名 → other")
    assertEqual(ClipboardFileClassifier.category(forPath: "a.unknownext"), .other, "未知扩展名 → other")
    assertEqual(ClipboardFileClassifier.category(forPath: ""), .other, "空路径 → other")
    assertEqual(ClipboardFileClassifier.category(forPath: "   "), .other, "纯空白 → other")
    assertEqual(ClipboardFileClassifier.category(forPath: "a."), .other, "点后无扩展名 → other")
    assertEqual(ClipboardFileClassifier.normalizedExtension(of: "a."), nil, "点后无扩展名归一化返回 nil")
    assertEqual(ClipboardFileClassifier.category(forExtension: ""), .other, "空扩展名 → other")
    assertEqual(ClipboardFileClassifier.category(forExtension: "xyz"), .other, "未知扩展名 → other")

    // 3) 大小写与前后空白归一（小写比较）
    assertEqual(ClipboardFileClassifier.normalizedExtension(of: "  a.PNG  "), "png", "大小写与空白归一为 png")
    assertEqual(ClipboardFileClassifier.category(forPath: "  /tmp/a.PnG  "), .image, "PNG 大写 + 空白仍判为图片")
    assertEqual(ClipboardFileClassifier.category(forPath: "\t a.MP4\n"), .video, "MP4 大小写 + 制表符仍判为视频")
    assertEqual(ClipboardFileClassifier.category(forPath: "a.ZIP"), .archive, "ZIP 大写判为压缩包")

    // 4) 多文件：全部同类 → 该类别
    assertEqual(ClipboardFileClassifier.category(forPaths: ["a.png", "b.png", "c.jpg"]), .image,
                "三张图片同类 → image")
    assertEqual(ClipboardFileClassifier.category(forPaths: ["a.swift", "b.ts"]), .code, "两个代码文件同类 → code")
    assertEqual(ClipboardFileClassifier.category(forPaths: ["a.zip"]), .archive, "单个文件 → 该类别")
    assertEqual(ClipboardFileClassifier.category(forPaths: ["README", "LICENSE"]), .other,
                "多个无扩展名同类 → other")

    // 5) 多文件混合 → other（不允许图标撒谎）
    assertEqual(ClipboardFileClassifier.category(forPaths: ["a.png", "b.pdf"]), .other,
                "图片 + 文档混合 → other")
    assertEqual(ClipboardFileClassifier.category(forPaths: ["a.mp4", "b.mp4", "c.pdf"]), .other,
                "多数派同类但含异类 → other")
    assertEqual(ClipboardFileClassifier.category(forPaths: ["a.png", "README"]), .other,
                "已知类 + 未知混合 → other")

    // 6) 空数组 → nil（无条目可判定）
    assertEqual(ClipboardFileClassifier.category(forPaths: []), nil, "空数组 → nil")

    // 7) 展示元数据：八类全有中文标签与 SF Symbol，且符号互不重复
    assertEqual(ClipboardFileCategory.allCases.count, 8, "八类齐全")
    let labels = ClipboardFileCategory.allCases.map { $0.label }
    assertEqual(labels.allSatisfy { !$0.isEmpty }, true, "每类都有中文标签")
    assertEqual(Set(ClipboardFileCategory.allCases.map { $0.symbolName }).count, 8, "八类符号互不重复")
    assertEqual(ClipboardFileCategory.allCases.map { $0.symbolName }.allSatisfy { !$0.contains("emoji") },
                true, "只用 SF Symbol 名，不含 emoji 占位")
    assertEqual(ClipboardFileCategory.image.label, "图片文件", "图片标签")
    assertEqual(ClipboardFileCategory.archive.label, "压缩包", "压缩包标签")
    assertEqual(ClipboardFileCategory.other.label, "文件", "兜底标签为「文件」")
    assertEqual(ClipboardFileCategory.image.symbolName, "photo", "图片沿用既有 photo 符号")
    assertEqual(ClipboardFileCategory.other.symbolName, "doc", "兜底沿用既有 doc 符号")
    assertEqual(ClipboardFileCategory.executable.symbolName, "hammer", "可执行符号为 hammer")
}

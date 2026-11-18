import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片卡脚文案（标题 / 来源两行）

/// 三段式卡片卡脚的文案口径 —— 对标 Paste 的「标题 + 域名」两行
///
/// 这三条规则最容易在改动中漂移，单独立成断言：
/// 1. 文本条目的标题取**正文首个非空行**，不是 preview（preview 可能是压缩摘要）；
/// 2. 图片条目的**内容哈希文件名不能当标题**（原图按 `<sha256>.png` 落盘，甩出来是一串十六进制）；
/// 3. 副标题恒为「来源 · 体量」，缺来源时不写「未知来源」占位，缺体量时不留空档。
func runClipboardFooterTextTests() {
    print("🧪 Testing clipboard card footer text...")

    let now = Date()
    // 文本：标题取首个非空行（前面有空行也要跳过）
    let text = ClipboardItem(kind: .text, text: "\n\n第一行标题\n第二行内容", preview: "第一行标题 第二行内容",
                             contentHash: "footer-text", sourceBundleID: "com.apple.Terminal",
                             sourceAppName: "终端", createdAt: now)
    assertEqual(ClipboardFooterText.title(for: text), "第一行标题", "文本标题取正文首个非空行")
    assertEqual(ClipboardFooterText.source(for: text), "终端 · 11 字", "文本副标题 = 来源 · 字数（去空白后）")

    // 纯空白：给明确的空态，不画空白行
    let blank = ClipboardItem(kind: .text, text: "   \n\t", preview: "", contentHash: "footer-blank")
    assertEqual(ClipboardFooterText.title(for: blank), "（空内容）", "空文本给空态文案")
    assertEqual(ClipboardFooterText.source(for: blank), "无来源信息", "无来源无体量时给一句兜底")

    // 图片：内容哈希文件名不当标题，退回尺寸
    let hashName = String(repeating: "a1b2c3d4", count: 8)   // 64 位十六进制
    let hashedImage = ClipboardItem(kind: .image, preview: "图片 512×384",
                                    imagePath: "/tmp/clip/\(hashName).png",
                                    imageWidth: 512, imageHeight: 384,
                                    contentHash: hashName, sourceAppName: "Safari", createdAt: now)
    assertEqual(ClipboardFooterText.looksLikeContentHash("\(hashName).png"), true, "64 位十六进制识别为内容哈希")
    assertEqual(ClipboardFooterText.title(for: hashedImage), "图片 512×384",
                "哈希文件名不当标题，退回尺寸")
    assertEqual(ClipboardFooterText.source(for: hashedImage), "Safari · 512×384", "图片副标题 = 来源 · 尺寸")

    // 图片：人写的文件名照常当标题
    let namedImage = ClipboardItem(kind: .image, preview: "图片 2400×1600",
                                   imagePath: "/tmp/clip/截屏 2026-11-18 21.04.png",
                                   imageWidth: 2400, imageHeight: 1600,
                                   contentHash: "footer-image-2", sourceAppName: "截图", createdAt: now)
    assertEqual(ClipboardFooterText.title(for: namedImage), "截屏 2026-11-18 21.04.png",
                "有语义的文件名当标题")
    assertEqual(ClipboardFooterText.looksLikeContentHash("截屏 2026-11-18 21.04.png"), false,
                "带空格与中文的文件名不是哈希")

    // 文件：标题取路径末段，副标题给大写扩展名
    let file = ClipboardItem(kind: .file, text: "/Users/x/Documents/spec.pdf", preview: "/Users/x/Documents/spec.pdf",
                             contentHash: "footer-file", sourceAppName: "访达", createdAt: now)
    assertEqual(ClipboardFooterText.title(for: file), "spec.pdf", "文件标题取路径末段")
    assertEqual(ClipboardFooterText.source(for: file), "访达 · PDF", "文件副标题 = 来源 · 大写扩展名")

    // 标题截断：超长不把整段塞进绘制
    let long = ClipboardItem(kind: .text, text: String(repeating: "长", count: 200),
                             preview: "", contentHash: "footer-long")
    assertEqual(ClipboardFooterText.title(for: long).count, ClipboardFooterText.titleMaxCharacters,
                "超长标题按上限截断（细节由绘制侧省略号收尾）")

    // 体量：取不到的项返回 nil（副标题不留空档）
    assertEqual(ClipboardFooterText.sizeText(for: ClipboardItem(kind: .image, preview: "",
                                                                contentHash: "footer-no-size")), nil,
                "没有像素尺寸的图片不给体量")
}

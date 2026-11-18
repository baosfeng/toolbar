import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板文本类型判定（Core 纯函数）

/// 覆盖 `ClipboardTextClassifier`：五类正例 + 边界（纯数字不算颜色 / 短 hex 算颜色 / 多行不是 url / 空串）+ 超长文本性能
func runClipboardTextClassifierTests() {
    print("🧪 Testing Clipboard text classifier...")

    // 1) 类型正例：每类至少两条，并校验判定依据
    let urlSamples = ["https://example.com/x", "http://a.b", "www.apple.com", "HTTPS://Example.COM"]
    for text in urlSamples {
        assertEqual(ClipboardTextClassifier.classify(text).kind, .url, "\(text) 判为链接")
    }
    assertEqual(ClipboardTextClassifier.classify("https://example.com").evidence, .schemeURL, "http(s) 依据是 scheme")
    assertEqual(ClipboardTextClassifier.classify("www.apple.com").evidence, .wwwPrefix, "www. 依据是前缀")

    let emailSamples = ["user@example.com", "first.last+tag@mail.example.org"]
    for text in emailSamples {
        assertEqual(ClipboardTextClassifier.classify(text).kind, .email, "\(text) 判为邮箱")
    }

    let colorSamples = ["#FFF", "#FFFFFF", "#FFFFFFFF", "#FFF0", "rgb(1,2,3)", "rgba(1,2,3,0.5)", "HSL(0,0%,0%)"]
    for text in colorSamples {
        assertEqual(ClipboardTextClassifier.classify(text).kind, .color, "\(text) 判为颜色")
    }
    assertEqual(ClipboardTextClassifier.classify("#FFFFFF").evidence, .hexColor, "hex 依据")
    assertEqual(ClipboardTextClassifier.classify("rgb(0,0,0)").evidence, .functionalColor, "函数式依据")

    let jsonSamples = ["{\"a\":1}", "[1,2,3]", "  {\"k\":[1,2]}  "]
    for text in jsonSamples {
        assertEqual(ClipboardTextClassifier.classify(text).kind, .json, "\(text) 判为 JSON")
    }
    assertEqual(ClipboardTextClassifier.classify("{\"a\":1}").evidence, .parseableJSON, "JSON 依据")

    let commandSamples = ["ls -la", "sudo rm -rf /tmp/x", "$ echo hi", "./run.sh", "git status", "brew list --versions"]
    for text in commandSamples {
        assertEqual(ClipboardTextClassifier.classify(text).kind, .command, "\(text) 判为命令")
    }
    assertEqual(ClipboardTextClassifier.classify("npm run build").evidence, .shellCommand, "命令依据")

    // 2) 边界：纯 6 位数字不算颜色（验证码不得变成色块）
    assertEqual(ClipboardTextClassifier.classify("235442").kind, .plain, "纯 6 位数字 → 普通文本")
    assertEqual(ClipboardTextClassifier.classify("235442").evidence, .none, "纯数字无判定依据")
    assertEqual(ClipboardTextClassifier.classify("000000").kind, .plain, "全零数字同样不是颜色")
    // 短 hex 仍算颜色，且 # 后位数不合法一律 plain
    assertEqual(ClipboardTextClassifier.classify("#FFF").kind, .color, "#FFF 算颜色")
    assertEqual(ClipboardTextClassifier.classify("#FFFFF").kind, .plain, "5 位 hex 不是颜色")
    assertEqual(ClipboardTextClassifier.classify("#GGG").kind, .plain, "非 hex 字符不是颜色")
    assertEqual(ClipboardTextClassifier.classify("#").kind, .plain, "只有井号不是颜色")

    // 3) 边界：多行文本一律不是 url / email / command
    assertEqual(ClipboardTextClassifier.classify("https://a.com\nhttps://b.com").kind, .plain, "多行链接 → plain")
    assertEqual(ClipboardTextClassifier.classify("hello\nworld").kind, .plain, "普通多行文本 → plain")
    assertEqual(ClipboardTextClassifier.classify("a@b.com\nc@d.com").kind, .plain, "多行邮箱 → plain")
    // JSON 是唯一允许跨行的类型
    assertEqual(ClipboardTextClassifier.classify("{\"a\":\n 1}").kind, .json, "跨行 JSON 仍是 JSON")

    // 4) 边界：空串 / 纯空白 / 解析失败的伪 JSON / ssh 地址
    assertEqual(ClipboardTextClassifier.classify(""), .plain, "空串 → plain")
    assertEqual(ClipboardTextClassifier.classify("   \n\t "), .plain, "纯空白 → plain")
    assertEqual(ClipboardTextClassifier.classify("{").kind, .plain, "解析失败的 { → plain")
    assertEqual(ClipboardTextClassifier.classify("[broken").kind, .plain, "解析失败的 [ → plain")
    assertEqual(ClipboardTextClassifier.classify("{\"a\":1").kind, .plain, "截断 JSON → plain")
    assertEqual(ClipboardTextClassifier.classify("git@github.com:foo/bar.git").kind, .plain, "ssh 地址不误判为邮箱")
    assertEqual(ClipboardTextClassifier.classify("a@b").kind, .plain, "域名无点 → plain")
    assertEqual(ClipboardTextClassifier.classify("a@@b.com").kind, .plain, "两个 @ → plain")

    // 5) 性能：超长文本判定不退化（JSON 只对可疑前缀且不超上限尝试解析）
    let longPlain = String(repeating: "一段很长的正文，没有类型特征。", count: 60000)
    let longJSONLike = "{" + String(repeating: "a", count: 1_000_000)
    let start = DispatchTime.now().uptimeNanoseconds
    assertEqual(ClipboardTextClassifier.classify(longPlain).kind, .plain, "超长正文 → plain")
    assertEqual(ClipboardTextClassifier.classify(longJSONLike).kind, .plain, "超长伪 JSON → plain（不白跑解析）")
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    // 阈值按「最慢的 CI 机器」给，不按本机：这是防退化粗判据（判「有没有对 100 万字符白跑一遍
    // JSON 解析」，那种退化是秒级而不是百毫秒级），不是性能基准。
    // 实测本机 arm64 约 40ms、CI 的 x86_64 runner 243ms——200ms 卡在机器差异上，与代码无关。
    assertEqual(elapsedMs < 1000, true, "两段超长文本判定合计 < 1s（实测 \(String(format: "%.1f", elapsedMs))ms）")

    // 6) 展示口径收敛：两处调用点共用同一判定（www. 开头此前详情区显示「文本」）
    let wwwItem = ClipboardItem(kind: .text, text: "www.apple.com", contentHash: "classify-www")
    assertEqual(ClipboardItemKindLabel.label(for: wwwItem), "链接", "www. 链接在详情区也显示为链接")
    let commandItem = ClipboardItem(kind: .text, text: "git status", contentHash: "classify-cmd")
    assertEqual(ClipboardItemKindLabel.label(for: commandItem), "文本", "命令的类型标签仍是文本")
    assertEqual(ClipboardItemKindLabel.symbolName(forTextKind: .url), "link", "链接符号")
    assertEqual(ClipboardItemKindLabel.symbolName(forTextKind: .json), "curlybraces", "JSON 符号")
    assertEqual(ClipboardItemKindLabel.symbolName(forTextKind: .command), "terminal", "命令符号")
    assertEqual(ClipboardItemKindLabel.symbolName(forTextKind: .plain), nil, "普通文本不表态（返回 nil）")
    assertEqual(ClipboardItemKindLabel.symbolName(forTextKind: .email), nil, "邮箱暂不特化符号（与类型标签一致）")
    assertEqual(ClipboardItemKindLabel.symbolName(forTextKind: .color), nil, "颜色暂不特化符号（与类型标签一致）")
    assertEqual(ClipboardTextKind.allCases.count, 6, "六类齐全")
}

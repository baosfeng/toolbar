import Foundation
import NetworkMonitorCore

// MARK: - 贴图来源纯文本与 ⌘⇧C（回归断言）

func runSnipPinSourceTextTests() {
    print("\n🧪 Testing Snip pin source text (⌘⇧C 复制纯文本)...")

    // 文本来源：原样返回
    assertEqual(SnipPinSourceText.plainText(of: .text("hello")), "hello", "纯文本来源原样返回")
    // 空白文本不算有内容（按不出来也不该复制一段空字符串）
    assertEqual(SnipPinSourceText.plainText(of: .text("   \n  ")), nil, "全空白文本视为无来源")
    // HTML 来源：给原始 HTML（官方是「纯文本」，先保留原文，后续可做去标签）
    assertEqual(SnipPinSourceText.plainText(of: .html("<p>hi</p>")), "<p>hi</p>", "HTML 来源返回原文")
    // 文件来源：多路径按行拼接，重复项去掉
    assertEqual(SnipPinSourceText.plainText(of: .files(["/a/b.png", "/a/c.txt", "/a/b.png"])),
                "/a/b.png\n/a/c.txt", "文件来源拼成多行且去重")
    assertEqual(SnipPinSourceText.plainText(of: .files([])), nil, "空文件列表无来源")
    // 图片与色卡没有来源文本（⌘⇧C 应给出「无内容可复制」而不是静默）
    assertEqual(SnipPinSourceText.plainText(of: .image), nil, "像素贴图无来源文本")
    assertEqual(SnipPinSourceText.plainText(of: .color(SnipPixelColor(red: 255, green: 0, blue: 0))),
                nil, "色卡无来源文本")

    print("✅ 贴图来源文本测试通过")
}

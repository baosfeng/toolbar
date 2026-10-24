import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板内容分类

func runSnipClipboardTests() {
    print("🧪 Testing Snip clipboard classification...")

    // 优先级：图片 > 文件 > 颜色 > HTML > 文本
    assertEqual(SnipClipboardClassifier.classify(hasImage: true, filePaths: ["/tmp/a.png"], plainText: "hi", html: nil),
                .image, "有图片时优先贴图")
    assertEqual(SnipClipboardClassifier.classify(hasImage: false, filePaths: ["/tmp/a.txt"], plainText: "#FF0000", html: nil),
                .files(["/tmp/a.txt"]), "文件优先于颜色")
    assertEqual(SnipClipboardClassifier.classify(hasImage: false, filePaths: [], plainText: "#FF0000", html: "<b>x</b>"),
                .color(SnipPixelColor(red: 255, green: 0, blue: 0)), "颜色优先于 HTML")
    assertEqual(SnipClipboardClassifier.classify(hasImage: false, filePaths: [], plainText: "普通文本", html: "<b>x</b>"),
                .html("<b>x</b>"), "HTML 优先于纯文本")
    assertEqual(SnipClipboardClassifier.classify(hasImage: false, filePaths: [], plainText: "普通文本", html: nil),
                .text("普通文本"), "纯文本")
    assertEqual(SnipClipboardClassifier.classify(hasImage: false, filePaths: [], plainText: "   ", html: "  "),
                nil, "空白内容不贴")
    assertEqual(SnipClipboardClassifier.classify(hasImage: false, filePaths: [], plainText: nil, html: nil),
                nil, "空剪贴板")

    // 颜色解析
    assertEqual(SnipClipboardClassifier.color(from: "#FF0000"), SnipPixelColor(red: 255, green: 0, blue: 0), "6 位 hex")
    assertEqual(SnipClipboardClassifier.color(from: "#0f0"), SnipPixelColor(red: 0, green: 255, blue: 0), "3 位 hex 展开")
    assertEqual(SnipClipboardClassifier.color(from: "rgb(0, 128, 255)"),
                SnipPixelColor(red: 0, green: 128, blue: 255), "rgb 函数")
    assertEqual(SnipClipboardClassifier.color(from: "rgba(255,0,0,0.5)"),
                SnipPixelColor(red: 255, green: 0, blue: 0), "rgba 取前三通道")
    assertEqual(SnipClipboardClassifier.color(from: "rgb(300, -10, 20)"),
                SnipPixelColor(red: 255, green: 0, blue: 20), "超范围分量被夹住")
    assertEqual(SnipClipboardClassifier.color(from: "#GGGGGG") == nil, true, "非法 hex 返回 nil")
    assertEqual(SnipClipboardClassifier.color(from: "红色") == nil, true, "普通文字不是颜色")
    assertEqual(SnipClipboardClassifier.color(from: "#FF00") == nil, true, "长度不对的 hex 返回 nil")
}

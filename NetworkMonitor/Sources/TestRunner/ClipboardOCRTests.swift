import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 图片文字识别口径（Core 纯逻辑）

/// 覆盖四件事：该不该识别（开关 / 类型 / 路径 / 三态）、结果怎么落库（空结果转终态）、
/// 失败冷却与次数上限（达上限转终态，不再每次启动重试）、闸门（并发 + 在途去重）。
func runClipboardOCRTests() {
    print("🧪 Testing Clipboard OCR policy...")

    // 1) 是否识别：开关关掉一律不识别（已有结果保留，新条目不入队）
    let image = ClipboardItem(kind: .image, preview: "图片 100×50", imagePath: "/tmp/clip.png",
                              imageWidth: 100, imageHeight: 50, contentHash: "ocr-a")
    assertEqual(ClipboardOCRPolicy.shouldRecognize(image, enabled: true), true, "图片 + 路径 + 未识别 → 入队")
    assertEqual(ClipboardOCRPolicy.shouldRecognize(image, enabled: false), false, "开关关掉不识别")
    assertEqual(ClipboardOCRPolicy.shouldRecognize(ClipboardItem(kind: .text, text: "纯文本", contentHash: "ocr-b"),
                                                   enabled: true), false, "文本条目不识别")
    var noPath = image; noPath.imagePath = nil
    assertEqual(ClipboardOCRPolicy.shouldRecognize(noPath, enabled: true), false, "没有落盘路径不识别")
    var emptyPath = image; emptyPath.imagePath = ""
    assertEqual(ClipboardOCRPolicy.shouldRecognize(emptyPath, enabled: true), false, "路径为空串不识别")

    // 2) 三态收敛：正文与空串都是终态，只有 NULL 可调度
    var recognized = image; recognized.ocrText = "识别出的文字"
    assertEqual(ClipboardOCRPolicy.shouldRecognize(recognized, enabled: true), false, "已有正文不再识别")
    var confirmedEmpty = image; confirmedEmpty.ocrText = ""
    assertEqual(ClipboardOCRPolicy.shouldRecognize(confirmedEmpty, enabled: true), false, "已确认为空不再识别")
    assertEqual(recognized.hasOCRText, true, "有正文时 hasOCRText 为真")
    assertEqual(confirmedEmpty.hasOCRText, false, "空串不算有识别文字")
    assertEqual(image.hasOCRText, false, "未识别不算有识别文字")
    assertEqual(ClipboardOCRPolicy.displayText(for: image), nil, "无识别结果时详情区不占位")
    assertEqual(ClipboardOCRPolicy.displayText(for: recognized), "识别出的文字", "有结果时给出展示文案")

    // 3) 结果整理：按阅读顺序拼行 → 空结果为空串（终态标记）
    let recognizedLines = [
        SnipTextLine(text: "第二行", confidence: 0.9, normalizedTop: 0.4, normalizedLeft: 0.1),
        SnipTextLine(text: "第一行", confidence: 0.9, normalizedTop: 0.9, normalizedLeft: 0.1),
    ]
    assertEqual(ClipboardOCRPolicy.storedText(from: recognizedLines), "第一行\n第二行", "按阅读顺序自上而下拼行")
    assertEqual(ClipboardOCRPolicy.storedText(from: []), "", "没有识别行时落空串（终态）")
    assertEqual(ClipboardOCRPolicy.storedText(from: [SnipTextLine(text: "噪声", confidence: 0.05)]), "",
                "全部低于置信度下限时落空串")
    let longText = String(repeating: "字", count: ClipboardOCRPolicy.maxStoredBytes)
    let truncated = ClipboardOCRPolicy.storedText(from: [SnipTextLine(text: longText, confidence: 0.9)])
    assertEqual(truncated.utf8.count <= ClipboardOCRPolicy.maxStoredBytes, true, "超长结果按字节上限截断")

    // 4) 失败冷却：首次可试 → 冷却内拒绝 → 冷却后可试 → 达上限转终态
    var policy = ClipboardOCRRetryPolicy(cooldown: 60, maxAttempts: 2)
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    assertEqual(policy.shouldAttempt(key: "k", now: t0), true, "从未失败可立即识别")
    assertEqual(policy.retryDelay(key: "k", now: t0), 0, "从未失败无需等待")
    policy.markFailed(key: "k", now: t0)
    assertEqual(policy.failureCount(key: "k"), 1, "失败次数累加")
    assertEqual(policy.shouldAttempt(key: "k", now: t0.addingTimeInterval(30)), false, "冷却未过不重试")
    assertEqual(policy.retryDelay(key: "k", now: t0.addingTimeInterval(30)), 30, "剩余冷却 30s")
    assertEqual(policy.shouldAttempt(key: "k", now: t0.addingTimeInterval(60)), true, "冷却到期可重试")
    policy.markFailed(key: "k", now: t0.addingTimeInterval(60))
    assertEqual(policy.isExhausted(key: "k"), true, "达次数上限转终态")
    assertEqual(policy.shouldAttempt(key: "k", now: t0.addingTimeInterval(9999)), false, "终态后永不再试")
    assertEqual(policy.retryDelay(key: "k", now: t0) == nil, true, "终态不再排期")
    policy.markSucceeded(key: "k")
    assertEqual(policy.failureCount(key: "k"), 0, "成功后清空失败记录")
    assertEqual(policy.shouldAttempt(key: "k", now: t0), true, "成功后重新可识别")
    assertEqual(policy.shouldAttempt(key: "   ", now: t0), false, "空白 key 视为非法入参")
    var resetPolicy = policy; resetPolicy.markFailed(key: "x", now: t0); resetPolicy.reset()
    assertEqual(resetPolicy.failureCount(key: "x"), 0, "reset 清空全部记录")
    assertEqual(ClipboardOCRRetryPolicy(maxAttempts: 0).maxAttempts, 2, "非法次数上限归一化为默认值")
    assertEqual(ClipboardOCRRetryPolicy(cooldown: -1).cooldown, 0, "负冷却归一化为 0")

    // 4b) 详情区展示：有识别文字才另起一行接在尺寸之后，没有就与改造前一致
    let detailImage = ClipboardItem(kind: .image, preview: "图片 1512×982", imagePath: "/tmp/detail.png",
                                    imageWidth: 1512, imageHeight: 982, contentHash: "ocr-detail")
    assertEqual(ClipboardDetailStrip.bodyText(for: detailImage), "图片 1512×982", "未识别时正文与改造前一致")
    assertEqual(ClipboardDetailStrip.bodyText(for: recognized),
                "图片 100×50\n识别出的文字", "有识别结果时另起一行接在尺寸之后")
    assertEqual(ClipboardDetailStrip.bodyText(for: confirmedEmpty), "图片 100×50", "确认无文字时不占位")

    // 5) 闸门：并发上限 + 在途去重 + 额度归还幂等
    assertEqual(ClipboardOCRLoadGate.defaultMaxConcurrent, 2, "默认并发 2")
    var gate = ClipboardOCRLoadGate()
    assertEqual(gate.beginLoad(key: "a"), true, "第 1 条通过")
    assertEqual(gate.beginLoad(key: "a"), false, "同一条在途时拒绝重复入队")
    assertEqual(gate.beginLoad(key: "b"), true, "第 2 条通过")
    assertEqual(gate.beginLoad(key: "c"), false, "并发满额时拒绝")
    gate.finishLoad(key: "a"); gate.finishLoad(key: "a")
    assertEqual(gate.activeCount, 1, "额度归还幂等（重复归还不多扣）")
    assertEqual(gate.beginLoad(key: "c"), true, "归还后可入队")
    gate.reset()
    assertEqual(gate.activeCount, 0, "reset 清空在途登记")
    assertEqual(ClipboardOCRLoadGate(maxConcurrent: 0).maxConcurrent, 2, "上限 0 归一化为默认值")

    print("✅ 图片文字识别口径 works")
}

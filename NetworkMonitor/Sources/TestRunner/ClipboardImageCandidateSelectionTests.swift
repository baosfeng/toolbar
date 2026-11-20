import Foundation
import NetworkMonitorCore

// MARK: - 采集端图片候选选择（单图字节上限口径）

/// 覆盖：只提供超限表示的复制（全屏裸 TIFF 22MB）不再静默丢弃，改走占位降级
func runClipboardImageCandidateSelectionTests() {
    print("🧪 Testing Clipboard image candidate selection...")

    func candidate(_ name: String, _ bytes: Int) -> ClipboardImageFormat.Selection {
        ClipboardImageFormat.Selection(typeName: name, data: Data(repeating: 0x01, count: bytes))
    }

    // 1) 正常：取第一个不超过上限的
    let normal = ClipboardImageCandidateSelection.select(candidates: [candidate("public.png", 1024)],
                                                         maxBytes: 4096)
    assertEqual(normal?.typeName, "public.png", "取到唯一候选")
    assertEqual(normal?.isOversized, false, "未超限不标 oversized")
    assertEqual(normal?.data.count, 1024, "字节原样带出")

    // 2) 全部超限：取第一个并标 oversized（旧实现这里返回 nil，历史里整条消失）
    let oversized = ClipboardImageCandidateSelection.select(
        candidates: [candidate("public.tiff", 8192), candidate("public.jpeg", 9000)], maxBytes: 4096)
    assertEqual(oversized?.isOversized, true, "全部超限时标 oversized 而不是丢弃")
    assertEqual(oversized?.typeName, "public.tiff", "取第一个超限候选")

    // 3) 前面超限、后面可用：取后面那个（PNG 优先语义不变）
    let mixed = ClipboardImageCandidateSelection.select(
        candidates: [candidate("public.tiff", 8192), candidate("public.png", 1024)], maxBytes: 4096)
    assertEqual(mixed?.isOversized, false, "有可用表示时不落进占位")
    assertEqual(mixed?.typeName, "public.png", "取可用的那个")

    // 4) 空候选 / 空字节
    assertEqual(ClipboardImageCandidateSelection.select(candidates: [], maxBytes: 4096) == nil,
                true, "空候选返回 nil")
    assertEqual(ClipboardImageCandidateSelection.select(candidates: [candidate("public.png", 0)],
                                                        maxBytes: 4096) == nil,
                true, "空字节返回 nil")

    // 5) 上限 ≤ 0 归一化为默认单图上限
    let normalized = ClipboardImageCandidateSelection.select(
        candidates: [candidate("public.png", ClipboardLimit.maxImageBytes + 1)], maxBytes: 0)
    assertEqual(normalized?.isOversized, true, "上限 ≤0 取默认值，超默认上限同样标 oversized")

    print("✅ Clipboard image candidate selection works")
}

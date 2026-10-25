import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板访问状态测试

/// 剪贴板访问权限的文案 / 色调 / 是否跳系统设置 — 纯规则，不依赖 AppKit
func runClipboardAccessTests() {
    print("\n🧪 Testing 剪贴板访问状态...")

    assertEqual(ClipboardAccessState.allCases.count, 5, "五种状态（allow/deny/ask/unspecified/unknown）")

    assertEqual(ClipboardAccessState.allowed.label, "已允许", "已允许文案")
    assertEqual(ClipboardAccessState.allowed.tone, .ok, "已允许为正常色调")
    assertEqual(ClipboardAccessState.allowed.needsSettingsJump, false, "已允许不显示跳转")

    assertEqual(ClipboardAccessState.denied.label, "已被拒绝", "拒绝文案")
    assertEqual(ClipboardAccessState.denied.tone, .warning, "拒绝为需处理色调")
    assertEqual(ClipboardAccessState.denied.needsSettingsJump, true, "拒绝时要能跳系统设置")

    assertEqual(ClipboardAccessState.ask.label, "每次询问", "每次询问文案")
    assertEqual(ClipboardAccessState.ask.tone, .warning, "每次询问为需处理色调")
    assertEqual(ClipboardAccessState.ask.needsSettingsJump, true, "每次询问时可跳转")

    assertEqual(ClipboardAccessState.unspecified.label, "默认", "系统默认文案")
    assertEqual(ClipboardAccessState.unspecified.tone, .muted, "系统默认用弱化色调")
    assertEqual(ClipboardAccessState.unspecified.needsSettingsJump, true, "系统默认可跳转")

    assertEqual(ClipboardAccessState.unknown.label, "未知", "低版本文案")
    assertEqual(ClipboardAccessState.unknown.tone, .muted, "未知用弱化色调")

    print("✅ 剪贴板访问状态 works")
}

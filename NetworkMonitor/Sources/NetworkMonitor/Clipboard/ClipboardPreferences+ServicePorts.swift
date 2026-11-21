import NetworkMonitorFeatureClipboard
import NetworkMonitorUI
import NetworkMonitorCore

// MARK: - 偏好聚合类适配服务层端口

/// 剪贴板偏好聚合类就是服务层端口的真实实现 —— 两处 conformance 都是空扩展
///
/// 为什么把偏好聚合类留在 App：它同时装着面板几何（ClipboardPanelLayout，设计系统侧的令牌）
/// 与全局热键组合（HotKeyCombo，Carbon 注册侧的值类型），这些不进服务层。
/// 服务层只声明「采集 / 识别需要的几个键」的端口（ClipboardCapturePreferences / ClipboardOCRPreferences），
/// 由这里一行适配，避免功能 target 反向依赖 App 可执行目标。
extension ClipboardPreferences: ClipboardCapturePreferences {}

/// 识别开关端口：采集后的 OCR 调度只读这一个键
extension ClipboardPreferences: ClipboardOCRPreferences {}

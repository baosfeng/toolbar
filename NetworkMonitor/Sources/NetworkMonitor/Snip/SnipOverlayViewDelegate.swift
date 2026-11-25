import AppKit

// MARK: - 覆盖层回调

/// 覆盖层向编排层发出的全部信号
///
/// 从 SnipOverlayView 主文件拆出：主文件此前同时装着协议、状态字段与生命周期，
/// 逼近单文件 15 KiB 门禁。协议本身是「覆盖层能对外说什么」，与视图实现无关。
@MainActor
protocol SnipOverlayViewDelegate: AnyObject {
    /// 用户按 Esc 或右键取消
    func overlayViewDidCancel(_ view: SnipOverlayView)
    /// 用户回车确认（本地点坐标）
    func overlayView(_ view: SnipOverlayView, didConfirm rect: CGRect)
    /// 用户要求切换「截图里是否包含鼠标指针」
    func overlayViewDidToggleCursor(_ view: SnipOverlayView)
    /// 用户要求保存选区（本地点坐标）；quick 为 true 表示快速保存
    func overlayView(_ view: SnipOverlayView, didRequestSave rect: CGRect, quick: Bool)
    /// 用户要求把选区贴到屏幕（本地点坐标）
    func overlayView(_ view: SnipOverlayView, didRequestPin rect: CGRect)
    /// 用户要求对选区做 OCR 文字识别（本地点坐标）
    func overlayView(_ view: SnipOverlayView, didRequestTextRecognition rect: CGRect)
    /// 输入框（文字 / 尺寸）开始或结束编辑
    ///
    /// 覆盖层要把这个信号同步给系统层按键通道：编辑态下白名单键必须放行，
    /// 否则输入框里的 a / 退格 / 回车会被当作截图指令吞掉（打不进字、删不掉）。
    func overlayView(_ view: SnipOverlayView, didChangeTextEditing isEditing: Bool)
}

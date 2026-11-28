import Foundation

// MARK: - 设置行的小图标口径

/// 「这一行该配哪个 SF Symbol」的白名单
///
/// 为什么用白名单而不是按关键字猜：设置行标题是人工文案（「开机自启动」「马赛克粒度」），
/// 关键字推断一定会把「通知」类与「额度通知」类混在一起，出现图标撒谎。
/// 白名单里没写的行就不画图标 —— 少一个图标不伤，画错一个反而误导。
///
/// 口径放 UI 库（纯值 + 纯函数）是为了让 TestRunner 能直接断言：
/// 每个键都映射到非空符号名，且未登记的标题必须返回 nil。
public enum SettingsRowIconMap {

    /// 标题全等 → SF Symbol（键是设置页里出现过的行名）
    public static let icons: [String: String] = [
        // 通用
        "开机自启动": "power",
        "额度用尽提醒": "bell.badge",
        "数值单位": "number",
        "面板展开收起": "rectangle.compress.vertical",
        "鼠标滚轮平滑": "computermouse",
        "速度增益": "speedometer",
        "持续时间": "timer",
        "最短步长": "ruler",
        "反向滚动": "arrow.up.arrow.down",
        // 外观
        "主题": "paintpalette",
        "玻璃效果": "circle.hexagongrid",
        "渲染帧率": "gauge.with.dots.needle.67percent",
        // 截图与贴图
        "默认颜色": "paintbrush",
        "线宽": "pencil.line",
        "虚线": "line.diagonal",
        "文字字号": "textformat.size",
        "马赛克粒度": "square.grid.3x3",
        "模糊强度": "drop",
        "文字提示": "text.bubble",
        "位置": "arrow.down.to.line",
        "标注工具": "pencil.and.outline",
        "颜色": "paintpalette",
        "快捷键": "keyboard",
        "输出格式": "doc",
        "JPEG 质量": "slider.horizontal.3",
        // 剪贴板
        "存储上限": "internaldrive",
        "最大条数": "list.number",
        "图片上限": "photo",
        "忽略的应用": "app.badge",
        "采集轮询": "arrow.triangle.2.circlepath",
        // 通知与音效
        "应用内音量": "speaker.wave.2",
        "音效库": "music.note.list",
        "系统通知": "bell",
        "触控板手感": "hand.tap",
        // Token
        "后台自动监控": "clock.arrow.circlepath",
        "扫描间隔": "timer",
        "已索引会话": "doc.text.magnifyingglass",
        "重新扫描": "arrow.clockwise",
        // 系统权限
        "辅助功能": "accessibility",
        "屏幕录制": "record.circle",
        "剪贴板访问": "doc.on.clipboard",
        "在 Finder 中显示": "folder",
        // 关于
        "检查更新": "arrow.triangle.2.circlepath",
        "自动下载安装": "arrow.down.circle",
        "当前版本": "tag",
        // 互传
        "设备名": "desktopcomputer",
        "端口": "network",
        "PIN": "key",
        "接收目录": "folder",
        // 补充：按设置页实际行标题覆盖（测试逐条解析符号名，写错会红）
        "默认不透明度": "circle.lefthalf.filled",
        "额度恢复通知": "bell.badge.waveform",
        "额度回升通知": "arrow.up.circle",
        "项目地址": "link",
        "面板高度": "rectangle.expand.vertical",
        "面板位置": "rectangle.on.rectangle",
        "采集模式": "square.stack.3d.up",
        "逐项自定义": "slider.horizontal.3",
        "超限告警": "exclamationmark.triangle",
        "识别后贴图": "text.viewfinder",
        "解压工具": "archivebox",
        "自定义音效": "music.note",
        "索引事件": "list.bullet.rectangle",
        "系统通知权限": "bell.badge",
        "窗口时长": "clock",
        "目标来源": "scope",
        "玻璃拟态": "circle.hexagongrid",
        "滚轮调数值": "arrow.up.arrow.down",
        "添加忽略应用": "plus.app",
        "最近扫描": "clock.arrow.circlepath",
        "最新版本": "tag",
        "暂停采集（复制的内容不入库）": "pause.circle",
        "显示 SoC 温度": "thermometer.medium",
        "新增实例": "plus.circle",
        "复制后自动保存": "arrow.down.doc",
        "快速保存目录": "folder.badge.gearshape",
        "快捷模板": "square.grid.2x2",
        "安装包": "shippingbox",
        "安装": "arrow.down.circle",
        "恢复默认": "arrow.counterclockwise",
        "退出": "rectangle.portrait.and.arrow.right",
        "输出动作": "square.and.arrow.up",
    ]

    /// 取图标；未登记返回 nil（调用方据此不画图标）
    public static func symbol(for title: String) -> String? {
        icons[title]
    }
}

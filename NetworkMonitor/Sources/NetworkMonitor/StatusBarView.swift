import AppKit

// MARK: - Status Bar Attributed String

/// 生成菜单栏的属性字符串 — 单行显示上下行网速
///
/// 格式：↓1.2 MB/s  ↑340 KB/s
///      绿色          橙色
enum StatusBarView {
    static func attributedString(downSpeed: String, upSpeed: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let result = NSMutableAttributedString()

        // 下行（绿色）
        result.append(NSAttributedString(string: "↓", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemGreen,
        ]))
        result.append(NSAttributedString(string: "\(downSpeed)/s", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemGreen,
        ]))

        // 间隔
        result.append(NSAttributedString(string: "  ", attributes: [.font: font]))

        // 上行（橙色）
        result.append(NSAttributedString(string: "↑", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemOrange,
        ]))
        result.append(NSAttributedString(string: "\(upSpeed)/s", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemOrange,
        ]))

        return result
    }
}

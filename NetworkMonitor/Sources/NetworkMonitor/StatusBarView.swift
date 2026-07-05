import AppKit

// MARK: - Status Bar Attributed String

/// 生成菜单栏的属性字符串 — 单行显示上下行网速
///
/// 格式：↑340 KB/s  ↓1.2 MB/s
///      橙色          绿色
enum StatusBarView {
    static func attributedString(downSpeed: String, upSpeed: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let result = NSMutableAttributedString()

        // 上行（橙色）- 放左边
        result.append(NSAttributedString(string: "↑", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemOrange,
        ]))
        result.append(NSAttributedString(string: "\(upSpeed)/s", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemOrange,
        ]))

        // 间隔
        result.append(NSAttributedString(string: "  ", attributes: [.font: font]))

        // 下行（绿色）- 放右边
        result.append(NSAttributedString(string: "↓", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemGreen,
        ]))
        result.append(NSAttributedString(string: "\(downSpeed)/s", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemGreen,
        ]))

        return result
    }
}

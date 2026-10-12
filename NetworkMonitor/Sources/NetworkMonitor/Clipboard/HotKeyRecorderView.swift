import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 快捷键录制控件

/// 快捷键录制控件 — 点击后进入录制态，按下「修饰键 + 单键」即完成录制
///
/// 录制约束：必须带至少一个修饰键（单键全局热键会吞掉正常输入）；Esc 取消录制。
@MainActor
final class HotKeyRecorderView: NSView {

    /// 当前组合键
    var combo: HotKeyCombo = .defaultPanelToggle {
        didSet { needsDisplay = true }
    }
    /// 录制完成回调（由设置窗做冲突检测与重新注册）
    var onChange: ((HotKeyCombo) -> Void)?
    /// 是否处于冲突态（由设置窗在注册失败后置位）
    var isConflicted = false {
        didSet { needsDisplay = true }
    }

    private var isRecording = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "点击后按下新的组合键（需包含 ⌘ / ⌥ / ⌃ / ⇧），Esc 取消"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        guard Int(event.keyCode) != kVK_Escape else {
            isRecording = false
            needsDisplay = true
            return
        }
        let modifiers = HotKeyCombo.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        isRecording = false
        combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        onChange?(combo)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isRecording {
            isRecording = false
            needsDisplay = true
        }
        return result
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        if isConflicted {
            NSColor.systemRed.setStroke()
            path.lineWidth = 1.5
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        let text: String
        if isRecording {
            text = "请按下组合键…"
        } else if isConflicted {
            text = "\(combo.displayString)（冲突）"
        } else {
            text = combo.displayString
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isConflicted ? NSColor.systemRed : NSColor.labelColor
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                    withAttributes: attributes)
    }
}

import Foundation

// MARK: - 截图键盘接线守卫用例
//
// 判据本身在 SnipKeyboardWiringGuard.swift（与本文件同目录）：两者拆开是为了守住
// 单文件 15 KiB 门禁。这里只放「健康接线全绿 + 错误形态必红 + 真实源码树无命中」。

// MARK: - 用例

func runSnipKeyboardWiringTests() {
    print("\n🧪 Testing 截图键盘接线守卫（编辑态信号必须接上）...")

    let keyboardOK = [
        "final class Bridge {",
        "    func setEditing(_ value: Bool) {",
        "        gate.setEditing(value)",
        "    }",
        "    func receiveSystemKey() {",
        "        guard !overlay.hasActiveTextInput else { return }",
        "    }",
        "}",
        "extension Controller {",
        "    func setKeyboardEditing(_ editing: Bool) {",
        "        keyboardBridge?.setEditing(editing)",
        "    }",
        "}",
    ].joined(separator: "\n")
    let overlayOK = [
        "private(set) var textEditor: SizeEditorField? {",
        "    didSet { textEditingDidChange() }",
        "}",
        "private(set) var sizeEditor: SizeEditorField? {",
        "    didSet { textEditingDidChange() }",
        "}",
        "delegate?.overlayView(self, didChangeTextEditing: hasActiveTextInput)",
        "private func textEditingDidChange() { }",
        "func replaceTextEditor(_ field: SizeEditorField?) {",
        "    textEditor = field",
        "}",
        "func replaceSizeEditor(_ field: SizeEditorField?) {",
        "    sizeEditor = field",
        "}",
    ].joined(separator: "\n")
    let windowOK = [
        "private func claimFirstResponderIfNeeded() {",
        "    guard !overlayView.hasActiveTextInput else { return }",
        "    makeFirstResponder(overlayView)",
        "}",
    ].joined(separator: "\n")
    let editingOK = [
        "extension SnipOverlayView {",
        "    func beginTextEditing() {",
        "        replaceTextEditor(field)",
        "    }",
        "    func replaceTextEditor(_ field: SizeEditorField?) {",
        "        textEditor = field",
        "    }",
        "    func replaceSizeEditor(_ field: SizeEditorField?) {",
        "        sizeEditor = field",
        "    }",
        "}",
        "extension SnipController {",
        "    func setKeyboardEditing(_ editing: Bool) {",
        "        keyboardBridge?.setEditing(editing)",
        "    }",
        "}",
    ].joined(separator: "\n")
    // 协议已从覆盖层主文件拆到独立文件：契约断言扫那一份
    let delegateOK = "func overlayView(_ view: SnipOverlayView, didChangeTextEditing isEditing: Bool)"
    let healthy = [SnipKeyboardWiringGuard.keyboardFile: keyboardOK,
                   SnipKeyboardWiringGuard.overlayFile: overlayOK,
                   SnipKeyboardWiringGuard.windowFile: windowOK,
                   SnipKeyboardWiringGuard.delegateFile: delegateOK,
                   SnipKeyboardWiringGuard.editingFile: editingOK]
    assertEqual(SnipKeyboardWiringGuard.violations(sources: healthy), [], "健康接线无命中")

    func issuesWith(_ path: String, _ text: String) -> [SnipKeyboardWiringIssue] {
        SnipKeyboardWiringGuard.violations(sources: healthy.merging([path: text]) { _, new in new })
    }

    // 复现当初的错误形态：接收端先 guard 再写同一个条件（写入点不可达）
    let deadWrite = [
        "final class Bridge {",
        "    func setEditing(_ value: Bool) {",
        "        gate.setEditing(value)",
        "    }",
        "    func receiveSystemKey() {",
        "        guard !overlay.hasActiveTextInput else { return }",
        "        keyboardBridge?.setEditing(overlay.hasActiveTextInput)",
        "    }",
        "}",
    ].joined(separator: "\n")
    let deadIssues = issuesWith(SnipKeyboardWiringGuard.keyboardFile, deadWrite)
    assertEqual(deadIssues.contains { $0.reason.contains("receiveSystemKey") }, true,
                "接收端写编辑态即命中")
    assertEqual(deadIssues.contains { $0.reason.contains("setKeyboardEditing") }, true,
                "并指出唯一写入口不存在")

    // 旧状态位残留
    let legacy = keyboardOK + "\nlet passThrough = false\nbridge.setPassThrough(false)"
    assertEqual(issuesWith(SnipKeyboardWiringGuard.keyboardFile, legacy)
                    .contains { $0.reason.contains("setPassThrough") }, true,
                "旧状态位残留即命中")

    // 输入框字段散着赋值（没有 private(set)）
    let looseField = overlayOK.replacingOccurrences(of: "private(set) var textEditor", with: "var textEditor")
    assertEqual(issuesWith(SnipKeyboardWiringGuard.overlayFile, looseField)
                    .contains { $0.reason.contains("private(set)") }, true,
                "输入框字段不是 private(set) 即命中")

    // 缺 delegate 通知（didSet 没接）
    let noNotify = overlayOK.replacingOccurrences(of: "didSet { textEditingDidChange() }", with: "didSet { }")
    assertEqual(issuesWith(SnipKeyboardWiringGuard.overlayFile, noNotify)
                    .contains { $0.reason.contains("didSet") }, true,
                "didSet 没通知即命中")

    // 输入框字段被直写（绕过收口 → 编辑态信号漏掉）
    let directWrite = editingOK.replacingOccurrences(of: "        replaceTextEditor(field)",
                                                     with: "        textEditor = field")
    assertEqual(issuesWith(SnipKeyboardWiringGuard.editingFile, directWrite)
                    .contains { $0.reason.contains("replaceTextEditor") }, true,
                "直写输入框字段即命中")

    // 焦点重试无条件抢焦点
    let ungated = [
        "private func claimFirstResponderIfNeeded() {",
        "    makeFirstResponder(overlayView)",
        "}",
        "func retry() {",
        "    makeFirstResponder(overlayView)",
        "}",
    ].joined(separator: "\n")
    let ungatedIssues = issuesWith(SnipKeyboardWiringGuard.windowFile, ungated)
    assertEqual(ungatedIssues.contains { $0.reason.contains("抢走输入框焦点") }, true,
                "无条件 makeFirstResponder 即命中")
    assertEqual(ungatedIssues.contains { $0.reason.contains("hasActiveTextInput") }, true,
                "并指出要看编辑态")

    // 真实源码树
    guard let root = SnipKeyboardWiringGuard.sourceRoot() else {
        print("❌ 找不到源码根 Sources/NetworkMonitor（#filePath 反推失败）")
        exit(1)
    }
    var real: [String: String] = [:]
    for path in [SnipKeyboardWiringGuard.keyboardFile,
                 SnipKeyboardWiringGuard.overlayFile,
                 SnipKeyboardWiringGuard.windowFile,
                 SnipKeyboardWiringGuard.delegateFile,
                 SnipKeyboardWiringGuard.editingFile] {
        let url = root.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("❌ 读不到源码：\(url.path)")
            exit(1)
        }
        real[path] = text
    }
    let issues = SnipKeyboardWiringGuard.violations(sources: real)
    guard issues.isEmpty else {
        print(SnipKeyboardWiringGuard.failureMessage(issues))
        exit(1)
    }

    print("✅ 截图键盘接线守卫通过（编辑态单点写入 / 字段收口 / 焦点不抢）")
}

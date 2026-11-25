import Foundation

// MARK: - 截图键盘接线的源码守卫（回归：编辑态信号从未写进 tap）
//
// 「文字打不进字」这个 bug 第二次复发的原因很刺眼：纯函数 SnipKeyboardRouting 全绿，
// 但编辑态信号写在接收端、被一行 guard 挡成死代码，于是 tap 恒按非编辑态裁决。
// 纯逻辑测试测不到「信号有没有被接上」，所以这里像 SnipDockIconPolicyTests 一样
// 直接读源文件做文本断言，把「错误形态」钉成判据。

/// 一处接线问题
struct SnipKeyboardWiringIssue: Equatable {
    let path: String
    let line: Int
    let reason: String

    var readable: String { "\(path):\(line) \(reason)" }
}

/// 接线守卫：文本级判据 + 真实源码树扫描
enum SnipKeyboardWiringGuard {

    static let keyboardFile = "Snip/SnipController+Keyboard.swift"
    static let overlayFile = "Snip/SnipOverlayView.swift"
    static let windowFile = "Snip/SnipOverlayWindow.swift"
    /// 输入框与编辑态接线的收口文件（文字输入 + 编辑态信号都在这儿）
    static let editingFile = "Snip/SnipTextEditing.swift"
    /// delegate 契约所在文件（协议已从 SnipOverlayView 主文件拆出，契约在哪就要扫到哪）
    static let delegateFile = "Snip/SnipOverlayViewDelegate.swift"

    /// 允许写编辑态的函数名：桥接层自己的 setEditing + 编排层唯一的 setKeyboardEditing
    static let editingWriters = ["setEditing", "setKeyboardEditing"]

    /// 去掉行注释（行号保持对齐）；被注释掉的旧写法与说明文字不该算命中
    static func codeLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            guard let range = line.range(of: "//") else { return line }
            return String(line[line.startIndex..<range.lowerBound])
        }
    }

    /// 函数的行号区间（1 起）：从 `func 名字(` 那行按大括号配平扫到收尾
    ///
    /// 只做文本配平、不解析语法树：本仓的函数体缩进与大括号风格一致，
    /// 对「体里有没有某句调用」这个用途足够。
    static func functionSpan(named name: String, in lines: [String]) -> ClosedRange<Int>? {
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else { return nil }
        var depth = 0
        var opened = false
        for index in start..<lines.count {
            for character in lines[index] {
                if character == "{" { depth += 1; opened = true }
                if character == "}" { depth -= 1 }
            }
            if opened && depth <= 0 { return (start + 1)...(index + 1) }
        }
        return nil
    }

    /// 判定一批源码里的接线问题
    static func violations(sources: [String: String]) -> [SnipKeyboardWiringIssue] {
        var issues: [SnipKeyboardWiringIssue] = []
        issues.append(contentsOf: keyboardIssues(sources[keyboardFile]))
        issues.append(contentsOf: wiringIssues(sources[editingFile] ?? "", path: editingFile))
        issues.append(contentsOf: overlayIssues(sources[overlayFile],
                                                delegateSource: sources[delegateFile]))
        issues.append(contentsOf: windowIssues(sources[windowFile]))
        return issues.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }

    /// 键盘通道：编辑态只有一个写入口，且不在接收端
    private static func keyboardIssues(_ raw: String?) -> [SnipKeyboardWiringIssue] {
        guard let raw else { return [] }
        let lines = codeLines(raw)
        var issues: [SnipKeyboardWiringIssue] = []

        let spans = editingWriters.compactMap { functionSpan(named: $0, in: lines) }
        if spans.isEmpty {
            issues.append(SnipKeyboardWiringIssue(path: keyboardFile, line: 1,
                                                  reason: "找不到 setKeyboardEditing（编辑态唯一写入口）"))
        }
        for (index, line) in lines.enumerated() where line.contains(".setEditing(") {
            let number = index + 1
            if !spans.contains(where: { $0.contains(number) }) {
                issues.append(SnipKeyboardWiringIssue(
                    path: keyboardFile, line: number,
                    reason: "编辑态写入点必须在 setEditing / setKeyboardEditing 内（在别处写会晚一拍，甚至永不执行）"))
            }
        }
        for (index, line) in lines.enumerated() where line.contains("setPassThrough") {
            issues.append(SnipKeyboardWiringIssue(
                path: keyboardFile, line: index + 1,
                reason: "旧状态位 setPassThrough 应已下线（其唯一写入点被 guard 挡成死代码）"))
        }
        // 接收端不许自己改编辑态（历史上就是这一处被 guard 挡成死代码）
        if let receive = functionSpan(named: "receiveSystemKey", in: lines) {
            for index in (receive.lowerBound - 1)...(receive.upperBound - 1)
            where lines[index].contains(".setEditing(") {
                issues.append(SnipKeyboardWiringIssue(
                    path: keyboardFile, line: index + 1,
                    reason: "receiveSystemKey 里不得写编辑态（吞键发生在它被调用之前）"))
            }
        }
        return issues
    }

    /// 输入框编辑态接线：五个入口全部经 replaceTextEditor / replaceSizeEditor 收口
    ///
    /// 散着写字段就一定会漏掉某个入口（本轮就是尺寸框那条链路没人管编辑态），
    /// 所以这里只认「经收口函数写」，且收口函数必须 call 编辑态通知。
    private static func wiringIssues(_ raw: String, path: String) -> [SnipKeyboardWiringIssue] {
        guard !raw.isEmpty else {
            return [SnipKeyboardWiringIssue(path: path, line: 1, reason: "读不到输入框编辑态的收口文件")]
        }
        let lines = codeLines(raw)
        var issues: [SnipKeyboardWiringIssue] = []

        // 收口函数定义在 SnipOverlayView 主文件里，本文件只负责「经它写」；这里取本文件的定义做豁免
        let setters = ["replaceTextEditor", "replaceSizeEditor"].compactMap { functionSpan(named: $0, in: lines) }
        // 除收口函数外，任何地方都不许直接赋 textEditor / sizeEditor：那就是漏信号的形态
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("textEditor =") || trimmed.hasPrefix("sizeEditor =") else { continue }
            let number = index + 1
            if !setters.contains(where: { $0.contains(number) }) {
                issues.append(SnipKeyboardWiringIssue(
                    path: path, line: number,
                    reason: "输入框字段必须经 replaceTextEditor / replaceSizeEditor 写（直写会漏掉编辑态通知）"))
            }
        }
        if !lines.contains(where: { $0.contains("func setKeyboardEditing(") }) {
            issues.append(SnipKeyboardWiringIssue(
                path: path, line: 1,
                reason: "缺 setKeyboardEditing（编辑态到按键通道的唯一写入口）"))
        }
        if !lines.contains(where: { $0.contains("keyboardBridge?.setEditing(") }) {
            issues.append(SnipKeyboardWiringIssue(
                path: path, line: 1,
                reason: "setKeyboardEditing 必须把编辑态写进按键桥"))
        }
        return issues
    }

    /// 覆盖层：两个输入框都要 private(set) + didSet 通知，信号生产侧不能靠自觉
    private static func overlayIssues(_ raw: String?,
                                     delegateSource: String?) -> [SnipKeyboardWiringIssue] {
        guard let raw else { return [] }
        let lines = codeLines(raw)
        var issues: [SnipKeyboardWiringIssue] = []

        // 两个收口函数必须存在：编辑态的同步只能从这两处发生
        for setter in ["replaceTextEditor", "replaceSizeEditor"] {
            if functionSpan(named: setter, in: lines) == nil {
                issues.append(SnipKeyboardWiringIssue(
                    path: overlayFile, line: 1,
                    reason: "缺 \(setter) 收口函数（输入框写入必须走它，否则编辑态信号会漏）"))
            }
        }
        for name in ["textEditor", "sizeEditor"] {
            guard let index = lines.firstIndex(where: { $0.contains("\(name): SizeEditorField?") }) else {
                issues.append(SnipKeyboardWiringIssue(path: overlayFile, line: 1,
                                                      reason: "找不到输入框字段 \(name)"))
                continue
            }
            if !lines[index].contains("private(set)") {
                issues.append(SnipKeyboardWiringIssue(
                    path: overlayFile, line: index + 1,
                    reason: "\(name) 必须是 private(set)：编辑态要在收口处通知，不能散着赋值"))
            }
            let next = index + 1
            if next >= lines.count || !lines[next].contains("textEditingDidChange()") {
                issues.append(SnipKeyboardWiringIssue(
                    path: overlayFile, line: index + 1,
                    reason: "\(name) 的 didSet 必须调用 textEditingDidChange()（否则编辑态传不出去）"))
            }
        }
        // delegate 契约在独立文件里（协议已从主文件拆出），契约与调用各至少一处
        let delegateLines = codeLines(delegateSource ?? "")
        if !delegateLines.contains(where: { $0.contains("didChangeTextEditing isEditing:") }) {
            issues.append(SnipKeyboardWiringIssue(path: overlayFile, line: 1,
                                                  reason: "delegate 里缺 didChangeTextEditing 契约"))
        }
        if !lines.contains(where: { $0.contains("didChangeTextEditing: hasActiveTextInput") }) {
            issues.append(SnipKeyboardWiringIssue(path: overlayFile, line: 1,
                                                  reason: "缺「通知编辑态变化」的调用（delegate 收不到信号）"))
        }
        return issues
    }

    /// 窗口：焦点重试不许抢正在编辑的输入框
    private static func windowIssues(_ raw: String?) -> [SnipKeyboardWiringIssue] {
        guard let raw else { return [] }
        let lines = codeLines(raw)
        var issues: [SnipKeyboardWiringIssue] = []

        guard let span = functionSpan(named: "claimFirstResponderIfNeeded", in: lines) else {
            return [SnipKeyboardWiringIssue(path: windowFile, line: 1,
                                            reason: "找不到 claimFirstResponderIfNeeded（焦点重试要有条件）")]
        }
        let body = lines[(span.lowerBound - 1)...(span.upperBound - 1)]
        if !body.contains(where: { $0.contains("hasActiveTextInput") }) {
            issues.append(SnipKeyboardWiringIssue(
                path: windowFile, line: span.lowerBound,
                reason: "claimFirstResponderIfNeeded 必须按 hasActiveTextInput 判断是否让出焦点"))
        }
        for (index, line) in lines.enumerated()
        where line.contains("makeFirstResponder(overlayView)") || line.contains("makeFirstResponder(self.overlayView)") {
            let number = index + 1
            if !span.contains(number) {
                issues.append(SnipKeyboardWiringIssue(
                    path: windowFile, line: number,
                    reason: "无条件 makeFirstResponder(overlayView) 会抢走输入框焦点，必须走 claimFirstResponderIfNeeded"))
            }
        }
        return issues
    }

    /// 源码根 = <repo>/NetworkMonitor/Sources/NetworkMonitor（#filePath 反推，与激活策略守卫同口径）
    static func sourceRoot(swiftFilePath: String = #filePath) -> URL? {
        let fileURL = URL(fileURLWithPath: swiftFilePath)
        let sourcesDir = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            sourcesDir.appendingPathComponent("NetworkMonitor"),
            cwd.appendingPathComponent("Sources/NetworkMonitor"),
            cwd.appendingPathComponent("NetworkMonitor/Sources/NetworkMonitor"),
        ]
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    /// 失败信息
    static func failureMessage(_ issues: [SnipKeyboardWiringIssue]) -> String {
        var lines = ["❌ 截图键盘接线有 \(issues.count) 处问题（编辑态信号可能又没接上）"]
        for issue in issues { lines.append("   • \(issue.readable)") }
        lines.append("")
        lines.append("改法：编辑态由 SnipOverlayView 的输入框 didSet → delegate → SnipController.setKeyboardEditing；")
        lines.append("     tap 侧只经 SnipKeyboardGate 读编辑态；焦点重试走 claimFirstResponderIfNeeded。")
        return lines.joined(separator: "\n")
    }
}

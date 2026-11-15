import Foundation

// MARK: - 步骤执行器（nmcli run）

/// 把一串步骤跑完：失败即停、每步打印耗时、任一失败整体 exit 1
///
/// 变量约定：`set k=v` 写入变量表，后续步骤的 `$(k)` 会替换后再解析。
/// 用 `$(k)` 而不是 `${k}`，因为后者在 shell 里会被提前展开成空串。
struct Runner {

    private var variables: [String: String] = [:]
    private(set) var outcomes: [StepOutcome] = []

    /// 执行脚本，返回是否全部成功
    mutating func run(_ script: String) -> Bool {
        let steps = StepParser.split(script)
        guard !steps.isEmpty else {
            Out.note("脚本为空")
            return false
        }
        for (index, raw) in steps.enumerated() {
            let text = StepParser.interpolate(raw, variables: variables)
            let started = Date()
            do {
                try perform(text)
                let elapsed = Format.milliseconds(Date().timeIntervalSince(started))
                outcomes.append(StepOutcome(index: index + 1, step: text, ok: true, milliseconds: elapsed, detail: ""))
                Out.line("[\(index + 1)] \(text) -> ok (\(elapsed)ms)")
            } catch {
                let elapsed = Format.milliseconds(Date().timeIntervalSince(started))
                let message = (error as? CLIError)?.description ?? "\(error)"
                outcomes.append(StepOutcome(index: index + 1, step: text, ok: false, milliseconds: elapsed, detail: message))
                Out.line("[\(index + 1)] \(text) -> fail (\(elapsed)ms) \(message)")
                return false
            }
        }
        return true
    }

    /// 单步分派；`set` / `assert` / `wait-window` 在这里做词法层处理
    private mutating func perform(_ text: String) throws {
        let step = try StepParser.parse(text)
        let args = step.args
        switch step.command {
        case "set":
            try setVariable(args)
        case "wait":
            try Commands.wait(args)
        case "wait-window":
            try Commands.waitWindow(args)
        case "assert":
            try assertStep(args)
        case "click":
            try Commands.click(args)
        case "click-at":
            try Commands.clickAt(args)
        case "hover":
            try Commands.hover(args)
        case "type":
            try Commands.type(args)
        case "key":
            try Commands.key(args)
        case "shot":
            try Commands.shot(args)
        case "at":
            try Commands.at(args)
        case "find":
            try Commands.find(args)
        case "menubar":
            try Commands.menubar(args)
        case "windows":
            try Commands.windows(args)
        case "apps":
            try Commands.apps(args)
        default:
            throw CLIError("未知步骤「\(step.command)」（支持 set/wait/wait-window/assert/click/click-at/hover/type/key/shot/at/find/menubar/windows/apps）")
        }
    }

    private mutating func setVariable(_ args: Args) throws {
        let tokens = args.positionals
        guard !tokens.isEmpty else { throw CLIError("用法：set k=v") }
        for token in tokens {
            guard let separator = token.firstIndex(of: "=") else {
                throw CLIError("set 需要 k=v 形式，收到「\(token)」")
            }
            let key = String(token[token.startIndex..<separator])
            let value = String(token[token.index(after: separator)...])
            variables[key] = value
        }
    }

    private mutating func assertStep(_ args: Args) throws {
        guard let kind = args.positionals.first else {
            throw CLIError("用法：assert window|element|pixels …")
        }
        // 断言关键字之后的位置参数才是断言自己的（app 名 / 图路径），选项原样透传
        let rest = args.droppingPositional(0)
        switch kind {
        case "window":
            try Assertions.window(rest)
        case "element":
            try Assertions.element(rest)
        case "pixels":
            try Assertions.pixels(rest)
        default:
            throw CLIError("未知断言「\(kind)」（支持 window / element / pixels）")
        }
    }
}

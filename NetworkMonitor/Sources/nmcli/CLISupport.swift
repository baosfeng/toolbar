import Foundation

// MARK: - CLI 基础设施（错误 / 输出 / 参数解析）

/// CLI 统一错误：只带一句人话，由 main 捕获后打到 stderr 并以 exit 1 结束
struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ message: String) {
        description = message
    }
}

/// 结果通道：数据走 stdout（可被脚本读取），诊断与失败走 stderr
enum Out {
    static func line(_ text: String = "") {
        print(text)
    }

    static func note(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// 极简参数解析：位置参数保序，选项统一为 `--name value` 或 `--name`
///
/// 取值规则：选项后的下一个 token 不以 `--` 开头时当作它的值，否则记为布尔 true。
/// 这样 `--layer 25 --gone` 与 `--gone` 两种写法都不需要额外声明。
struct Args {
    let positionals: [String]
    private let options: [String: String]
    /// 原始 token（去掉一个位置参数后重新解析时用，顺序敏感）
    private let raw: [String]

    init(_ raw: [String]) {
        var positionals: [String] = []
        var options: [String: String] = [:]
        var index = 0
        while index < raw.count {
            let token = raw[index]
            guard token.hasPrefix("--"), token.count > 2 else {
                positionals.append(token)
                index += 1
                continue
            }
            let name = String(token.dropFirst(2))
            let next = index + 1 < raw.count ? raw[index + 1] : nil
            if let next, !next.hasPrefix("--") {
                options[name] = next
                index += 2
            } else {
                options[name] = "true"
                index += 1
            }
        }
        self.positionals = positionals
        self.options = options
        self.raw = raw
    }

    /// 去掉第 index 个位置参数后的同一份参数（`assert window <app> …` 转交 span 时用）
    func droppingPositional(_ index: Int) -> Args {
        var tokens = raw
        var seen = 0
        var cursor = 0
        while cursor < tokens.count {
            let token = tokens[cursor]
            let isOption = token.hasPrefix("--") && token.count > 2
            let nextIsValue = isOption && cursor + 1 < tokens.count && !tokens[cursor + 1].hasPrefix("--")
            if isOption {
                cursor += nextIsValue ? 2 : 1
                continue
            }
            if seen == index {
                tokens.remove(at: cursor)
                return Args(tokens)
            }
            seen += 1
            cursor += 1
        }
        return self
    }

    /// 布尔开关：出现即 true
    func flag(_ name: String) -> Bool {
        options[name] != nil
    }

    func string(_ name: String) -> String? {
        guard let value = options[name], value != "true" else { return nil }
        return value
    }

    func int(_ name: String) throws -> Int? {
        guard let text = string(name) else { return nil }
        guard let value = Int(text) else {
            throw CLIError("选项 --\(name) 需要整数，收到「\(text)」")
        }
        return value
    }

    func double(_ name: String) throws -> Double? {
        guard let text = string(name) else { return nil }
        guard let value = Double(text) else {
            throw CLIError("选项 --\(name) 需要数字，收到「\(text)」")
        }
        return value
    }

    /// 取第 n 个位置参数，缺失即报错（错误文案带上用法提示）
    func positional(_ index: Int, _ name: String) throws -> String {
        guard index < positionals.count else {
            throw CLIError("缺少参数：<\(name)>")
        }
        return positionals[index]
    }
}

// MARK: - 格式化

enum Format {
    /// 坐标统一保留一位小数：AX / CGWindow 都是浮点，截断成整数会丢半像素
    static func point(_ point: CGPoint) -> String {
        String(format: "%.1f,%.1f", point.x, point.y)
    }

    static func rect(_ rect: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }

    static func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }
}

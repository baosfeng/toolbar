import Foundation

// MARK: - 步骤解析（run / scenario 共用）

/// 一条步骤：命令名 + 位置参数 + 选项（选项值与 `--name value` 同义）
struct Step {
    let command: String
    let positionals: [String]
    let args: Args

    /// 原始文本（打印日志用，变量已替换后的形态）
    let source: String
}

enum StepParser {

    /// 把一整串脚本切成步骤：分号分隔，双引号内的分号不切
    ///
    /// 只支持双引号（单引号也认），不做转义——验收脚本里写的是坐标和元素名，
    /// 引入完整 shell 语法只会让 `$(k)` 插值与引号互相打架。
    static func split(_ script: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var quote: Character?
        for character in script {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character == ";" {
                chunks.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        chunks.append(current)
        return chunks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// 变量插值：`$(name)` → 值；未知变量保留原文（让后续步骤报错时看得见）
    static func interpolate(_ text: String, variables: [String: String]) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "(" {
                var cursor = text.index(index, offsetBy: 2)
                var name = ""
                var closed = false
                while cursor < text.endIndex {
                    if text[cursor] == ")" { closed = true; break }
                    name.append(text[cursor])
                    cursor = text.index(after: cursor)
                }
                if closed {
                    result += variables[name] ?? "$(\(name))"
                    index = text.index(after: cursor)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    /// 一条步骤 → Step；`set k=v` 由调用方先处理
    static func parse(_ text: String) throws -> Step {
        let tokens = tokenize(text)
        guard let command = tokens.first else { throw CLIError("空步骤") }
        return Step(command: command,
                    positionals: [],
                    args: Args(Array(tokens.dropFirst())),
                    source: text)
    }

    /// 按空白切词，双引号内的空白保留
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasContent = false
        for character in text {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                hasContent = true
                continue
            }
            if character == " " || character == "\t" {
                if hasContent || !current.isEmpty {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
                continue
            }
            current.append(character)
        }
        if hasContent || !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

// MARK: - 步骤台账

/// 一步的执行结果（summary.json 的一行）
struct StepOutcome {
    let index: Int
    let step: String
    let ok: Bool
    let milliseconds: Int
    let detail: String
}

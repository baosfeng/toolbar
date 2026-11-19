import Foundation

// MARK: - 错误体文案提取

/// 错误响应体 → 可读文案 —— 全仓唯一一份提取实现
///
/// 后端形态各家不同，差异收敛成一个 `Dialect`（只是取值顺序不同，不是多份实现）：
/// - `.generic`：error（字符串）→ error.message → message → detail（App 侧 6 家与统一口径）
/// - `.plainError`：只认顶层 error 字符串（Ollama / Open Design）
/// - `.errorOrNested`：顶层 error（非空）→ error.message（OpenCode Go）
///
/// **空串语义与改造前逐字一致**：`.generic` / `.plainError` 拿到空串就返回空串
/// （上层按「有文案但为空」处理），`.errorOrNested` 的顶层 error 才把空串当没给。
public enum HTTPErrorBody {

    /// 错误体方言 —— 与 provider 后端的实际形态一一对应
    public enum Dialect: Sendable {
        /// error（字符串）→ error.message → message → detail
        case generic
        /// 只认顶层 error 字符串
        case plainError
        /// 顶层 error（非空）→ error.message
        case errorOrNested
    }

    /// 按方言提取文案（非 JSON / 字段缺失返回 nil）
    public static func message(from data: Data, dialect: Dialect = .generic) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        switch dialect {
        case .generic:
            if let text = object["error"] as? String { return text }
            if let nested = object["error"] as? [String: Any],
               let text = nested["message"] as? String { return text }
            if let text = object["message"] as? String { return text }
            if let text = object["detail"] as? String { return text }
            return nil
        case .plainError:
            return object["error"] as? String
        case .errorOrNested:
            if let text = object["error"] as? String, !text.isEmpty { return text }
            if let nested = object["error"] as? [String: Any],
               let text = nested["message"] as? String { return text }
            return nil
        }
    }

    /// 通用方言的提取入口（可直接当闭包默认值传；Swift 不允许带默认参数的函数作默认值）
    public static func genericMessage(from data: Data) -> String? {
        message(from: data, dialect: .generic)
    }
}

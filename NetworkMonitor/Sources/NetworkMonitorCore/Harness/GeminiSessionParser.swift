import Foundation

// MARK: - Gemini CLI 会话解析

/// Gemini CLI 聊天记录解析（设计规格 §2.3）
///
/// 记录形态（第一手证据：官方 packages/core/src/services/chatRecordingService.ts）：append-only
/// JSONL，四类 —— 消息 {id,timestamp,type,content,tokens?}、元信息 $set（messages 全量重写已
/// deprecated）、补丁 $patch（id/updates/removeIds/orderIds）、截断 $rewindTo；旧版整份 JSON 给
/// messages 数组，入口先试整体解析、失败再逐行。
///
/// 硬约束：tokens 为 null 跳过（不补 0）；同一 id 会被再 append 一次（recordMessageTokens 回填
/// usage 后 pushMessage 又写一遍整条）→ 后者胜且只算一次请求数；$rewindTo 截断该 id 及其后
/// （找不到则清空），$patch 只改已有消息；四桶 uncachedInput = prompt - cached + tool、
/// output = candidates + thoughts、cacheWrite = 0。
///
/// 只吃文件内容、不看路径：会话文件名（session-<ISO 截到分钟>-<id 前 8 位>.jsonl）、子 agent 的
/// chats/<parentId>/ 一层与桶名（项目 slug）都归发现层。
public enum GeminiSessionParser {
    public static let source: TokenSourceID = .gemini
    /// Gemini 只跑 Google 系模型，记录不带 provider 字段
    public static let providerName = "google"
    public static let unknownModel = "unknown"

    // MARK: - 入口

    /// 纯函数入口：整段文本（整份 JSON 或 JSONL）
    public static func parse(text: String) -> TokenSourceParseReport {
        parse(data: Data(text.utf8))
    }

    public static func parse(data: Data) -> TokenSourceParseReport {
        var state = State()
        if let root = try? JSONSerialization.jsonObject(with: data) {
            state.consume(root)
        } else {
            state.consumeLines(data)
        }
        return state.report()
    }

    /// IO 入口：读文件（失败返回 nil → 调用方按可用性上报，不伪装成 0 用量）
    public static func parse(contentsOf url: URL) -> TokenSourceParseReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    // MARK: - 累计状态

    /// 一条消息的记账草稿（模型 / 会话键 / 项目根取落盘当时的快照，后一条换模型不追溯改写）
    struct Draft: Equatable {
        var tsMs: Int64
        var usage: HarnessTokenUsage
        var model: String
        var sessionKey: String
        var cwd: String
    }

    /// 解析过程中的累计状态（纯值类型：整份 JSON 与逐行两条路径共用同一套记账）
    struct State {
        /// 消息键 → 草稿；同一键再出现时覆盖（后者胜）
        var drafts: [String: Draft] = [:]
        /// 消息键的写入顺序（$patch.orderIds 重排、$rewindTo 截断）
        var order: [String] = []
        /// 出现过的消息键（清空不删）：只用于 skipped 计数，口径是「多余的那份不再计请求数」
        var seen: Set<String> = []
        /// 当前会话键（sessionId）
        var sessionKey = ""
        /// 当前项目根（.project_root）
        var cwd = ""
        /// 当前模型（消息记录带 model 时更新）
        var model = ""
        var malformed = 0
        var ignored = 0
        var skipped = 0

        /// 吞一条已解析的 JSON 值（对象 = 一条记录；数组 = 一批消息）
        mutating func consume(_ any: Any) {
            if let record = TokenSourceJSON.object(any) {
                consumeRecord(record)
            } else if let array = any as? [Any] {
                consumeMessages(array)
            } else {
                malformed += 1
            }
        }

        /// 吞一条记录：截断 / 补丁 / 元信息写 / 容器 messages / 单条消息
        mutating func consumeRecord(_ record: [String: Any]) {
            applyMetadata(record)
            // 1. 截断：$rewindTo 指向的消息及其后全部作废
            if let rewind = TokenSourceJSON.string(record["$rewindTo"]) {
                applyRewind(to: rewind)
                return
            }
            // 2. 补丁：只改已有消息（tokens 不经此下发，但 removeIds / orderIds 影响口径）
            if let patch = TokenSourceJSON.object(record["$patch"]) {
                applyPatch(patch)
                return
            }
            // 3. 元信息写 $set（messages 已 deprecated）；没有 messages 的只是一次元信息合并
            if let set = TokenSourceJSON.object(record["$set"]) {
                applyMetadata(set)
                guard set["messages"] != nil else {
                    ignored += 1
                    return
                }
                consumeMessages(set["messages"])
                return
            }
            if let messages = record["messages"] {
                consumeMessages(messages)
                return
            }
            consumeMessage(record)
        }

        /// 逐行路径：一行一份 JSON（新版 JSONL）
        mutating func consumeLines(_ data: Data) {
            for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
                var line = rawLine
                if line.last == 0x0D { line = line.dropLast() }
                // 空行 / 纯空白不算坏行（与 Claude / Codex 同一口径）
                if TokenSourceJSON.isBlank(Data(line)) { continue }
                guard let record = TokenSourceJSON.object(from: Data(line)) else {
                    malformed += 1
                    continue
                }
                consumeRecord(record)
            }
        }

        /// 元信息：会话键 / 项目根 / 模型（消息记录上也带 model，随后生效）
        mutating func applyMetadata(_ record: [String: Any]) {
            if let id = TokenSourceJSON.string(record["sessionId"]) { sessionKey = id }
            if let root = TokenSourceJSON.string(record[".project_root"]) { cwd = root }
            if let name = TokenSourceJSON.string(record["model"]) { model = name }
        }

        /// 一批消息（messages / $set.messages 的元素）
        mutating func consumeMessages(_ any: Any?) {
            guard let any else { return }
            guard let list = any as? [Any] else {
                malformed += 1
                return
            }
            for element in list {
                guard let record = TokenSourceJSON.object(element) else {
                    malformed += 1
                    continue
                }
                consumeMessage(record)
            }
        }

        /// 单条消息：没有 tokens 或为 null 的（user / info / error）与统计无关
        mutating func consumeMessage(_ record: [String: Any]) {
            guard let rawTokens = record["tokens"], !(rawTokens is NSNull) else {
                ignored += 1
                return
            }
            guard let tokens = TokenSourceJSON.object(rawTokens) else {
                malformed += 1
                return
            }
            guard let tsMs = TokenSourceJSON.milliseconds(fromISO8601: record["timestamp"] as? String) else {
                malformed += 1
                return
            }
            if let name = TokenSourceJSON.string(record["model"]) { model = name }
            let usage = GeminiSessionParser.usage(from: tokens)
            guard !usage.isZero else {
                skipped += 1
                return
            }
            let key = messageKey(record: record, tsMs: tsMs, usage: usage)
            // 同一 id 再 append（usage 回填 / 重放）：后者胜，但只算一次请求数
            if !seen.insert(key).inserted { skipped += 1 }
            if drafts[key] == nil { order.append(key) }
            drafts[key] = Draft(
                tsMs: tsMs,
                usage: usage,
                model: model.isEmpty ? GeminiSessionParser.unknownModel : model,
                sessionKey: sessionKey,
                cwd: cwd
            )
        }

        /// 消息键：id 优先（$rewindTo / $patch 用它寻址）；缺失时退化为 (sessionKey, 时间戳, 四桶)
        func messageKey(record: [String: Any], tsMs: Int64, usage: HarnessTokenUsage) -> String {
            if let id = TokenSourceJSON.string(record["id"]) { return id }
            return [
                "#fallback", sessionKey, String(tsMs),
                String(usage.uncachedInput), String(usage.output), String(usage.cacheRead),
            ].joined(separator: "|")
        }

        /// $rewindTo：截掉该 id 及其后全部记录（上游 accumulator 同构：找不到就整份清空）
        mutating func applyRewind(to id: String) {
            let removed: [String]
            if let index = order.firstIndex(of: id) {
                removed = Array(order[index...])
                order.removeSubrange(index...)
            } else {
                removed = order
                order.removeAll()
            }
            guard !removed.isEmpty else { return }
            for key in removed where drafts.removeValue(forKey: key) != nil {
                skipped += 1
            }
        }

        /// $patch：单条补丁 / 批量 updates / removeIds / orderIds
        mutating func applyPatch(_ patch: [String: Any]) {
            var changed = applySinglePatch(patch)
            if let updates = patch["updates"] as? [Any] {
                for element in updates {
                    guard let update = TokenSourceJSON.object(element) else {
                        malformed += 1
                        continue
                    }
                    changed = applySinglePatch(update) || changed
                }
            }
            if let removeIds = patch["removeIds"] as? [Any] {
                for element in removeIds {
                    guard let id = TokenSourceJSON.string(element) else { continue }
                    changed = remove(key: id) || changed
                }
            }
            if let orderIds = patch["orderIds"] as? [Any], reorder(orderIds) { changed = true }
            // 与旧口径一致：没有任何用量影响的记录行归 ignored（补丁行绝大多数属于此类）
            if !changed { ignored += 1 }
        }

        /// 单条补丁：只更新已有消息（上游 MessagePatch 只带 content / toolCalls，故正常无改动；
        /// 仍宽松读 tokens / timestamp / model，兼容自行扩展的记录）
        mutating func applySinglePatch(_ patch: [String: Any]) -> Bool {
            guard let id = TokenSourceJSON.string(patch["id"]), var draft = drafts[id] else {
                return false
            }
            var changed = false
            if let tokens = TokenSourceJSON.object(patch["tokens"]) {
                let usage = GeminiSessionParser.usage(from: tokens)
                if !usage.isZero, usage != draft.usage {
                    draft.usage = usage
                    changed = true
                }
            }
            if let tsMs = TokenSourceJSON.milliseconds(fromISO8601: patch["timestamp"] as? String),
               tsMs != draft.tsMs {
                draft.tsMs = tsMs
                changed = true
            }
            if let name = TokenSourceJSON.string(patch["model"]), name != draft.model {
                draft.model = name
                changed = true
            }
            if changed { drafts[id] = draft }
            return changed
        }

        /// 删除一条已记消息（$patch.removeIds）
        mutating func remove(key: String) -> Bool {
            guard drafts.removeValue(forKey: key) != nil else { return false }
            order.removeAll { $0 == key }
            skipped += 1
            return true
        }

        /// 重排（$patch.orderIds）：列出的按给定顺序排在未列出者之后（同上游）
        mutating func reorder(_ list: [Any]) -> Bool {
            let ordered = list
                .compactMap { TokenSourceJSON.string($0) }
                .filter { drafts[$0] != nil }
            guard !ordered.isEmpty else { return false }
            let orderedSet = Set(ordered)
            let next = order.filter { !orderedSet.contains($0) } + ordered
            guard next != order else { return false }
            order = next
            return true
        }

        /// 汇总报告（按最终顺序输出；元信息缺省 nil，由扫描器补齐）
        func report() -> TokenSourceParseReport {
            var events: [TokenSourceUsageEvent] = []
            events.reserveCapacity(order.count)
            for key in order {
                guard let draft = drafts[key] else { continue }
                events.append(TokenSourceUsageEvent(
                    source: GeminiSessionParser.source,
                    tsMs: draft.tsMs,
                    provider: GeminiSessionParser.providerName,
                    model: draft.model,
                    usage: draft.usage,
                    sessionKey: draft.sessionKey,
                    cwd: draft.cwd
                ))
            }
            let hasSession = !sessionKey.isEmpty || !cwd.isEmpty || !model.isEmpty
            return TokenSourceParseReport(
                source: GeminiSessionParser.source,
                events: events,
                session: hasSession
                    ? TokenSourceSessionInfo(
                        source: GeminiSessionParser.source,
                        sessionKey: sessionKey,
                        cwd: cwd,
                        model: model.isEmpty ? GeminiSessionParser.unknownModel : model
                    )
                    : nil,
                ignoredLineCount: ignored,
                malformedLineCount: malformed,
                skippedLineCount: skipped
            )
        }
    }

    // MARK: - 四桶映射

    /// 四桶映射（规格 §2.7）：uncachedInput = input - cached（tool 计入输入）、
    /// output = output + thoughts、cacheWrite = 0。上游 total = prompt + candidates + tool + thoughts。
    static func usage(from tokens: [String: Any]) -> HarnessTokenUsage {
        let input = number(tokens, ["promptTokenCount", "input"])
        let cached = number(tokens, ["cachedContentTokenCount", "cached"])
        let output = number(tokens, ["candidatesTokenCount", "output"])
        /// thoughts 单列，必须加进 output（Gemini 的 reasoning 不计入 candidates）
        let thoughts = number(tokens, ["thoughtsTokenCount", "thoughts"])
        /// tool 用量不计入 promptTokenCount，单独并入输入
        let tool = number(tokens, ["toolUsePromptTokenCount", "tool"])
        return HarnessTokenUsage(
            uncachedInput: max(0, input - cached) + tool,
            output: output + thoughts,
            cacheRead: cached,
            cacheWrite: 0,
            requestCount: 1
        )
    }

    /// 两种命名都出现过（API 名 / 归一化名），都读、前者优先
    static func number(_ tokens: [String: Any], _ keys: [String]) -> Int {
        for key in keys {
            if let value = TokenSourceJSON.int(tokens[key]) { return TokenSourceJSON.nonNegative(value) }
        }
        return 0
    }
}

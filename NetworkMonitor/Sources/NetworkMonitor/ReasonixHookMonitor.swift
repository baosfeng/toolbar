import Darwin
import Foundation
import NetworkMonitorCore

/// Reasonix Hook 事件监听器
///
/// 通过 Unix Domain Socket (UDS) Datagram 模式接收 Reasonix AI 助手推送的事件，
/// 解析为结构化的事件数据并写入本地 SQLite 数据库。
///
/// ## 通信方式
/// - 协议: AF_UNIX + SOCK_DGRAM
/// - 地址: /tmp/reasonix-hook.sock
/// - 格式: UTF-8 JSON
///
/// ## 线程安全
/// - `start()` / `stop()` 可在任意线程调用
/// - 实际的 recvfrom 循环在私有 DispatchQueue 上运行
/// - 数据库写入委托给 DatabaseManager（内部已串行化）
final class ReasonixHookMonitor {

    // MARK: - 常量

    /// UDS socket 文件路径（固定）
    private static let sockPath = "/tmp/reasonix-hook.sock"
    /// UDS Datagram 单条数据上限
    private static let maxDatagramSize = 65535
    /// 内部队列标签（事件处理）
    private static let queueLabel = "com.example.NetworkMonitor.reasonix-hook"

    // MARK: - 属性

    private let database: DatabaseManager
    private var socketFd: Int32 = -1
    private var readSource: DispatchSourceRead?
    /// 事件处理队列 — DispatchSourceRead 在此队列上派发事件
    private let eventQueue = DispatchQueue(label: queueLabel, qos: .background)
    /// 健康检查计时器，socket 文件丢失时自动重建
    private var healthTimer: DispatchSourceTimer?
    /// 会话侧车缓存 — TTL 1 小时，最多 100 个会话，LRU 淘汰
    private let sidecarCache = SessionSidecarCache(maxCount: 100, ttl: 3600)

    // MARK: - 初始化

    init(database: DatabaseManager) {
        self.database = database
    }

    deinit {
        stop()
    }

    // MARK: - 公共方法

    /// 启动 UDS 监听器
    func start() {
        guard readSource == nil else {
            print("⚠️ ReasonixHookMonitor 已在运行中")
            return
        }

        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            print("❌ ReasonixHookMonitor socket 创建失败: \(String(cString: strerror(errno)))")
            return
        }
        socketFd = fd

        // 增大接收缓冲区，防止高并发丢包
        var rcvbufSize: Int32 = 256 * 1024  // 256KB
        _ = withUnsafeMutablePointer(to: &rcvbufSize) { ptr in
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, ptr, socklen_t(MemoryLayout<Int32>.size))
        }

        // 清理可能残留的 socket 文件
        Self.cleanupSocket()

        // 构建 sockaddr_un
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Self.sockPath.utf8
        let pathLen = pathBytes.count
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path) - 1

        guard pathLen <= maxPath else {
            print("❌ ReasonixHookMonitor socket 路径过长")
            stop()
            return
        }

        // 复制路径到 sun_path
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            var offset = 0
            for byte in pathBytes {
                ptr.advanced(by: offset).pointee = Int8(byte)
                offset += 1
            }
            ptr.advanced(by: offset).pointee = 0 // null-terminated
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, addrLen)
            }
        }

        guard bindResult == 0 else {
            print("❌ ReasonixHookMonitor bind 失败: \(String(cString: strerror(errno)))")
            stop()
            return
        }

        print("✅ ReasonixHookMonitor 已绑定到 \(Self.sockPath)")

        // 使用 DispatchSourceRead 监听 socket 可读事件
        // 事件处理器在 eventQueue 上运行，不会阻塞
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: eventQueue)
        readSource = source

        source.setEventHandler { [weak self] in
            // Drain: 循环读取直到 EAGAIN，防止多个数据包堆积
            while true {
                var buffer = [UInt8](repeating: 0, count: Self.maxDatagramSize)
                var addrStorage = sockaddr_storage()
                var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)

                let received = withUnsafeMutablePointer(to: &addrStorage) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        recvfrom(fd, &buffer, buffer.count, MSG_DONTWAIT, sockaddrPtr, &addrLen)
                    }
                }

                guard received > 0 else {
                    break  // EAGAIN 或错误，退出 drain 循环
                }

                let data = Data(bytes: buffer, count: received)
                self?.handleReceivedData(data)
            }
        }

        source.setCancelHandler {
            close(fd)
            print("📡 ReasonixHookMonitor socket 已关闭")
        }

        source.resume()

        print("📡 ReasonixHookMonitor 已启动 — 监听 \(Self.sockPath)")

        startHealthCheck()
    }

    /// 停止 UDS 监听器
    func stop() {
        healthTimer?.cancel()
        healthTimer = nil

        readSource?.cancel()
        readSource = nil

        if socketFd >= 0 {
            close(socketFd)
            socketFd = -1
        }
    }

    // MARK: - Socket 健康检查

    /// 启动 socket 文件健康检查（每 30 秒检测一次，丢失则重建）
    private func startHealthCheck() {
        let timer = DispatchSource.makeTimerSource(queue: eventQueue)
        healthTimer = timer
        timer.schedule(deadline: .now() + 30, repeating: .seconds(30), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let sockPath = Self.sockPath
            if !FileManager.default.fileExists(atPath: sockPath) {
                print("⚠️ socket 文件丢失，正在重建...")
                // stop() 会清理 FD；start() 内部调用 cleanupSocket() + bind
                self.stop()
                self.start()
            }
        }
        timer.resume()
    }

    /// 清理 socket 文件（类方法，可在应用退出时调用）
    static func cleanupSocket() {
        _ = sockPath.withCString { cPath in
            unlink(cPath)
        }
    }

    // MARK: - 数据处理

    /// 加载指定事件的侧车数据（缓存优先，mtime 校验自动刷新）
    private func loadSidecar(for event: ReasonixHookEvent) -> SessionSidecarData {
        let sid = event.sessionId
        if let cached = sidecarCache.get(sid) {
            return cached.data
        }
        guard !sid.isEmpty, !event.cwd.isEmpty else {
            return SessionSidecarData()
        }

        let slug = event.cwd.replacingOccurrences(of: "/", with: "-")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = "\(home)/.reasonix/projects/\(slug)/sessions/\(sid)"
        let metaPath = base + ".jsonl.meta"
        let telePath = base + ".jsonl.telemetry.json"

        // 检查 mtime 是否匹配缓存
        if let cached = sidecarCache.peek(sid),
           let metaMtime = fileModTime(metaPath),
           let teleMtime = fileModTime(telePath),
           metaMtime == cached.metaMtime,
           teleMtime == cached.teleMtime {
            // mtime 未变，延长缓存有效期但不重读文件
            sidecarCache.touch(sid)
            return cached.data
        }

        // 读取 meta 文件
        var model = "", topic = ""
        var turns = 0
        if let metaData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
           let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
            model = (meta["model"] as? String) ?? ""
            topic = (meta["topic_title"] as? String) ?? ""
            turns = (meta["turns"] as? Int) ?? 0
        }

        // 读取 telemetry
        var promptTokens = 0, completionTokens = 0, totalTokens = 0
        var reasoningTokens = 0, cost = 0.0
        if let teleData = try? Data(contentsOf: URL(fileURLWithPath: telePath)),
           let tele = try? JSONSerialization.jsonObject(with: teleData) as? [String: Any],
           let u = tele["usage"] as? [String: Any] {
            promptTokens = (u["promptTokens"] as? Int) ?? (u["prompt_tokens"] as? Int) ?? 0
            completionTokens = (u["completionTokens"] as? Int) ?? (u["completion_tokens"] as? Int) ?? 0
            totalTokens = (u["totalTokens"] as? Int) ?? (u["total_tokens"] as? Int) ?? 0
            reasoningTokens = (u["reasoningTokens"] as? Int) ?? (u["reasoning_tokens"] as? Int) ?? 0
            cost = (u["sessionCost"] as? Double) ?? (u["cost"] as? Double) ?? 0.0
        }

        let data = SessionSidecarData(
            model: model,
            topic: topic,
            turns: turns,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cost: cost
        )
        sidecarCache.set(sid, data, metaMtime: fileModTime(metaPath) ?? 0,
                         teleMtime: fileModTime(telePath) ?? 0)
        print("📖 加载侧车数据: \(sid.prefix(30))... turns=\(turns) tokens=\(totalTokens)")
        return data
    }

    /// 获取文件修改时间戳（秒级）
    private func fileModTime(_ path: String) -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    /// 生成 ISO8601 时间戳（事件自带为空时使用当前时间）
    private func resolveTimestamp(_ ts: String) -> String {
        if !ts.isEmpty { return ts }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date())
    }

    /// 处理接收到的原始数据
    /// - Parameter data: UTF-8 JSON 数据
    private func handleReceivedData(_ data: Data) {
        do {
            var event = try ReasonixHookEvent.from(jsonData: data)
            // 补全缺失的时间戳
            event.timestamp = resolveTimestamp(event.timestamp)
            print("🔌 [\(event.eventTypeCN)] \(event.sessionId.prefix(30))... 轮次:\(event.turns)")

            // 补全侧车数据（缓存命中则不读磁盘）
            let sidecar = loadSidecar(for: event)
            event.enrich(from: sidecar)

            // 1. 写入事件流水
            database.writeHookEvent(event: event)

            // 2. 更新会话汇总
            if event.isSessionStart || event.isSessionEnd || event.isStop || event.isStopFailure {
                database.upsertHookSession(event: event)
            }

            // 2b. 轮次完成/失败时弹通知
            if event.isStop || event.isStopFailure {
                sendSessionEndNotification(event: event)
            }

            // 3. 处理工具调用
            if event.isToolStart {
                let toolName = event.toolName ?? "unknown"
                var argsJSON: String? = nil
                if let args = event.toolArgs,
                   let jsonData = try? JSONSerialization.data(withJSONObject: args, options: .sortedKeys) {
                    argsJSON = String(data: jsonData, encoding: .utf8)
                }
                database.startHookToolCall(
                    sessionId: event.sessionId,
                    turn: event.turns,
                    toolName: toolName,
                    toolArgsJSON: argsJSON,
                    timestamp: event.timestamp
                )
                print("🔧 工具调用开始: \(toolName)")
            }

            if event.isToolEnd {
                let toolName = event.toolName ?? "unknown"
                let isSuccess = event.eventType == .postToolUse
                let status = isSuccess ? "success" : "failure"
                let resultPreview = isSuccess ? event.resultPreview : nil
                let errorStr = isSuccess ? nil : event.errorInfo

                database.finishHookToolCall(
                    sessionId: event.sessionId,
                    turn: event.turns,
                    toolName: toolName,
                    status: status,
                    resultPreview: resultPreview,
                    error: errorStr,
                    timestamp: event.timestamp
                )
                print("🔧 工具调用结束: \(toolName) [\(status)]")
            }

        } catch let error as ReasonixHookError {
            print("⚠️ Hook 数据解析失败: \(error.localizedDescription)")
            if let rawStr = String(data: data, encoding: .utf8) {
                print("  原始数据: \(rawStr.prefix(300))")
            }
        } catch {
            print("⚠️ Hook 数据处理异常: \(error.localizedDescription)")
        }
    }

    // MARK: - 会话结束通知

    /// 会话结束时弹出系统通知
    private func sendSessionEndNotification(event: ReasonixHookEvent) {
        let project = event.project.isEmpty ? "默认项目" : event.project
        let sid = event.sessionId
        let tokensStr = "Token: \(Self.formatTokenCount(event.totalTokens))"
        let costStr = String(format: "花费: $%.4f", event.cost)
        let isFailure = event.isStopFailure
        let statusStr = isFailure ? "❌ 失败" : "✅ 完成"

        // 清理过期通知（超过 5 分钟）和超量通知（最多 5 条）
        cleanupNotifications()

        let notification = NSUserNotification()
        notification.title = "\(project) — 轮次 \(statusStr)"
        notification.informativeText = "\(sid.prefix(16))...  \(tokensStr)  \(costStr)"
        notification.soundName = NSUserNotificationDefaultSoundName

        // 保存会话文件路径到 userInfo，点击时用来跳转
        let slug = event.cwd.replacingOccurrences(of: "/", with: "-")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionFile = "\(home)/.reasonix/projects/\(slug)/sessions/\(sid).jsonl"
        notification.userInfo = [
            "sessionFile": sessionFile,
            "sentAt": Date().timeIntervalSince1970
        ]

        NSUserNotificationCenter.default.deliver(notification)
    }

    /// 清理过期和超量的通知
    private func cleanupNotifications() {
        let center = NSUserNotificationCenter.default
        let now = Date().timeIntervalSince1970
        let maxAge: TimeInterval = 300  // 5 分钟
        let maxCount = 5

        var remaining: [NSUserNotification] = []
        for note in center.deliveredNotifications {
            guard let info = note.userInfo,
                  let sentAt = info["sentAt"] as? TimeInterval else {
                center.removeDeliveredNotification(note)
                continue
            }
            // 超过 5 分钟的移除
            if now - sentAt > maxAge {
                center.removeDeliveredNotification(note)
                continue
            }
            remaining.append(note)
        }

        // 超过 5 条的移除最旧的
        if remaining.count >= maxCount {
            // 按发送时间排序，移除最旧的
            remaining.sort { a, b in
                let aTime = a.userInfo?["sentAt"] as? TimeInterval ?? 0
                let bTime = b.userInfo?["sentAt"] as? TimeInterval ?? 0
                return aTime < bTime
            }
            let toRemove = remaining.prefix(remaining.count - maxCount + 1)
            for note in toRemove {
                center.removeDeliveredNotification(note)
            }
        }
    }

    /// 格式化 Token 数（简短显示）
    private static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

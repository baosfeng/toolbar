import Foundation

// MARK: - 传输服务

/// 传输服务 — 会话编排、收件目录、配对记忆、路由实现（组合根注入的唯一样例）
///
/// 分层职责（设计文档 §2）：Service 不解析 HTTP（由 Protocol / Transport 完成），
/// 只决定「谁授权、存哪里、状态怎么走」。actor 保证会话表在并发请求下的一致。
public actor TransferService: TransferRouteHandling {

    // MARK: - 配置

    /// 服务配置
    public struct Configuration: Sendable {
        /// 收件目录（默认 `~/Downloads/局域网互传/`）
        public var receiveDirectory: URL
        /// 应用版本（`/info` 与发现公告使用）
        public var appVersion: String
        /// 确认超时（秒）
        public var confirmTimeout: TimeInterval
        /// 收件文件名冲突时的目录探测共用同一目录
        public var downloadDirectory: URL

        public init(receiveDirectory: URL, appVersion: String,
                    confirmTimeout: TimeInterval = TransferProtocol.confirmTimeout) {
            self.receiveDirectory = receiveDirectory
            self.appVersion = appVersion
            self.confirmTimeout = confirmTimeout
            self.downloadDirectory = receiveDirectory
        }

        /// 默认收件目录
        public static func defaultReceiveDirectory() -> URL {
            let downloads = FileManager.default.urls(for: .downloadsDirectory,
                                                     in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return downloads.appendingPathComponent("局域网互传", isDirectory: true)
        }
    }

    // MARK: - 内部上下文

    /// 接收端单个文件的落盘信息（文件名在 accept 阶段一次确定）
    struct ReceiveFileContext {
        var finalURL: URL
        var finalName: String
        var writer: FileStreamWriter?
    }

    /// 会话上下文：会话本体 + 传输所需的对端与落盘信息
    struct SessionContext {
        var session: TransferSession
        var peerIP: String
        var peerPort: Int
        /// 未配对时展示给用户的 PIN
        var pin: String?
        var pinExpiresAt: Date?
        /// 接收端的最终答复（pending 用 nil 表示）
        var decision: OfferDecision?
        var receiveFiles: [String: ReceiveFileContext]
        /// 发送端：fileId → 本地源文件
        var sourceFiles: [String: URL]
        /// 发送端：对端设备
        var peerDeviceId: String
        /// 对端别名（来源为 offer 的 senderAlias，用于接收弹窗直接展示，不依赖发现层）
        var peerAlias: String
    }

    /// 接收端对 `offer` 的最终答复
    enum OfferDecision: String, Sendable {
        case approved
        case denied
        case expired
    }

    /// 等待用户确认的接收会话（面板展示 PIN 用）
    public struct PendingOffer: Sendable, Equatable {
        public var sessionId: String
        public var peerDeviceId: String
        public var pin: String
        public var expiresAt: Date
        /// 发送方别名（offer.senderAlias 透传，缺失时由 UI 回落「未知设备」）
        public var senderAlias: String
    }

    // MARK: - 依赖

    // 说明：以下成员放宽为 internal，供 `TransferService+Receive/Send` 扩展文件使用
    let registry: DeviceRegistry
    let pairing: PairingStore
    let preferences: TransferPreferences
    /// 已知设备地址记忆（冷启动快速探测）
    let knownPeers: KnownPeerStore?
    let logger: LoggingService
    let configuration: Configuration
    /// 扫码接收 token（纯逻辑，时钟/随机源可注入）
    let scanTokens: ScanTokenStore
    private let server: HttpServer
    let httpClient: TransferHTTPClient
    private let observerQueue: DispatchQueue
    private var discovery: UdpDiscoveryService?

    /// 本机身份（HTTP 端口在服务启动后回填）
    public private(set) var localIdentity: LocalIdentity

    // MARK: - 状态

    var contexts: [String: SessionContext] = [:]
    /// 发送进度通知节流时间戳（扩展文件使用）
    var lastSendProgressNotify: Date = .distantPast
    // 放宽为 internal：观察者订阅方法在 `TransferService+Observer` 扩展中
    var onSessionsChanged: (@Sendable ([TransferSession]) -> Void)?
    var onSessionFinished: (@Sendable (TransferSession) -> Void)?
    private var started = false

    // MARK: - 初始化

    public init(identity: LocalIdentity,
                registry: DeviceRegistry,
                configuration: Configuration,
                pairing: PairingStore = PairingStore(),
                preferences: TransferPreferences = TransferPreferences(),
                knownPeers: KnownPeerStore? = nil,
                scanTokens: ScanTokenStore = ScanTokenStore(),
                logger: LoggingService = AppContext.shared.logger,
                observerQueue: DispatchQueue = .main) {
        self.localIdentity = identity
        self.registry = registry
        self.configuration = configuration
        self.pairing = pairing
        self.preferences = preferences
        self.knownPeers = knownPeers
        self.scanTokens = scanTokens
        self.logger = logger
        self.observerQueue = observerQueue
        self.server = HttpServer(logger: logger)
        self.httpClient = TransferHTTPClient(logger: logger)
        try? FileManager.default.createDirectory(at: configuration.receiveDirectory,
                                                 withIntermediateDirectories: true)
    }

    // MARK: - 生命周期

    /// 启动 HTTP 服务与 UDP 发现，返回实际监听端口
    @discardableResult
    public func start(portCandidates: [UInt16] = TransferProtocol.defaultPorts,
                      startDiscovery: Bool = true) async throws -> UInt16 {
        if started, localIdentity.port > 0 { return UInt16(localIdentity.port) }

        let router = TransferRouter(handler: self, scanHandler: self)
        let port = try await server.start(portCandidates: portCandidates) { request, body in
            await router.route(request, body: body)
        }
        localIdentity.port = Int(port)
        started = true

        if startDiscovery {
            let discovery = UdpDiscoveryService(identity: localIdentity, registry: registry,
                                                knownPeers: knownPeers, logger: logger)
            self.discovery = discovery
            discovery.start()
        }

        // 已配对设备在设备表里同步标记，UI 直接可读
        for deviceId in pairing.pairedDeviceIds() {
            registry.setPaired(true, deviceId: deviceId)
        }
        logger.info("传输服务已启动：HTTP \(port)，收件目录 \(configuration.receiveDirectory.path)")
        notifySessions()
        return port
    }

    /// 停止服务（HTTP + UDP）
    public func stop() {
        discovery?.stop()
        discovery = nil
        server.stop()
        scanTokens.revokeAll()
        started = false
        logger.info("传输服务已停止")
    }

    /// 手动刷新发现（面板「刷新」入口）
    public func refreshDiscovery() {
        discovery?.refreshDiscovery()
    }

    /// 立即公告一次
    public func announceNow() {
        discovery?.announceNow()
    }

    /// 是否已启动
    public var isRunning: Bool { started }

    /// 实际 HTTP 端口
    public var listenPort: Int { localIdentity.port }

    // MARK: - 路由：/info

    public func deviceInfo() async -> DeviceInfo {
        DeviceInfo(identity: localIdentity)
    }

    // MARK: - 路由：/offer

    public func handleOffer(_ request: OfferRequest,
                            pairKey: String?) async -> Result<OfferHandlingResult, TransferError> {
        let now = Date()
        let totalSize = request.files.reduce(Int64(0)) { $0 + $1.size }
        do {
            try DiskSpaceProbe.require(bytes: totalSize, at: configuration.receiveDirectory)
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("磁盘空间预检失败"))
        }

        // 重提 PIN / 断网重试：优先按 sessionId 复用未终结的接收会话；
        // 未带 sessionId 时按 senderDeviceId + sha256 集合复用待确认会话
        if let requestSessionId = request.sessionId,
           let existing = contexts[requestSessionId],
           existing.session.direction == .recv,
           !existing.session.state.isTerminal {
            return handleRepeatedOffer(existing, request: request, now: now)
        }
        let signature = Self.offerSignature(request)
        if let existing = pendingContext(signature: signature, sender: request.senderDeviceId, now: now) {
            return handleRepeatedOffer(existing, request: request, now: now)
        }

        // 接收端本地策略（设计文档 §3.6）：已配对 / 免配对窗口 / 体积阈值，任一满足即免确认
        let paired = isPairingKeyValid(pairKey, deviceId: request.senderDeviceId)
        let decision = AcceptancePolicy.decide(paired: paired,
                                               windowActive: preferences.isWindowActive(now: now),
                                               sizeThresholdMB: preferences.sizeThresholdMB,
                                               totalBytes: totalSize)
        let context = makeOfferContext(request: request, approved: decision.accepted, now: now)
        contexts[context.session.id] = context

        if decision.accepted {
            logger.info("offer 免确认放行（\(decision.reason.rawValue)）：\(request.senderDeviceId)")
        } else if let pin = context.pin, let expiry = context.pinExpiresAt {
            logger.info("收到未配对 offer（\(request.senderDeviceId)），PIN \(pin) 有效期至 \(expiry)")
        }
        notifySessions()

        let accepted = decision.accepted ? acceptedOffsets(context) : []
        let result = OfferResult(sessionId: context.session.id,
                                 token: context.session.token,
                                 state: decision.accepted ? .approved : .pending,
                                 accepted: accepted)
        return .success(OfferHandlingResult(result: result))
    }

    // MARK: - 路由：/offer/status

    public func offerStatus(sessionId: String) async -> Result<OfferStatusResult, TransferError> {
        guard var context = contexts[sessionId] else { return .failure(.sessionNotFound) }

        // 确认超时：pending 超过 30s 直接过期
        if context.decision == nil, context.session.state == .awaitingConfirm,
           let expiry = context.pinExpiresAt, Date() >= expiry {
            context.decision = .expired
            context.session.state = .failed
            contexts[sessionId] = context
            logger.warning("会话 \(sessionId) 确认超时（\(Int(configuration.confirmTimeout))s）")
            notifySessions()
            return .success(OfferStatusResult(state: .expired))
        }

        switch context.decision {
        case .denied:
            return .success(OfferStatusResult(state: .denied))
        case .expired:
            return .success(OfferStatusResult(state: .expired))
        case .approved:
            return .success(OfferStatusResult(state: .approved))
        case nil:
            // 已配对直通 transferring 的会话也算 approved
            let state: OfferState = context.session.state == .awaitingConfirm ? .pending : .approved
            return .success(OfferStatusResult(state: state))
        }
    }

    // MARK: - 路由：/cancel

    public func cancel(sessionId: String, token: String?) async -> Result<EmptyPayload, TransferError> {
        guard var context = contexts[sessionId] else { return .failure(.sessionNotFound) }
        if let token, !token.isEmpty, token != context.session.token {
            return .failure(.tokenMismatch)
        }
        cleanupParts(&context)
        context.session.state = .cancelled
        contexts[sessionId] = context
        logger.info("会话 \(sessionId) 已取消")
        notifySessions()
        finishIfNeeded(context.session)
        return .success(EmptyPayload())
    }

    /// 本地取消（发送端 UI 主动中止时的入口）
    public func cancelLocal(sessionId: String) async {
        guard var context = contexts[sessionId] else { return }
        cleanupParts(&context)
        context.session.state = .cancelled
        contexts[sessionId] = context
        notifySessions()
        finishIfNeeded(context.session)
    }

    /// 用户拒绝接收（UI「拒绝」按钮）
    public func denyOffer(sessionId: String) {
        guard var context = contexts[sessionId] else { return }
        context.decision = .denied
        context.session.state = .failed
        contexts[sessionId] = context
        cleanupParts(&context)
        logger.info("用户拒绝会话 \(sessionId)")
        notifySessions()
        finishIfNeeded(context.session)
    }

    /// 用户确认接收（UI 上直接同意，无需 PIN）
    public func approveOffer(sessionId: String) {
        guard var context = contexts[sessionId],
              context.session.state == .awaitingConfirm else { return }
        context.decision = .approved
        context.pin = nil
        context.pinExpiresAt = nil
        context.session.state = .transferring
        contexts[sessionId] = context
        notifySessions()
    }

    /// 当前处于等待确认的会话（UI 展示 PIN 用）
    public func pendingOffers() -> [PendingOffer] {
        contexts.values
            .filter { $0.session.direction == .recv && $0.session.state == .awaitingConfirm && $0.decision == nil }
            .sorted { $0.session.createdAt > $1.session.createdAt }
            .compactMap { context in
                guard let pin = context.pin, let expiry = context.pinExpiresAt else { return nil }
                return PendingOffer(sessionId: context.session.id,
                                    peerDeviceId: context.session.peerDeviceId,
                                    pin: pin,
                                    expiresAt: expiry,
                                    senderAlias: context.peerAlias)
            }
    }

    // MARK: - 辅助

    /// 删除会话相关的所有 `.part`
    func cleanupParts(_ context: inout SessionContext) {
        for (_, receive) in context.receiveFiles {
            receive.writer?.discard()
            try? FileManager.default.removeItem(at: UploadPlanner.partURL(for: receive.finalURL))
        }
        context.receiveFiles = context.receiveFiles.mapValues { value in
            var updated = value
            updated.writer = nil
            return updated
        }
    }

    /// 会话进入终结态时触发一次完成回调
    func finishIfNeeded(_ session: TransferSession) {
        guard session.state.isTerminal, let onSessionFinished else { return }
        observerQueue.async { onSessionFinished(session) }
    }

    /// 推送会话快照到观察者
    func notifySessions() {
        guard let onSessionsChanged else { return }
        let snapshot = sessionSnapshot()
        observerQueue.async { onSessionsChanged(snapshot) }
    }
}

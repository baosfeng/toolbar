import Foundation

// MARK: - offer 处理（PIN / 配对 / 会话构造）

/// 说明：与主文件同属 `TransferService`，这里放接收端的 offer 分支与会话构造，
/// 成员可见性放宽为 internal 以便跨文件调用。
extension TransferService {

    func handleRepeatedOffer(_ context: SessionContext, request: OfferRequest,
                                     now: Date) -> Result<OfferHandlingResult, TransferError> {
        var context = context
        // 已批准 / 传输中：断网重试按服务端已收字节续传（协议 §6），不再走 PIN 流程
        if context.decision == .approved || context.session.state == .transferring {
            let resumed = OfferResult(sessionId: context.session.id,
                                      token: context.session.token,
                                      state: .approved,
                                      accepted: acceptedOffsets(context))
            return .success(OfferHandlingResult(result: resumed))
        }
        if let pin = request.pin {
            guard let storedPIN = context.pin, storedPIN == pin else {
                logger.warning("PIN 校验失败：\(request.senderDeviceId)")
                return .failure(.invalidRequest("PIN 校验失败"))
            }
            guard let expiry = context.pinExpiresAt, now < expiry else {
                context.decision = .expired
                context.session.state = .failed
                contexts[context.session.id] = context
                notifySessions()
                return .failure(.confirmTimeout)
            }
            let pairingKey = PairingStore.generateKey()
            pairing.save(key: pairingKey, for: request.senderDeviceId)
            registry.setPaired(true, deviceId: request.senderDeviceId)
            context.decision = .approved
            context.pin = nil
            context.pinExpiresAt = nil
            context.session.state = .transferring
            contexts[context.session.id] = context
            logger.info("PIN 配对成功：\(request.senderDeviceId)")
            notifySessions()
            // 配对 key 走 data.pairingKey（文档 §3.5 唯一通道），响应头保留兼容
            let result = OfferResult(sessionId: context.session.id,
                                     token: context.session.token,
                                     state: .approved,
                                     accepted: acceptedOffsets(context),
                                     pairingKey: pairingKey)
            return .success(OfferHandlingResult(result: result, issuedPairingKey: pairingKey))
        }

        // 无 PIN：仍是等待确认，返回同一会话（不重复创建）
        let result = OfferResult(sessionId: context.session.id, token: context.session.token,
                                 state: .pending, accepted: [])
        return .success(OfferHandlingResult(result: result))
    }

    // MARK: - 会话构造

    /// 创建接收会话（文件名在此阶段一次确定）
    func makeOfferContext(request: OfferRequest, paired: Bool,
                                  now: Date) -> SessionContext {
        let sessionId = Self.randomHex(bytes: 16)
        let token = Self.randomHex(bytes: 16)
        var existingNames = FileNameResolver.existingNames(in: configuration.receiveDirectory)
        var receiveFiles: [String: ReceiveFileContext] = [:]
        var files: [TransferFile] = []

        for offerFile in request.files {
            let finalName = FileNameResolver.uniqueName(for: offerFile.name, in: existingNames)
            existingNames.insert(finalName)
            let finalURL = configuration.receiveDirectory.appendingPathComponent(finalName)
            receiveFiles[offerFile.fileId] = ReceiveFileContext(finalURL: finalURL,
                                                               finalName: finalName,
                                                               writer: nil)
            files.append(TransferFile(fileId: offerFile.fileId,
                                      name: finalName,
                                      size: offerFile.size,
                                      sha256: offerFile.sha256,
                                      mime: offerFile.mime))
        }

        let session = TransferSession(id: sessionId,
                                      direction: .recv,
                                      peerDeviceId: request.senderDeviceId,
                                      token: token,
                                      files: files,
                                      state: paired ? .transferring : .awaitingConfirm,
                                      createdAt: now,
                                      directory: configuration.receiveDirectory)

        return SessionContext(session: session,
                              peerIP: "",
                              peerPort: 0,
                              pin: paired ? nil : PairingStore.generatePIN(),
                              pinExpiresAt: paired ? nil : now.addingTimeInterval(configuration.confirmTimeout),
                              decision: paired ? .approved : nil,
                              receiveFiles: receiveFiles,
                              sourceFiles: [:],
                              peerDeviceId: request.senderDeviceId)
    }

    /// 已接受的续传偏移（`.part` 大小落在合法区间才 > 0）
    func acceptedOffsets(_ context: SessionContext) -> [AcceptedFile] {
        context.session.files.compactMap { file in
            guard let receive = context.receiveFiles[file.fileId] else { return nil }
            let partSize = FileStreamReader.size(of: UploadPlanner.partURL(for: receive.finalURL)) ?? 0
            let offset = UploadPlanner.resumableOffset(partSize: partSize, expectedSize: file.size)
            return AcceptedFile(fileId: file.fileId, offset: offset)
        }
    }

    /// 查找同设备同清单的未决会话（`sessionId` 不重复创建）
    func pendingContext(signature: String, sender: String, now: Date) -> SessionContext? {
        contexts.values.first { context in
            context.session.direction == .recv
                && context.session.peerDeviceId == sender
                && context.session.state == .awaitingConfirm
                && context.decision == nil
                && Self.signature(of: context.session) == signature
                && (context.pinExpiresAt.map { now < $0 } ?? false)
        }
    }

    /// 配对 key 校验（只在 `POST /offer` 上使用）
    func isPairingKeyValid(_ pairKey: String?, deviceId: String) -> Bool {
        guard let pairKey, !pairKey.isEmpty else { return false }
        return pairing.key(for: deviceId) == pairKey
    }

    /// 清单签名（设备 + 文件 sha256 集合，重命名不影响复用判定）
    public static func offerSignature(_ request: OfferRequest) -> String {
        let digests = request.files.map { $0.sha256.lowercased() }.sorted()
        return "\(request.senderDeviceId)|" + digests.joined(separator: "|")
    }

    /// 会话清单签名（设备 + 文件 sha256 集合）
    public static func signature(of session: TransferSession) -> String {
        let digests = session.files.map { $0.sha256.lowercased() }.sorted()
        return "\(session.peerDeviceId)|" + digests.joined(separator: "|")
    }

    /// 随机 hex 串（会话 id / token）
    public static func randomHex(bytes: Int) -> String {
        var values = [UInt8](repeating: 0, count: bytes)
        for index in 0..<bytes { values[index] = UInt8.random(in: 0...255) }
        return values.map { String(format: "%02x", $0) }.joined()
    }
}

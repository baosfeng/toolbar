import Foundation

// MARK: - 发送端编排

extension TransferService {

    /// 发起一次发送 — 生成清单 → `POST /offer` → 已配对直接传，未配对停在等待确认
    ///
    /// 未配对时返回的会话状态为 `awaitingConfirm`，由 UI 引导用户输入接收端显示的 PIN，
    /// 再调用 `submitPIN(_:sessionId:)` 继续（不在本方法内阻塞等待）。
    public func sendFiles(_ urls: [URL], to device: RemoteDevice) async -> Result<TransferSession, TransferError> {
        guard !urls.isEmpty else { return .failure(.invalidRequest("没有待发送文件")) }
        guard device.port > 0, !device.ip.isEmpty else {
            return .failure(.invalidRequest("设备 \(device.deviceId) 缺少可用地址"))
        }

        let prepared: (files: [TransferFile], sources: [String: URL])
        do {
            prepared = try await Self.prepareManifest(urls)
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("生成文件清单失败"))
        }

        let sessionId = Self.randomHex(bytes: 16)
        let context = SessionContext(
            session: TransferSession(id: sessionId, direction: .send,
                                     peerDeviceId: device.deviceId, token: "",
                                     files: prepared.files, state: .pending,
                                     createdAt: Date()),
            peerIP: device.ip,
            peerPort: device.port,
            pin: nil,
            pinExpiresAt: nil,
            decision: nil,
            receiveFiles: [:],
            sourceFiles: prepared.sources,
            peerDeviceId: device.deviceId)
        contexts[sessionId] = context
        notifySessions()

        // pending → offering
        if var offering = contexts[sessionId] {
            offering.session.state = .offering
            contexts[sessionId] = offering
        }

        let offerRequest = Self.makeOfferRequest(files: prepared.files, sender: localIdentity)
        do {
            let (result, issuedKey) = try await httpClient.offer(
                offerRequest, ip: device.ip, port: device.port,
                pairKey: pairing.key(for: device.deviceId))
            if let issuedKey = result.pairingKey ?? issuedKey {
                pairing.save(key: issuedKey, for: device.deviceId)
                registry.setPaired(true, deviceId: device.deviceId)
                logger.info("已保存与 \(device.deviceId) 的配对 key")
            }
            return await applyOfferResult(result, sessionId: sessionId)
        } catch let error as TransferError {
            await markFailed(sessionId: sessionId, error: error)
            return .failure(error)
        } catch {
            let error = TransferError.ioFailed("发起 offer 失败")
            await markFailed(sessionId: sessionId, error: error)
            return .failure(error)
        }
    }

    /// 提交 PIN（发送方输入接收端显示的 4 位码），成功后继续上传
    public func submitPIN(_ pin: String, sessionId: String) async -> Result<TransferSession, TransferError> {
        guard let context = contexts[sessionId], context.session.direction == .send else {
            return .failure(.sessionNotFound)
        }
        guard PairingStore.isValidPIN(pin) else {
            return .failure(.invalidRequest("PIN 必须是 4 位数字"))
        }

        let files = Self.offerFiles(from: context.session.files)
        let request = OfferRequest(senderDeviceId: localIdentity.deviceId,
                                   senderAlias: localIdentity.alias,
                                   files: files, sessionId: sessionId, pin: pin)
        do {
            let (result, issuedKey) = try await httpClient.offer(
                request, ip: context.peerIP, port: context.peerPort, pairKey: nil)
            // 配对 key 唯一通道是 data.pairingKey（响应头仅兼容旧实现）
            if let issuedKey = result.pairingKey ?? issuedKey {
                pairing.save(key: issuedKey, for: context.peerDeviceId)
                registry.setPaired(true, deviceId: context.peerDeviceId)
                logger.info("已保存与 \(context.peerDeviceId) 的配对 key")
            }
            if var updated = contexts[sessionId] {
                updated.pin = nil
                updated.pinExpiresAt = nil
                contexts[sessionId] = updated
            }
            return await applyOfferResult(result, sessionId: sessionId)
        } catch let error as TransferError {
            // PIN 错误时保持等待确认状态，允许用户重试
            logger.warning("PIN 提交失败：\(error.message)")
            return .failure(error)
        } catch {
            return .failure(.ioFailed("PIN 提交失败"))
        }
    }

    /// 取消发送（通知对端清理 `.part` 后本地转 cancelled）
    public func cancelSend(sessionId: String) async {
        if let context = contexts[sessionId], context.session.direction == .send,
           !context.session.token.isEmpty {
            try? await httpClient.cancel(sessionId: sessionId, ip: context.peerIP,
                                         port: context.peerPort, token: context.session.token)
        }
        await cancelLocal(sessionId: sessionId)
    }

    /// 点击面板任务行重试失败会话（重新走一遍 offer）
    public func retrySend(sessionId: String) async -> Result<TransferSession, TransferError> {
        guard let context = contexts[sessionId], context.session.direction == .send,
              let device = registry.device(deviceId: context.peerDeviceId) else {
            return .failure(.sessionNotFound)
        }
        let urls = context.sourceFiles.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return await sendFiles(urls, to: device)
    }

    // MARK: - offer 结果处理

    private func applyOfferResult(_ result: OfferResult,
                                  sessionId: String) async -> Result<TransferSession, TransferError> {
        guard var context = contexts[sessionId] else { return .failure(.sessionNotFound) }
        context.session.token = result.token
        context.decision = context.decision ?? .approved

        switch result.state {
        case .approved:
            applyAcceptedOffsets(result.accepted, context: &context)
            context.decision = .approved
            if context.session.state != .transferring {
                context.session.state = .transferring
            }
            contexts[sessionId] = context
            notifySessions()
            await runUploads(sessionId: sessionId)
        case .pending:
            if context.session.state == .offering {
                context.session.state = .awaitingConfirm
            }
            contexts[sessionId] = context
            notifySessions()
        case .denied:
            await markFailed(sessionId: sessionId, error: .denied)
            return .failure(.denied)
        case .expired:
            await markFailed(sessionId: sessionId, error: .confirmTimeout)
            return .failure(.confirmTimeout)
        }

        guard let session = contexts[sessionId]?.session else { return .failure(.sessionNotFound) }
        return .success(session)
    }

    /// 应用接收端确认的续传起点
    private func applyAcceptedOffsets(_ accepted: [AcceptedFile], context: inout SessionContext) {
        for item in accepted {
            guard let index = context.session.index(ofFile: item.fileId) else { continue }
            context.session.files[index].offset = item.offset
            context.session.files[index].transferred = item.offset
        }
    }

    // MARK: - 上传循环

    /// 逐文件上传，单文件失败重试 3 次（1s/2s/4s 退避，设计文档 §6）
    private func runUploads(sessionId: String) async {
        httpClient.setProgressHandler { [weak self] key, sent in
            Task { await self?.applyUploadProgress(key: key, sent: sent) }
        }
        defer { httpClient.setProgressHandler(nil) }

        guard let initial = contexts[sessionId] else { return }
        for file in initial.session.files {
            guard let context = contexts[sessionId], context.session.state == .transferring else { return }
            guard let source = context.sourceFiles[file.fileId] else { continue }
            guard let index = context.session.index(ofFile: file.fileId) else { continue }

            let expectedDigest = context.session.files[index].sha256
            var succeeded = false
            var lastError: TransferError = .ioFailed("未知错误")
            var attemptOffset = context.session.files[index].offset

            for attempt in 1...3 {
                let token = contexts[sessionId]?.session.token ?? context.session.token
                do {
                    let result = try await httpClient.upload(
                        fileURL: source, fileId: file.fileId, offset: attemptOffset,
                        sessionId: sessionId, token: token,
                        ip: context.peerIP, port: context.peerPort,
                        progressKey: "\(sessionId)|\(file.fileId)")
                    guard result.sha256.lowercased() == expectedDigest.lowercased() else {
                        throw TransferError.checksumMismatch(expected: expectedDigest,
                                                             actual: result.sha256)
                    }
                    succeeded = true
                    break
                } catch let error as TransferError {
                    lastError = error
                    logger.warning("上传 \(file.name) 第 \(attempt) 次失败：\(error.message)")
                } catch {
                    lastError = .ioFailed("上传 \(file.name) 失败")
                }
                if attempt < 3 {
                    // 接收端对 offset 严格校验：重试前向服务端确认已收字节，
                    // 从该位置续传，绝不假设可以 offset=0 覆盖（协议 §6）
                    if let reported = await refreshResumeOffset(sessionId: sessionId,
                                                                fileId: file.fileId) {
                        attemptOffset = UploadPlanner.retryOffset(serverReported: reported,
                                                                  fallback: attemptOffset)
                        logger.info("重试 \(file.name) 从服务端已收字节续传：offset=\(attemptOffset)")
                    }
                    let delay = pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }

            guard succeeded else {
                await markFailed(sessionId: sessionId, error: lastError)
                return
            }
            markFileCompleted(sessionId: sessionId, fileId: file.fileId)
        }

        // verifying → completed
        guard var finishing = contexts[sessionId] else { return }
        finishing.session.state = .verifying
        contexts[sessionId] = finishing
        notifySessions()
        finishing.session.state = .completed
        contexts[sessionId] = finishing
        notifySessions()
        finishIfNeeded(finishing.session)
    }

    /// 更新单文件发送进度（按 120ms 节流刷新 UI）
    private func applyUploadProgress(key: String, sent: Int64) {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return }
        let sessionId = String(parts[0])
        let fileId = String(parts[1])
        guard var context = contexts[sessionId],
              let index = context.session.index(ofFile: fileId) else { return }
        let offset = context.session.files[index].offset
        let size = context.session.files[index].size
        context.session.files[index].transferred = min(max(0, offset + sent), max(0, size))
        contexts[sessionId] = context
        let now = Date()
        guard now.timeIntervalSince(lastSendProgressNotify) >= 0.12 else { return }
        lastSendProgressNotify = now
        notifySessions()
    }

    /// 单文件发送完成
    private func markFileCompleted(sessionId: String, fileId: String) {
        guard var context = contexts[sessionId],
              let index = context.session.index(ofFile: fileId) else { return }
        context.session.files[index].transferred = context.session.files[index].size
        context.session.files[index].offset = 0
        contexts[sessionId] = context
        notifySessions()
    }

    /// 会话转失败并触发结束回调
    private func markFailed(sessionId: String, error: TransferError) async {
        guard var context = contexts[sessionId] else { return }
        context.session.state = .failed
        contexts[sessionId] = context
        logger.error("会话 \(sessionId) 失败：\(error.message)")
        notifySessions()
        finishIfNeeded(context.session)
    }

    // MARK: - 清单

    /// 生成发送清单（摘要计算在后台线程，避免阻塞 actor 的 HTTP 请求处理）
    private static func prepareManifest(_ urls: [URL]) async throws -> (files: [TransferFile], sources: [String: URL]) {
        try await Task.detached(priority: .userInitiated) {
            var files: [TransferFile] = []
            var sources: [String: URL] = [:]
            for (index, url) in urls.enumerated() {
                guard let size = FileStreamReader.size(of: url) else {
                    throw TransferError.ioFailed("无法读取 \(url.lastPathComponent)")
                }
                let digest = try FileStreamReader.sha256(of: url)
                let fileId = "f\(index + 1)"
                files.append(TransferFile(fileId: fileId,
                                          name: url.lastPathComponent,
                                          size: size,
                                          sha256: digest,
                                          mime: FileStreamReader.mimeType(for: url)))
                sources[fileId] = url
            }
            return (files, sources)
        }.value
    }

    private static func makeOfferRequest(files: [TransferFile], sender: LocalIdentity) -> OfferRequest {
        OfferRequest(senderDeviceId: sender.deviceId,
                     senderAlias: sender.alias,
                     files: offerFiles(from: files))
    }

    static func offerFiles(from files: [TransferFile]) -> [OfferFile] {
        files.map { file in
            OfferFile(fileId: file.fileId, name: file.name, size: file.size,
                      sha256: file.sha256, mime: file.mime)
        }
    }
}

import Foundation

// MARK: - 接收上传

extension TransferService {

    /// `PUT /upload` — 流式写入 `.part`，完成后校验 sha256 再改名
    ///
    /// 流程与设计文档 §5 一致：预检（会话 / token / offset）→ 流式落盘 → 摘要校验 →
    /// 改名 → 推进会话状态。任何校验失败都删除该文件 `.part`。
    public func receiveUpload(sessionId: String, fileId: String, offset: Int64,
                              token: String?, body: HttpBodyReader) async -> Result<UploadResult, TransferError> {
        guard var context = contexts[sessionId] else { return .failure(.sessionNotFound) }
        guard let token, !token.isEmpty, token == context.session.token else {
            return .failure(.tokenMismatch)
        }
        guard let fileIndex = context.session.index(ofFile: fileId) else {
            return .failure(.invalidRequest("文件不在清单内：\(fileId)"))
        }
        guard let receive = context.receiveFiles[fileId] else {
            return .failure(.invalidRequest("缺少落盘信息：\(fileId)"))
        }

        // 1. offset 校验：以 `.part` 实际大小为准（4003）
        let partURL = UploadPlanner.partURL(for: receive.finalURL)
        let partSize = FileStreamReader.size(of: partURL) ?? 0
        do {
            try UploadPlanner.validateOffset(requested: offset, received: partSize)
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("offset 校验失败"))
        }

        // 2. 会话进入传输态（已配对会话可能已是 transferring）
        if context.session.state == .awaitingConfirm {
            context.session.state = .transferring
        }
        guard context.session.state == .transferring else {
            return .failure(.invalidRequest("会话状态不允许上传：\(context.session.state.rawValue)"))
        }

        // 3. 打开写入器（续传时先喂已有内容给摘要）
        let writer: FileStreamWriter
        do {
            writer = try FileStreamWriter(finalURL: receive.finalURL, resumeOffset: offset)
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("创建写入器失败"))
        }
        var updatedReceive = receive
        updatedReceive.writer = writer
        context.receiveFiles[fileId] = updatedReceive
        contexts[sessionId] = context

        let expectedSize = context.session.files[fileIndex].size
        let expectedDigest = context.session.files[fileIndex].sha256
        var lastNotify = Date.distantPast
        var lastError: TransferError?

        // 4. 边收边写（64 KiB 一块，内存与文件大小无关）
        while let chunk = await body.next() {
            do {
                try writer.write(chunk)
            } catch let error as TransferError {
                lastError = error
                break
            } catch {
                lastError = .ioFailed("写入失败")
                break
            }
            let now = Date()
            if now.timeIntervalSince(lastNotify) > 0.15 {
                lastNotify = now
                updateReceiveProgress(sessionId: sessionId, fileId: fileId,
                                      transferred: writer.totalWritten)
            }
        }

        if let lastError {
            writer.discard()
            failReceive(sessionId: sessionId, error: lastError)
            return .failure(lastError)
        }

        let receivedBytes = writer.totalWritten
        guard receivedBytes >= expectedSize else {
            // 提前中断：保留 `.part` 供客户端带新 offset 续传（设计文档 §6），
            // 会话保持传输态而不是直接失败；`.part` 的清理交给 /cancel 或过期回收。
            writer.finishWithoutClosingDigest()
            updateReceiveProgress(sessionId: sessionId, fileId: fileId, transferred: receivedBytes)
            let error = TransferError.offsetMismatch(expected: expectedSize, received: receivedBytes)
            logger.warning("上传未完成（\(receivedBytes)/\(expectedSize)）：\(fileId)，保留 .part")
            return .failure(error)
        }

        // 5. 关闭并校验摘要（4005）
        let digest: String
        do {
            digest = try writer.finish()
        } catch let error as TransferError {
            writer.discard()
            failReceive(sessionId: sessionId, error: error)
            return .failure(error)
        } catch {
            writer.discard()
            let error = TransferError.ioFailed("关闭文件失败")
            failReceive(sessionId: sessionId, error: error)
            return .failure(error)
        }

        guard expectedDigest.isEmpty || digest.lowercased() == expectedDigest.lowercased() else {
            writer.discard()
            let error = TransferError.checksumMismatch(expected: expectedDigest, actual: digest)
            failReceive(sessionId: sessionId, error: error)
            return .failure(error)
        }

        // 6. 改名为正式文件（此处不再改成功文件名之外的规则）
        let finalURL = finalizeFile(partURL: partURL, receive: receive)
        guard let finalURL else {
            writer.discard()
            let error = TransferError.ioFailed("改名 \(receive.finalName) 失败")
            failReceive(sessionId: sessionId, error: error)
            return .failure(error)
        }

        // 7. 更新会话进度并推进状态
        completeReceiveFile(sessionId: sessionId, fileId: fileId, finalURL: finalURL,
                            transferred: receivedBytes)
        return .success(UploadResult(fileId: fileId, received: receivedBytes, sha256: digest))
    }

    // MARK: - 接收辅助

    /// 把 `.part` 改名为正式文件；目标被占用时重新去重
    private func finalizeFile(partURL: URL, receive: ReceiveFileContext) -> URL? {
        let manager = FileManager.default
        if !manager.fileExists(atPath: receive.finalURL.path) {
            do {
                try manager.moveItem(at: partURL, to: receive.finalURL)
                return receive.finalURL
            } catch {
                logger.warning("改名失败，尝试重新去重：\(error.localizedDescription)")
            }
        }
        let existing = FileNameResolver.existingNames(in: receiveDirectory)
        let fallbackName = FileNameResolver.uniqueName(for: receive.finalName, in: existing)
        let fallbackURL = receiveDirectory.appendingPathComponent(fallbackName)
        do {
            try manager.moveItem(at: partURL, to: fallbackURL)
            return fallbackURL
        } catch {
            logger.error("最终改名失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 更新单文件接收进度（节流由调用方控制）
    private func updateReceiveProgress(sessionId: String, fileId: String, transferred: Int64) {
        guard var context = contexts[sessionId] else { return }
        guard let index = context.session.index(ofFile: fileId) else { return }
        let size = context.session.files[index].size
        context.session.files[index].transferred = min(max(0, transferred), max(0, size))
        contexts[sessionId] = context
        notifySessions()
    }

    /// 接收完成：推进 verifying → completed
    private func completeReceiveFile(sessionId: String, fileId: String, finalURL: URL,
                                     transferred: Int64) {
        guard var context = contexts[sessionId] else { return }
        guard let index = context.session.index(ofFile: fileId) else { return }
        context.session.files[index].transferred = context.session.files[index].size
        if var receive = context.receiveFiles[fileId] {
            receive.writer = nil
            receive.finalURL = finalURL
            receive.finalName = finalURL.lastPathComponent
            context.receiveFiles[fileId] = receive
        }
        context.session.files[index].offset = 0

        let allCompleted = context.session.files.allSatisfy { $0.transferred >= $0.size }
        if allCompleted {
            // 校验（sha256）已在写入阶段完成，这里先广播一次 verifying 供 UI 过渡，
            // 再立即转 completed —— 两次都必须写回会话表，否则 UI 会永远停在「校验中」。
            context.session.state = .verifying
            contexts[sessionId] = context
            notifySessions()

            context.session.state = .completed
            contexts[sessionId] = context
        } else {
            contexts[sessionId] = context
        }
        notifySessions()
        finishIfNeeded(context.session)
    }

    /// 接收失败：会话转 failed 并清理 `.part`
    private func failReceive(sessionId: String, error: TransferError) {
        guard var context = contexts[sessionId] else { return }
        cleanupParts(&context)
        context.session.state = .failed
        contexts[sessionId] = context
        logger.error("接收失败（\(sessionId)）：\(error.message)")
        notifySessions()
        finishIfNeeded(context.session)
    }
}

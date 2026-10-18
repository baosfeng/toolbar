import Foundation

// MARK: - 续传偏移确认

/// 说明：断网重试前必须向接收端确认已收字节（协议 §6），单独成文件避免主编排文件超限。
extension TransferService {

    /// 向接收端确认某文件已收字节（断网重试前调用，协议 §6）
    public func refreshResumeOffset(sessionId: String, fileId: String) async -> Int64? {
        guard let offsets = await refreshResumeOffsets(sessionId: sessionId) else { return nil }
        return offsets[fileId]
    }

    /// 带 `sessionId` 重新 `POST /offer` 取 `accepted[].offset`，并同步本地会话
    ///
    /// 接收端对已批准 / 传输中的会话返回 `approved + accepted`（见 `handleRepeatedOffer`），
    /// 这是断网重试时获知「服务端已收字节」的唯一可靠通道。
    public func refreshResumeOffsets(sessionId: String) async -> [String: Int64]? {
        guard let context = contexts[sessionId], context.session.direction == .send else { return nil }
        let request = OfferRequest(senderDeviceId: localIdentity.deviceId,
                                   senderAlias: localIdentity.alias,
                                   files: Self.offerFiles(from: context.session.files),
                                   sessionId: sessionId)
        do {
            let (result, issuedKey) = try await httpClient.offer(
                request, ip: context.peerIP, port: context.peerPort,
                pairKey: pairing.key(for: context.peerDeviceId))
            if let issuedKey = result.pairingKey ?? issuedKey {
                pairing.save(key: issuedKey, for: context.peerDeviceId)
                registry.setPaired(true, deviceId: context.peerDeviceId)
            }
            guard result.state == .approved else {
                logger.warning("续传偏移确认未获批准：\(result.state.rawValue)")
                return nil
            }
            var offsets: [String: Int64] = [:]
            for accepted in result.accepted { offsets[accepted.fileId] = accepted.offset }
            if var updated = contexts[sessionId] {
                updated.session.token = result.token
                for (fileId, offset) in offsets {
                    guard let index = updated.session.index(ofFile: fileId) else { continue }
                    updated.session.files[index].offset = offset
                    updated.session.files[index].transferred = offset
                }
                contexts[sessionId] = updated
                notifySessions()
            }
            return offsets
        } catch let error as TransferError {
            logger.warning("续传偏移确认失败：\(error.message)")
            return nil
        } catch {
            logger.warning("续传偏移确认失败：网络不可用")
            return nil
        }
    }

}

import Foundation

// MARK: - 扫码接收通道

/// 扫码接收 — 绕过 UDP 发现的浏览器直传：二维码 → 上传页 → 裸二进制落盘
///
/// 信任边界：token、文件名、Content-Length 全部来自浏览器，任何非法输入都必须在
/// 落盘前拦下；写入采用 `FileStreamWriter` 的 `.part` + 完成后改名，中断不会留下半个文件。
extension TransferService: ScanRouteHandling {

    // MARK: - 签发链接

    /// 签发扫码链接（UI「扫码接收」入口调用）
    ///
    /// 必须使用局域网 IPv4（回环 / APIPA 地址对手机不可达），取不到时返回错误由 UI 提示。
    public func issueScanLink() -> Result<ScanSessionInfo, TransferError> {
        guard isRunning, localIdentity.port > 0 else {
            return .failure(.listenerUnavailable("HTTP 服务未启动"))
        }
        guard let ip = getLocalIPAddress(), ScanLinkBuilder.isValidLANIPv4(ip) else {
            return .failure(.invalidRequest("未取到局域网 IPv4 地址（请确认已连接 Wi-Fi 或有线网络）"))
        }
        let issued = scanTokens.issue()
        guard let url = ScanLinkBuilder.pageURL(token: issued.token, ip: ip, port: localIdentity.port) else {
            return .failure(.invalidRequest("扫码地址构造失败"))
        }
        logger.info("已签发扫码接收链接：http://\(ip):\(localIdentity.port)\(ScanProtocol.pagePath)")
        return .success(ScanSessionInfo(token: issued.token, url: url, expiresAt: issued.expiresAt))
    }

    /// 只签发 token（无局域网 IP 时的回退 / 测试用）
    public func issueScanToken() -> ScanTokenStore.Issued {
        scanTokens.issue()
    }

    /// token 剩余有效秒数（UI 倒计时兜底；无效返回 0）
    public nonisolated func scanTokenRemainingSeconds(_ token: String) -> Int {
        scanTokens.remainingSeconds(token)
    }

    // MARK: - GET /scan

    /// 上传页：token 无效 / 过期 / 伪造统一 4001
    public func scanPage(token: String) async -> Result<String, TransferError> {
        guard scanTokens.isValid(token) else {
            logger.warning("扫码页请求被拒：token 无效或已过期")
            return .failure(.tokenMismatch)
        }
        return .success(ScanPageRenderer.html(token: token))
    }

    // MARK: - POST /scan/upload

    /// 流式接收裸二进制并写入收件目录
    ///
    /// 校验顺序：token → 内容长度上限 → 磁盘空间 → 文件名清洗去重 → 边收边写 → 改名。
    public func scanUpload(token: String, name: String, contentLength: Int64,
                           body: HttpBodyReader) async -> Result<ScanUploadResult, TransferError> {
        guard scanTokens.isValid(token) else {
            return .failure(.tokenMismatch)
        }
        guard contentLength >= 0, contentLength <= ScanProtocol.maxFileBytes else {
            return .failure(.payloadTooLarge(limit: ScanProtocol.maxFileBytes))
        }

        // 写入前预检磁盘空间（Content-Length 未知时跳过，落盘阶段仍有大小上限兜底）
        do {
            try DiskSpaceProbe.require(bytes: contentLength, at: receiveDirectory)
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("磁盘空间预检失败"))
        }

        let resolvedName = ScanFileNaming.resolve(name)
        let existing = FileNameResolver.existingNames(in: receiveDirectory)
        let uniqueName = FileNameResolver.uniqueName(for: resolvedName, in: existing)
        let finalURL = receiveDirectory.appendingPathComponent(uniqueName)

        let writer: FileStreamWriter
        do {
            writer = try FileStreamWriter(finalURL: finalURL)
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("创建写入器失败"))
        }

        var written: Int64 = 0
        while let chunk = await body.next() {
            if written + Int64(chunk.count) > ScanProtocol.maxFileBytes {
                writer.discard()
                logger.warning("扫码上传超过 2 GiB 上限，已丢弃：\(uniqueName)")
                return .failure(.payloadTooLarge(limit: ScanProtocol.maxFileBytes))
            }
            do {
                try writer.write(chunk)
                written += Int64(chunk.count)
            } catch let error as TransferError {
                writer.discard()
                return .failure(error)
            } catch {
                writer.discard()
                return .failure(.ioFailed("写入 \(uniqueName) 失败"))
            }
        }

        // 声明了长度但没读满（连接中断）：删除 `.part`，不留下半个文件
        if contentLength > 0, written < contentLength {
            writer.discard()
            logger.warning("扫码上传中断（\(written)/\(contentLength)）：\(uniqueName)")
            return .failure(.invalidRequest("上传未完成（\(written)/\(contentLength) 字节）"))
        }

        do {
            _ = try writer.finish()
        } catch let error as TransferError {
            writer.discard()
            return .failure(error)
        } catch {
            writer.discard()
            return .failure(.ioFailed("关闭 \(uniqueName) 失败"))
        }

        let partURL = UploadPlanner.partURL(for: finalURL)
        guard move(partURL: partURL, to: finalURL) else {
            try? FileManager.default.removeItem(at: partURL)
            return .failure(.ioFailed("改名 \(uniqueName) 失败"))
        }
        logger.info("扫码接收完成：\(uniqueName)（\(written) 字节）")
        return .success(ScanUploadResult(savedAs: uniqueName))
    }

    // MARK: - 内部

    /// `.part` → 正式文件；目标被占用时按现有目录重新去重一次
    private func move(partURL: URL, to finalURL: URL) -> Bool {
        let manager = FileManager.default
        if !manager.fileExists(atPath: finalURL.path) {
            do {
                try manager.moveItem(at: partURL, to: finalURL)
                return true
            } catch {
                logger.warning("扫码落盘改名失败，尝试重新去重：\(error.localizedDescription)")
            }
        }
        let existing = FileNameResolver.existingNames(in: receiveDirectory)
        let fallbackName = FileNameResolver.uniqueName(for: finalURL.lastPathComponent, in: existing)
        do {
            try manager.moveItem(at: partURL,
                                 to: receiveDirectory.appendingPathComponent(fallbackName))
            return true
        } catch {
            logger.error("扫码落盘最终改名失败：\(error.localizedDescription)")
            return false
        }
    }
}

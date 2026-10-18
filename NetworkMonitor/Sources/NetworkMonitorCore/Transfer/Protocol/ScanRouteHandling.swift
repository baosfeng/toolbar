import Foundation

// MARK: - 扫码接收路由协议

/// 扫码接收路由处理协议 — 与 `TransferRouteHandling` 分开，避免往旧协议塞新方法（ISP）
///
/// 只定义「要做什么」：校验 token、给出上传页 HTML、把裸二进制流写入收件目录。
public protocol ScanRouteHandling: AnyObject, Sendable {

    /// `GET /scan?t=<token>`：返回上传页 HTML；token 无效/过期返回 `tokenMismatch`（4001）
    func scanPage(token: String) async -> Result<String, TransferError>

    /// `POST /scan/upload?t=<token>&name=<urlencoded>`：流式落盘
    ///
    /// - Parameters:
    ///   - token: 扫码 token
    ///   - name: 原始文件名（未清洗，服务端负责清洗与去重）
    ///   - contentLength: 请求体字节数（`Content-Length`，用于上限与磁盘预检）
    ///   - body: 流式请求体
    func scanUpload(token: String, name: String, contentLength: Int64,
                    body: HttpBodyReader) async -> Result<ScanUploadResult, TransferError>
}

import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 真实网络自证（人工触发）

/// 真实 GitHub Releases 请求 — `swift run ... TestRunner --update-check-live`
///
/// 不进默认测试流程：默认测试必须离线可跑，这里是一次真实网络往返。
/// 打印三件事：HTTP 状态与耗时、原始响应解码出的 tag 与版本判定、真实实现
/// （`GitHubUpdateChecker.fetchLatestRelease`）的结果——两条路径都打，才算自证。
func runUpdateCheckLiveProbe() {
    print("🧪 Live probe: GitHub Releases API（真实网络，匿名只读）...")
    let box = ProbeLineBox()
    let semaphore = DispatchSemaphore(value: 0)

    Task.detached {
        // 1) 原始请求：状态码 + 耗时 + 同一份 data 走同一套解码
        let url = URL(string: "https://api.github.com/repos/baosfeng/toolbar/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("一览/live-probe", forHTTPHeaderField: "User-Agent")
        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(started)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            box.append("HTTP 状态=\(status) 耗时=\(String(format: "%.3f", elapsed))s 字节=\(data.count)")
            let release = try GitHubUpdateChecker.release(fromJSON: data)
            let current = ProcessInfo.processInfo.environment["NM_CURRENT_VERSION"] ?? "1.24.2"
            let available = UpdateVersionLogic.isUpdateAvailable(current: current,
                                                                 latest: release.tagName)
            box.append("解析 tag=\(release.tagName) 当前=\(current) 判定="
                       + (available.map { $0 ? "有新版本" : "已是最新" } ?? "无法比较"))
            box.append("说明摘要=\(UpdateNotes.summary(release.notes))")
        } catch {
            box.append("原始请求失败：\(error)")
        }

        // 2) 真实实现（App 内用的就是它）
        let checker = GitHubUpdateChecker(userAgent: "一览/live-probe")
        do {
            let release = try await checker.fetchLatestRelease()
            box.append("checker tag=\(release.tagName) url=\(release.htmlURL?.absoluteString ?? "nil")"
                       + " publishedAt=\(release.publishedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")
        } catch let error as UpdateCheckError {
            box.append("checker 失败：\(error.userMessage)")
        } catch {
            box.append("checker 失败：\(error)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    for line in box.all { print("   " + line) }
}

// MARK: - 行缓冲

/// 后台任务写、主线程读的字符串缓冲（跨并发边界用锁保护）
private final class ProbeLineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

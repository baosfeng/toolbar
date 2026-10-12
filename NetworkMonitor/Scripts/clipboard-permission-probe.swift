// 剪贴板访问授权探针
//
// 用途：实测 macOS 15.4+ 中「后台程序化读取系统剪贴板」是否会触发系统授权弹窗、
//       触发几次、是否阻塞读取。结论决定 ClipboardCaptureService 的最终实现方式。
//
// 背景：Apple 文档明确 General pasteboard 在程序化访问时的默认行为是 ask：
//       "The default behavior for the General pasteboard is to ask upon programmatic
//        access. ... Once programmatic pasteboard access triggers the first pasteboard
//        access alert, the state automatically changes to .ask."
//       来源：https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum/default
//
// 用法：
//   swift Scripts/clipboard-permission-probe.swift --seconds 120
//   swift Scripts/clipboard-permission-probe.swift --force --seconds 60
//   ./Scripts/clipboard-probe.sh          # 打包成 .app 运行，授权归属更贴近真实应用
//
// 参数：
//   --seconds N   观察时长，默认 120 秒
//   --interval S  轮询间隔（秒），默认 0.5，与正式实现保持一致
//   --force       忽略 changeCount 判断，每轮都真实读取（用于测试最坏情况）

import AppKit
import Foundation

// MARK: - 参数解析

private let arguments = CommandLine.arguments

/// 读取形如 --name value 的数值参数
private func doubleArg(_ name: String, default fallback: Double) -> Double {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count,
          let value = Double(arguments[index + 1]) else { return fallback }
    return value
}

private let observeSeconds = doubleArg("--seconds", default: 120)
private let pollInterval = max(doubleArg("--interval", default: 0.5), 0.1)
private let forceRead = arguments.contains("--force")

private let logPath = "/tmp/clipboard-probe.log"

// MARK: - 输出

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

/// 同时输出到标准输出与日志文件，便于打包成 .app 后回看
private func emit(_ text: String) {
    let line = "[\(timeFormatter.string(from: Date()))] \(text)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.close()
    }
}

// MARK: - 授权行为描述

/// 把 NSPasteboard.AccessBehavior 转成可读中文
private func accessBehaviorDescription() -> String {
    guard #available(macOS 15.4, *) else { return "系统低于 15.4，无此 API" }
    let behavior = NSPasteboard.general.accessBehavior
    if behavior == .alwaysAllow { return "alwaysAllow — 已放行，不再弹窗" }
    if behavior == .alwaysDeny { return "alwaysDeny — 已被拒绝" }
    if behavior == .ask { return "ask — 已弹过窗，可在系统设置中切换" }
    if behavior == .`default` { return "default — 从未弹过窗，不在系统设置中显示" }
    return "未知行为：\(behavior.rawValue)"
}

// MARK: - 探针

/// 剪贴板读取授权探针：轮询 changeCount，变更时真实读取并记录耗时与授权状态
final class ClipboardProbe {
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var changeCountHits = 0
    private var realReads = 0
    private var slowReads = 0
    private var initialBehavior = ""

    /// 启动前记录一次基线授权状态
    func reportBaseline() {
        initialBehavior = accessBehaviorDescription()
        emit("起始授权状态：\(initialBehavior)")
        emit("当前 changeCount：\(lastChangeCount)")
    }

    /// 单轮探测
    func tick() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        let changed = currentChangeCount != lastChangeCount
        guard changed || forceRead else { return }

        if changed {
            changeCountHits += 1
            lastChangeCount = currentChangeCount
        }

        // 读取前记录授权状态 —— 若从 default 变为 ask，说明本轮触发了系统弹窗
        let behaviorBefore = accessBehaviorDescription()

        let started = Date()
        let types = pasteboard.types?.map(\.rawValue).sorted() ?? []
        let text = pasteboard.string(forType: .string)
        let elapsed = Date().timeIntervalSince(started)

        realReads += 1
        let blocked = elapsed > 0.3
        if blocked { slowReads += 1 }

        let behaviorAfter = accessBehaviorDescription()
        let behaviorChanged = behaviorBefore != behaviorAfter

        var summary = "读取 #\(realReads)"
        summary += changed ? "（changeCount \(lastChangeCount)）" : "（--force 强制）"
        summary += " 耗时 \(Int(elapsed * 1000))ms"
        if blocked { summary += "  ⚠️ 疑似被系统弹窗阻塞" }
        if behaviorChanged { summary += "\n        授权状态变化：\(behaviorBefore)  →  \(behaviorAfter)" }
        emit(summary)

        emit("        类型：\(types.isEmpty ? "（空）" : types.joined(separator: ", "))")
        emit("        文本：\(text.map { "\($0.count) 字 — \($0.prefix(40).replacingOccurrences(of: "\n", with: " "))" } ?? "（无纯文本）")")
    }

    /// 汇总
    func reportSummary() {
        emit("──────── 汇总 ────────")
        emit("changeCount 变更次数：\(changeCountHits)")
        emit("真实读取次数：\(realReads)")
        emit("疑似被弹窗阻塞的读取：\(slowReads)")
        emit("起始授权状态：\(initialBehavior)")
        emit("结束授权状态：\(accessBehaviorDescription())")
        emit("日志文件：\(logPath)")
        emit("判读：真实读取次数 ≈ 系统弹窗次数（若状态从 default 变为 ask，说明确实弹过窗）")
    }
}

// MARK: - 主流程

FileManager.default.createFile(atPath: logPath, contents: nil)

emit("════ 剪贴板访问授权探针 ════")
emit("进程：\(ProcessInfo.processInfo.processName)  PID：\(ProcessInfo.processInfo.processIdentifier)")
emit("包路径：\(Bundle.main.bundlePath)")
emit("Bundle ID：\(Bundle.main.bundleIdentifier ?? "（无，直接以脚本运行）")")
emit("观察时长：\(Int(observeSeconds))s  轮询间隔：\(pollInterval)s  强制读取：\(forceRead)")
emit("")
emit("请保持本进程运行，并切换到其他 App 复制 3~5 段文字（每次间隔几秒）。")
emit("重点观察：屏幕上是否出现系统授权弹窗、弹了几次、弹窗内容是什么。")
emit("")

let probe = ClipboardProbe()
probe.reportBaseline()

let deadline = Date().addingTimeInterval(observeSeconds)
while Date() < deadline {
    // 跑 RunLoop 而非 sleep，保证系统弹窗等事件可正常处理
    RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    probe.tick()
}

probe.reportSummary()

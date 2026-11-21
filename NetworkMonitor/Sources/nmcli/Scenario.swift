import AppKit
import CoreGraphics
import Foundation

// MARK: - 场景预设

/// 场景 = 一串带断言的复杂操作，一条命令跑完并产出证据包
///
/// 与 `run` 的区别：`run` 是用户手写的通用步骤串，场景是**针对本应用版式**预置的
/// 固定剧本（知道面板几个 tab、系统页哪张卡可展开、设置侧栏有哪些分类），
/// 失败文案与产物命名都按验收口径写死，方便反复跑、批量比对。
enum Scenario {

    /// 产物跑名的入口；失败抛错（main 转成 exit 1）
    static func run(name: String, outDirectory: String) throws {
        switch name {
        case "panel-tour":
            try panelTour(outDirectory: outDirectory)
        default:
            throw CLIError("未知场景「\(name)」（可用：panel-tour）")
        }
    }

    // MARK: 面板巡览

    private static func panelTour(outDirectory: String) throws {
        let target = try AppTarget.resolve("一览")
        AppTarget.warnIfMultipleInstances(named: target.name)
        let recorder = Recorder(directory: outDirectory)
        try FileManager.default.createDirectory(atPath: recorder.resolvedDirectory,
                                                withIntermediateDirectories: true)

        // 1) 幂等开面板：先查现况，已经开着就复用（AXPress 是 toggle，盲按会把它关掉）
        try recorder.step("打开面板（幂等：已开则复用）") {
            guard let item = MenuBarReader.primaryStatusItem(of: target) else {
                throw CLIError("读不到菜单栏状态项（辅助功能权限？）")
            }
            let statusFrame = item.frameDescription
            let result = PanelGeometry.openPanel(target)
            guard result != .failed else {
                throw CLIError("AXPress 后 2s 内面板没有出现（面板此前是否已开？见 openPanel 的幂等检查）")
            }
            guard let panel = PanelGeometry.panel(of: target) else {
                throw CLIError("面板打开了但 CGWindowList 里没有 layer 25 窗口")
            }
            let how = result == .alreadyOpen ? "panel already open（未重复 AXPress）" : "AXPress 新开"
            guard panel.bounds.width > 300 else {
                throw CLIError("面板尺寸仍在动画中间态：\(Format.rect(panel.bounds))")
            }
            return "状态项 \(statusFrame)；\(how)；面板 id=\(panel.id) \(Format.rect(panel.bounds))"
        }

        // 2) 依次切面板**当前实际显示**的全部分页，各存一张
        // 段数取 AX 现读（用户可隐藏 / 重排分页），不是写死的全集
        let visibleTabs = PanelGeometry.visibleTabNames(of: target)
        for (index, name) in visibleTabs.enumerated() {
            try recorder.step("切到「\(name)」tab") {
                guard PanelGeometry.panel(of: target) != nil else {
                    throw CLIError("切页前面板消失了")
                }
                guard PanelGeometry.selectTab(target, index: index) else {
                    throw CLIError("坐标点击 tab 后读不到面板")
                }
                guard let after = PanelGeometry.panel(of: target) else {
                    throw CLIError("切页后面板消失了")
                }
                let selected = PanelGeometry.selectedTab(of: target) ?? "?"
                guard selected == name else {
                    throw CLIError("切页后选中态是「\(selected)」，不是「\(name)」")
                }
                let shot = try Capture.shot(.window(after.id), to: recorder.path("tab-\(index + 1)-\(name).png"))
                recorder.record(shot)
                return "选中=「\(selected)」；面板 \(Format.rect(after.bounds))；\(shot.describe)"
            }
        }

        // 3) 进系统页某张卡的二级详情页再返回
        try recorder.step("系统页 → CPU 卡二级详情") {
            guard let systemIndex = PanelGeometry.visibleTabIndex(of: "系统", in: target) else {
                throw CLIError("当前显示的分页里没有「系统」")
            }
            guard PanelGeometry.selectTab(target, index: systemIndex) else {
                throw CLIError("切不到系统页")
            }
            guard let panel = PanelGeometry.panel(of: target) else {
                throw CLIError("系统页读不到面板")
            }
            guard let card = AXRoots.collect(target, maxDepth: 16, match: {
                $0.role == "AXButton" && $0.desc == "CPU"
            }).first else {
                throw CLIError("系统页没有 desc=CPU 的卡（AX 未上报？）")
            }
            guard Actions.press(card) else { throw CLIError("CPU 卡的 AXPress 失败") }
            usleep(900_000)
            guard let detail = PanelGeometry.panel(of: target) else {
                throw CLIError("进详情页后读不到面板")
            }
            let shot = try Capture.shot(.window(detail.id), to: recorder.path("system-cpu-detail.png"))
            recorder.record(shot)
            return "卡片 \(card.frameDescription) → 详情面板 \(Format.rect(detail.bounds))；面板高 \(Int(panel.bounds.height)) → \(Int(detail.bounds.height))；\(shot.describe)"
        }

        try recorder.step("二级详情页返回系统页") {
            guard let back = AXRoots.collect(target, maxDepth: 16, match: {
                $0.role == "AXButton" && $0.desc.contains("返回")
            }).first else {
                throw CLIError("详情页没有「返回」按钮")
            }
            guard Actions.press(back) else { throw CLIError("返回按钮 AXPress 失败") }
            usleep(800_000)
            let stillDetail = AXRoots.collect(target, maxDepth: 16) { $0.desc == "CPU" }.isEmpty
            guard !stillDetail else { throw CLIError("按了返回，但系统页的 CPU 卡没回来") }
            guard let panel = PanelGeometry.panel(of: target) else { throw CLIError("返回后面板消失了") }
            let shot = try Capture.shot(.window(panel.id), to: recorder.path("system-back.png"))
            recorder.record(shot)
            return "返回按钮 \(back.desc)；面板 \(Format.rect(panel.bounds))；\(shot.describe)"
        }

        // 4) 分页条不该再有「剪贴板」段（该分页已下线，历史只在独立浮层里看）
        try recorder.step("分页条无「剪贴板」段") {
            guard let panel = PanelGeometry.panel(of: target) else { throw CLIError("核对分页条时面板消失了") }
            let titles = Set(PanelGeometry.visibleTabNames(of: target))
            guard !titles.contains("剪贴板") else {
                throw CLIError("分页条里仍有「剪贴板」段：菜单面板剪贴板分页没有下线")
            }
            let shot = try Capture.shot(.window(panel.id), to: recorder.path("tabbar-segments.png"))
            recorder.record(shot)
            return "读到 \(titles.sorted())（\(titles.count) 段）；面板 \(Format.rect(panel.bounds))；\(shot.describe)"
        }

        // 5) 关面板
        try recorder.step("关闭面板") {
            guard PanelGeometry.closePanel(target) else { throw CLIError("收起失败：面板仍在") }
            return "layer 25 窗口已消失"
        }

        // 6) 设置窗口 → 关于页 → 截图 → 关闭
        try recorder.step("打开设置窗口") {
            guard SettingsWindow.open(target) else { throw CLIError("菜单「设置…」AXPress 后没有设置窗口") }
            usleep(400_000)
            guard let window = SettingsWindow.window(of: target) else { throw CLIError("设置窗口读不到") }
            return "设置窗口 \(window.frameDescription)"
        }

        try recorder.step("切到「关于」页并截图") {
            guard SettingsWindow.selectSection(target, name: "关于") else {
                throw CLIError("侧栏找不到「关于」行")
            }
            guard let window = SettingsWindow.window(of: target) else { throw CLIError("切页后设置窗口读不到") }
            guard let panelWindow = WindowList.visibleWindows(of: target.pid).first(where: {
                $0.layer == 0 && $0.bounds.width > 600
            }) else { throw CLIError("CGWindowList 里没有设置窗口") }
            let shot = try Capture.shot(.window(panelWindow.id), to: recorder.path("settings-about.png"))
            recorder.record(shot)
            return "设置窗口 \(window.frameDescription)；\(shot.describe)"
        }

        try recorder.step("关闭设置窗口") {
            guard SettingsWindow.close(target) else { throw CLIError("关闭按钮 AXPress 后设置窗口仍在") }
            return "设置窗口已关闭"
        }

        let summaryPath = try recorder.writeSummary(target: target, scenario: "panel-tour")
        Out.line("")
        Out.line("产物：\(recorder.artifacts.count) 张 PNG + summary.json")
        Out.line("summary：\(summaryPath)")
    }
}

// MARK: - 台账

/// 场景执行台账：每步耗时 / 成败 / 产物，最后落 summary.json
final class Recorder {

    struct StepRecord {
        let index: Int
        let name: String
        let ok: Bool
        let milliseconds: Int
        let detail: String
    }

    private let directory: String
    private(set) var steps: [StepRecord] = []
    private(set) var artifacts: [ShotResult] = []

    init(directory: String) {
        self.directory = (directory as NSString).expandingTildeInPath
    }

    /// 展开 `~` 与相对路径后的输出目录（创建目录与写文件必须用同一份）
    var resolvedDirectory: String {
        (directory as NSString).expandingTildeInPath
    }

    func path(_ name: String) -> String {
        (directory as NSString).appendingPathComponent(name)
    }

    func record(_ shot: ShotResult) {
        artifacts.append(shot)
    }

    /// 跑一步并记账：成功打印明细，失败打印原因后继续抛（由调用方决定是否中止）
    func step(_ name: String, _ body: () throws -> String) throws {
        let started = Date()
        let index = steps.count + 1
        do {
            let detail = try body()
            let elapsed = Format.milliseconds(Date().timeIntervalSince(started))
            steps.append(StepRecord(index: index, name: name, ok: true, milliseconds: elapsed, detail: detail))
            Out.line("[\(index)] \(name) -> ok (\(elapsed)ms)  \(detail)")
        } catch {
            let elapsed = Format.milliseconds(Date().timeIntervalSince(started))
            let message = (error as? CLIError)?.description ?? "\(error)"
            steps.append(StepRecord(index: index, name: name, ok: false, milliseconds: elapsed, detail: message))
            Out.line("[\(index)] \(name) -> fail (\(elapsed)ms)  \(message)")
            throw error
        }
    }

    /// 落 summary.json 并返回路径
    func writeSummary(target: AppTarget, scenario: String) throws -> String {
        let payload: [String: Any] = [
            "scenario": scenario,
            "pid": Int(target.pid),
            "app": target.name,
            "bundleId": target.bundleID,
            "finishedAt": ISO8601DateFormatter().string(from: Date()),
            "totalMilliseconds": steps.reduce(0) { $0 + $1.milliseconds },
            "ok": steps.allSatisfy(\.ok),
            "steps": steps.map { step -> [String: Any] in
                ["index": step.index, "step": step.name, "ok": step.ok,
                 "milliseconds": step.milliseconds, "detail": step.detail]
            },
            "artifacts": artifacts.map { shot -> [String: Any] in
                ["path": shot.path, "width": shot.width, "height": shot.height,
                 "bytes": shot.bytes, "mode": shot.mode.rawValue]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let summaryPath = path("summary.json")
        try data.write(to: URL(fileURLWithPath: summaryPath))
        return summaryPath
    }
}
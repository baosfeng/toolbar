import AppKit
import Foundation

// MARK: - nmcli 入口

/// 分发表：命令名 → 实现。`run` / `scenario` 在下方单独处理（它们自带子语法）
nonisolated(unsafe) let handlers: [String: (Args) throws -> Void] = [
    "apps": Commands.apps,
    "windows": Commands.windows,
    "ax": Commands.ax,
    "at": Commands.at,
    "find": Commands.find,
    "click": Commands.click,
    "click-at": Commands.clickAt,
    "hover": Commands.hover,
    "type": Commands.type,
    "key": Commands.key,
    "shot": Commands.shot,
    "wait": Commands.wait,
    "wait-window": Commands.waitWindow,
    "menubar": Commands.menubar,
    "page": PageCommand.run
]

let usage = """
nmcli — 一览（菜单栏 App）UI 自动化 CLI

用法：
  nmcli apps                              列出运行中的 app（pid / bundleId / 名字 / 窗口数）
  nmcli windows <app> [--layer N]         列出窗口（含 NSPanel；CGWindowList 口径）
  nmcli ax <app> [--depth N]              dump AX 树
  nmcli at <x> <y>                        坐标命中测试：该点最上层 AX 元素
  nmcli find <app> [--role R] [--title T] [--desc D] [--index N]
  nmcli click <app> [--role R] [--title T] [--desc D] [--index N]
  nmcli click-at <x> <y>                  裸坐标点击
  nmcli hover <x> <y> [--hold 450]        移动光标并保持
  nmcli type <text>                       键入文本
  nmcli key <combo>                       如 cmd+w / esc / enter
  nmcli shot --out <file> [--window <id>] [--rect x,y,w,h] [--app <app> --layer N]
  nmcli wait <ms>
  nmcli wait-window <app> --layer 25 --timeout 2000 [--gone]
  nmcli menubar <app>                     菜单栏状态项（title / 实时 bounds / actions）
  nmcli run "<step>; <step>; …"           一串步骤跑完（set k=v / $(k) 插值 / assert）
  nmcli scenario panel-tour --out-dir DIR 预置剧本：面板巡览全套证据
  nmcli page list                         列出 page 命令可打开的目标页面
  nmcli page open <target>                让运行中的 app 打开页面（不重启、不退出）
  nmcli page shot --out <file> [--target <target>]
                                          打开目标页面并截图输出 PNG（默认 target=current）

说明：
  · app 参数接受 pid / bundleId / 本地化名 / 可执行名，只匹配运行中进程，从不新启实例
  · 面板（NSPanel）只在 CGWindowList 里，layer 25
"""

func main() {
    let raw = Array(CommandLine.arguments.dropFirst())
    guard let command = raw.first, command != "--help", command != "-h", command != "help" else {
        print(usage)
        exit(raw.isEmpty ? 1 : 0)
    }
    let args = Args(Array(raw.dropFirst()))
    do {
        switch command {
        case "run":
            var runner = Runner()
            let script = try args.positional(0, "steps")
            let ok = runner.run(script)
            exit(ok ? 0 : 1)
        case "scenario":
            let name = try args.positional(0, "name")
            let outDirectory = args.string("out-dir") ?? "/tmp/nmcli-verify"
            try Scenario.run(name: name, outDirectory: outDirectory)
            exit(0)
        default:
            guard let handler = handlers[command] else {
                Out.note("未知命令「\(command)」\n")
                Out.note(usage)
                exit(2)
            }
            try handler(args)
            exit(0)
        }
    } catch let error as CLIError {
        Out.note("错误：\(error.description)")
        exit(1)
    } catch {
        Out.note("错误：\(error)")
        exit(1)
    }
}

main()

# UI 自动化 CLI（nmcli）

> **何时阅读：** 要给菜单栏 app 做程序化验收（点开面板、切页、悬停、截图、断言）时先看这里；
> 需要「一条命令跑完一整套复杂操作」时直接看场景预设一节。

## 它是什么

`nmcli` 是本仓自研的 UI 自动化命令行工具（target 名 `nmcli`，产物同名），
只依赖系统框架（AppKit / ApplicationServices / CoreGraphics / ImageIO），零第三方依赖。

它解决的是「菜单栏 app 没法用常规手段验收」这件事：

- 目标 app 是 `LSUIElement` 菜单栏程序，没有可切换的主窗口；
- 交互面板是 `NSPanel`（`.nonactivatingPanel`），**不在 AX 的 `AXWindows` 里**，
  只有 `CGWindowListCopyWindowInfo(.optionAll)` 能拿到它的 id / layer / alpha / bounds；
- 菜单栏状态项的屏幕 x 随上下行速率文字宽度实时变化，**任何写死坐标的方案都会失效**。

## 与 cua 的边界

| 维度 | nmcli | cua（getApp / 截图等） |
|------|-------|------------------------|
| 目标进程 | 只用 `NSWorkspace.runningApplications` 按 pid 直连，**从不新起实例** | `getApp(一览)` 每次调用都可能再拉起一个实例（实测一次搞出 9 个进程） |
| 面板窗口 | 走 `CGWindowListCopyWindowInfo`，能拿到 layer 25 的 `NSPanel` | 走 AX 窗口树，拿不到非激活面板 |
| 用途 | 可重复、可脚本化、可进 CI 的验收 | 人工临时观察 |
| 输出 | stdout 结构化文本 + PNG + `summary.json` | 交互式结果 |

**结论**：验收菜单栏 app 用 nmcli；需要「看一眼屏幕」这类临时观察才用 cua，且不要对菜单栏 app 调 `getApp`。

## 权限要求

| 能力 | 需要的授权 | 授权对象 |
|------|-----------|---------|
| 读 AX 树 / 命中测试 / `AXPress` | 辅助功能 | 发起 nmcli 的终端（或父进程链上被授权的 app） |
| 截图（`screencapture`）、`CGWindowList` 读窗口 | 屏幕录制 | 同上 |
| 合成鼠标 / 键盘事件 | 输入监控（可只授「辅助功能」） | 同上 |

从 shell 起的子进程继承父进程的 TCC 授权，所以只要终端已授权，`swift build` 出来的 `nmcli` 直接可用。
自检命令：

```bash
nmcli ax 一览 --depth 2        # 有输出（AXApplication / 窗口 / 菜单栏）= 辅助功能就绪
nmcli shot --out /tmp/t.png    # 打印像素尺寸 = 屏幕录制就绪
```

两者都失败时先去「系统设置 → 隐私与安全性」给发起命令的终端（或 IDE）勾上对应权限，
改完要重启终端进程（TCC 授权在进程启动时读取）。

## 命令表

```text
nmcli apps                                          运行中的 app（pid / bundleId / 名字 / 窗口数）
nmcli windows <app> [--layer N]                     窗口列表（含 NSPanel；CGWindowList 口径）
nmcli ax <app> [--depth N] [--max-nodes N]          dump AX 树（role / title / desc / bounds / actions）
nmcli at <x> <y>                                    坐标命中测试：该点最上层 AX 元素
nmcli find <app> [--role R] [--title T] [--desc D] [--value V] [--index N]
nmcli click <app> [--role R] [--title T] [--desc D] [--index N]
nmcli click-at <x> <y>                              裸坐标点击
nmcli hover <x> <y> [--hold 450]                    移动光标并保持 N 毫秒
nmcli type <text>                                   键入文本
nmcli key <combo> [--app <app>]                     如 cmd+w / esc / enter / opt+cmd+v
nmcli shot --out <file> [--window <id>] [--rect x,y,w,h] [--app <app> --layer N]
nmcli wait <ms>
nmcli wait-window <app> --layer 25 --timeout 2000 [--gone]
nmcli menubar <app>                                 菜单栏状态项（title / 实时 bounds / actions）
nmcli run "<step>; <step>; …"                       一串步骤跑完
nmcli scenario panel-tour --out-dir <dir>           预置剧本：面板巡览全套证据
```

`<app>` 接受 pid / bundleId / 本地化名 / 可执行名，**只匹配运行中进程**，匹配不到直接报错，不会替你启动。

### 点击口径

`click` 的优先级是 **AXPress → 坐标中心**：菜单栏状态项（`AXMenuBarItem`）能直接接受
`kAXPressAction` 并真的打开面板；自绘元素往往没有 `AXPress`，这时才按它上报的 bounds 中心做坐标点击。
输出里会写清走的是哪条路（`AXPress ok` / `坐标回退`）。

### 截图口径

`shot` 默认走 `screencapture -l<windowid>`。**对拿不到图窗（部分 borderless / 离屏窗口）会自动回退**
到按 CGWindowList 现查 bounds 的矩形截图，输出与 `summary.json` 里标 `[rectFallback] (via rect fallback)`——
矩形口径会多截到窗口阴影外的背景，读图时必须知道这一点。

## 场景预设

```bash
nmcli scenario panel-tour --out-dir /tmp/nmcli-verify/
```

一条命令依次完成：幂等开面板 → 5 个 tab 各截一张 → 系统页 CPU 卡二级详情 → 返回 →
剪贴板页 hover 0.6s（与基线做像素差）→ 关面板 → 开设置窗口 → 「关于」页 → 截图 → 关窗口。
产物 10 张 PNG + `summary.json`（每步 ok / 耗时 / 明细 / 产物尺寸与截图 mode）。

要点：

- **切 tab 用坐标点击**，坐标按 CGWindowList 现查的面板 bounds 换算（左右各 25pt、5 等分、纵向 35pt）；
- 切页成功后校验 AX 的 `value=已选中`，不是「看高度变了」——剪贴板与 Token 页高度都是 331；
- 面板打开有开合动画，中间态尺寸是 254×243 / 310×297，**必须等到连续两次采样一致**再算坐标。

## nmcli run：把一串操作合并成一条命令

```bash
nmcli run 'set out=/tmp/nmcli-run; wait 200; click 一览 --role AXMenuBarItem --index 0;   wait-window 一览 --layer 25 --timeout 2000; assert window 一览 --layer 25;   shot --out $(out)/open.png --app 一览 --layer 25;   click 一览 --role AXMenuBarItem --index 0; assert window 一览 --layer 25 --gone'
```

- 步骤以分号分隔，双引号内的分号不切；
- 变量用 `set k=v` 定义、`$(k)` 插值（**用圆括号不用花括号**，后者会被 shell 提前展开成空串，
  shell 里请用单引号包住整串）；
- 断言三种：`assert window <app> --layer 25 [--gone]`、`assert element <app> --role … --title …`、
  `assert pixels <a.png> vs <b.png> --max-diff 0.01`；
- 每步打印 `[n] step -> ok/fail (耗时)`，**失败即停**，任一失败整体 exit 1；
- 可被 `run` 调用的步骤：`set / wait / wait-window / assert / click / click-at / hover / type / key / shot / at / find / menubar / windows / apps`。

## 已知坑（都是实测踩出来的）

| 现象 | 原因 | 绕法 |
|------|------|------|
| 面板明明是开的，`AXPress` 之后却「等不到面板」 | 状态项的 AXPress 是 **toggle**，开着再按是关掉 | `openPanel` 先查现况，已可见直接复用（输出 `panel already open`） |
| 点了 tab 却没切页 | AX 里 tab 按钮坐标恒为脏值（y=954）；纵向偏移取 20pt 落在高亮带外 | 坐标按面板 bounds 现查换算，纵向 35pt；切完读 `value=已选中` 校验 |
| 面板收起了，`assert window --gone` 仍说「还在」 | 收起后系统把窗口留在列表里，标成 `onscreen=true alpha=0 1x1` | 可见性判据统一为「onscreen && alpha>0.5 && 宽高≥2」 |
| 截图报 `could not create image from window` | `screencapture -l` 对部分窗口拿不到图 | 自动回退矩形截图并标 `rectFallback` |
| 刚打开面板就截图，图里半张面板 | 开合动画中间态（254×243 → 346×331） | 等「可见性不变 + 尺寸连续两次一致」再动 |
| `nmcli key` 按了没反应 | 合成键盘只送给前台进程 | 加 `--app 一览`（先激活再按）；或用 `click` 走 AXPress |
| AX 里找不到面板内容 | 面板 `NSPanel` 不在 `AXWindows` 里，从 app 根不可达 | nmcli 内部在面板 bounds 上做命中测试再沿父链爬到 `AXPopover`，作为额外根遍历 |

## 平台与能力限制

- 只能跑在 macOS（用 AppKit / AX / CGWindowList / `screencapture`）；
- 需要真实登录会话（锁屏 / 无头 CI 里没有窗口服务器，取不到窗口与像素）；
- 自绘面板里**没有 AX 元素**的区域（如 tab 条、卡片行内部）只能坐标点击，坐标按版式事实换算，
  版式改了就跟着改 `PanelGeometry`；
- 菜单面板的剪贴板页只做「行 hover 高亮」验收；卡片与底部详情区属于**独立的剪贴板面板**
  （`⌘⌥V` 唤起，另一个 `NSPanel`），不在菜单面板里，需要单独脚本覆盖；
- 合成键盘能否触发 Carbon 全局热键取决于前台进程的输入上下文，nmcli 只保证「发给前台 app」；
  实测对 `⌥⌘V`（剪贴板面板）/ `⌃⇧S`（截图）这类 Carbon 热键没有反应，需要时请用 AX 或坐标点击驱动；
- 同名多实例不会自动处理：`scenario` 只在 stderr 打一行警告（列出全部 pid），
  要精确指定就把它当 `app` 参数传 pid——nmcli 从不杀进程。

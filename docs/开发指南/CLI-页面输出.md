# CLI 页面输出（nmcli page）

> **何时阅读：** 要给运行中的「一览」截图取证 / 验收某个页面（菜单面板分页、设置分类、剪贴板历史浮层）时。

## 它替代了什么

改造前这类取证靠一批 `NM_*` 环境变量探针：另起一个 app 实例 → 离屏渲染 → `exit(0)`。
问题是它**只能在一个没人用的实例里跑**：

- 用户手上那个进程帮不上忙，取证必须先杀掉它（或另起一份实例争同一个数据库与全局热键）；
- 跑完少一个进程，脚本里还得再拉起来；
- 出的是「构造函数拼出来的页面」，不是用户眼前的真页面，布局与数据都可能对不上。

现在的通道对**已在运行的进程**发一条命令：app 打开页面 → 回执窗口号 → CLI 按窗口截图。
不重启、不退出、不读环境变量、不改用户偏好。

## 命令表

```bash
nmcli page list                                     # 列出可用目标
nmcli page open clipboard                           # 只打开，不截图
nmcli page shot --out /tmp/clip.png --target clipboard
nmcli page shot --out /tmp/token.png --target menu.token
nmcli page shot --out /tmp/settings.png --target settings.clipboard
nmcli page shot --out /tmp/now.png                  # 默认 target=current：只截当前已可见页面
```

选项：

| 选项 | 含义 |
|------|------|
| `--out <file>` | 必填（`shot`），PNG 落盘路径，目录不存在会自动建 |
| `--target <target>` | 目标页面，缺省 `current` |
| `--timeout <ms>` | 等 app 回执的上限，默认 5000 |

## 目标

| target | 页面 |
|--------|------|
| `current` | 不切换，直接输出当前最上层可见窗口 |
| `clipboard` | 屏幕底部的剪贴板历史浮层 |
| `menu` | 菜单面板（保持当前分页） |
| `menu.network` / `menu.transfer` / `menu.credits` / `menu.token` / `menu.system` | 菜单面板指定分页 |
| `settings` | 统一设置窗口（保持当前分类） |
| `settings.<分类>` | 设置窗口指定分类（`general` / `appearance` / `providers` / `clipboard` / `capture` / `transfer` / `notifications` / `token` / `permissions` / `system` / `about`） |

## 链路

1. nmcli 生成 request id，投分布式通知 `com.bsfeng.yilan.cli.page`（`target` / `request`）；
2. app 侧 `CLIPageBridge`（`Sources/NetworkMonitor/CLI/`）收到后按 target 打开页面；
3. app 回执 `com.bsfeng.yilan.cli.page.done`，带 **windowNumber**；
4. nmcli 等窗口尺寸连续两次采样一致（面板有开合动画），再 `screencapture -l<id>`；
5. 输出 `<路径> <宽>x<高> <字节>B [<mode>]`，mode 为 `window` 或 `rectFallback`；后者会再补一句 `(via rect fallback)`——说明系统不让按窗口抓，图里会多出面板阴影外的背景（见 `Sources/nmcli/Capture.swift:103-106`）。

## 限制与已知行为

- **目标 app 必须在运行**：nmcli 从不替你启动实例（两份实例会争同一个数据库与全局热键）。
- **需要屏幕录制权限**：由发起 nmcli 的终端持有；`nmcli shot` 自检可先验证。
- **菜单面板可能走 `rectFallback`**：`screencapture -l` 对 layer=25 的 popover 实测会失败，此时按 `CGWindowList` 现查 bounds 矩形截图。
- **只输出 UI，不输出数据**：要断言数值口径请用 TestRunner 里的纯函数测试，不要把截图当数据源。

## 加一个新页面

1. `NetworkMonitorUI/CLIPageTarget.swift:13`：`CLIPageTarget` 加 case——**只有新增一类窗口（如独立浮层）才加**，菜单分页与设置分类已由 `menu.<tab>` / `settings.<分类>` 覆盖；
2. 同一文件 `:92` `CLIPageChannel.knownMenuTabIDs` / `:95` `knownSettingsSectionIDs`：让 `nmcli page list` 能列出来（与 App 层的枚举同源，改枚举时一起改）；
3. `NetworkMonitor/CLI/CLIPageBridge.swift:42` `handle(rawTarget:request:)`：新 case 里把「怎么打开页面」与「算出目标 windowNumber」一起写掉；
4. 页面在独立窗口里时**不给控制器加只读属性**（同族行数门禁只允许变小）：照剪贴板浮层的做法，在 `NSApp.windows` 里按类型找可见窗口（`CLIPageBridge.swift:49-53`）；
5. 在 `NetworkMonitor/Sources/TestRunner/CLIPageTargetTests.swift` 补 `CLIPageTarget.parse` 的解析用例（纯逻辑，不需要起真机），并确认 `TestSuites+Pane.swift` 已登记。

## 读旧文档时撞见的 `NM_*` 探针（对照表）

`docs/设计/`、`docs/调研/`、`docs/踩坑/` 里的历史记录常写「用 NM_XXX 取证」。那批探针**已全部删除**
（`Sources/NetworkMonitor/Debug/` 整目录 + 各 `+Snapshot` / `+Evidence` / `*Probe` 扩展 + `SnapshotClock`），
今天再设这些环境变量不会有任何反应，也不要在新代码里复活它们：

| 已删除 | 当时做什么 | 现在用什么 |
|--------|-----------|-----------|
| `NM_SNAPSHOT_DIR` + `NM_SNAPSHOT_FREEZE` / `NM_SNAPSHOT_SYSTEM_MODE` / `NM_SNAPSHOT_WIFI_MODE` / `NM_SNAPSHOT_CLIPBOARD_*` | 离屏渲染菜单面板 / 设置页各页成 PNG；`FREEZE` 冻结时钟让两次跑逐字节一致 | `nmcli page shot --out <file> --target menu.<tab>` / `settings.<分类>`：截**真页面** |
| `NM_SHOW_PANEL` / `NM_EVIDENCE_TAB` / `NM_FORCE_APPEARANCE` / `NM_FORCE_EMPTY` | 让 app 自己展开 popover 停在指定分页、强制浅深或空态，供 `screencapture` 抓真实窗口 | 同上：开页面与回执窗口号已由通道负责，浅深由系统外观决定 |
| `NM_DISPLAY_EVIDENCE` / `NM_EVIDENCE_SUITE` | 逐项写偏好验证「设置真的生效」，偏好写隔离 suite 不污染用户 | 已删除；偏好热生效的回归走 TestRunner 的纯逻辑断言（如 `SettingsOrderTests`） |
| `NM_PANEL_PIN_PROBE` / `NM_PANEL_PIN_TRACE` / `NM_MEASURE_PANEL_OPEN` | 逐帧打印面板 frame、量展开宽度 | 已删除；面板几何由 `Sources/nmcli/PanelGeometry.swift` 直接读真实窗口 |
| `NM_SNIP_TOOLBAR_SNAPSHOT_DIR` / `NM_SNIP_OVERLAY_SNAPSHOT_DIR` / `NM_SNIP_CROP_PROBE` / `NM_SNIP_VISIBLE_PROBE` / `NM_SNIP_DOCK_PROBE` / `NM_SNIP_*_DEMO` | 截图工具条与覆盖层的离屏渲染、裁剪像素逐点比对、Dock 条目自证 | 已删除；截图链路要开覆盖层，`nmcli page` 不覆盖它，改真机手测 + `TestRunner/SnipGeometryTests.swift` 等纯函数断言 |
| `NM_DRAWN_PROBE` / `NM_DRAWN_INTERACTION_PROBE` / `NM_CLIPBOARD_CARD_PROBE` | 自绘组件的离屏样例图与交互自证 | 已删除；交互自证改用 `nmcli click` / `nmcli hover` + `nmcli shot` |
| `NM_TOKEN_AUTOINDEX_PROBE` / `NM_WATCHDOG_STALL_MS` / `NM_UPDATE_PROBE` / `NM_UPDATE_PROBE_URL` | 打印自动索引轮次、人为卡主线程、造更新状态并出关于页快照 | 已删除；手动跑索引走设置页「Token 用量 → 按来源重新扫描」，更新链路自证走 TestRunner 的 `UpdateInstallSandbox` |

## 与「快照冻结」的关系

旧的 `NM_SNAPSHOT_FREEZE`（冻结时钟 + 固定 fixture 做逐像素回归）已随探针一并移除。
逐像素回归若还要做，基座应改为「同一份真实页面 + 固定窗口 id + 固定外观」，而不是给生产代码注入假数据。

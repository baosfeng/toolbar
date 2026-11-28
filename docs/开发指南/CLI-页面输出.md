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
5. 输出 `路径 宽x高 字节 [mode]`，mode 为 `window` 或 `rectFallback`（后者说明系统不让按窗口抓，图里会多出面板阴影外的背景）。

## 限制与已知行为

- **目标 app 必须在运行**：nmcli 从不替你启动实例（两份实例会争同一个数据库与全局热键）。
- **需要屏幕录制权限**：由发起 nmcli 的终端持有；`nmcli shot` 自检可先验证。
- **菜单面板可能走 `rectFallback`**：`screencapture -l` 对 layer=25 的 popover 实测会失败，此时按 `CGWindowList` 现查 bounds 矩形截图。
- **只输出 UI，不输出数据**：要断言数值口径请用 TestRunner 里的纯函数测试，不要把截图当数据源。

## 加一个新页面

1. `NetworkMonitorUI/CLIPageTarget.swift`：`CLIPageTarget` 加 case（或复用 `menu.<tab>` / `settings.<section>` 这种带参数形式）；
2. 同一文件 `CLIPageChannel.knownMenuTabIDs` / `knownSettingsSectionIDs`：让 `nmcli page list` 能列出来（与 App 层的枚举同源，改枚举时一起改）；
3. `NetworkMonitor/CLI/CLIPageBridge.swift`：`handle(target:)` 里接上「怎么把页面打开」并返回目标窗口号；
4. 页面若在独立窗口里，给它的控制器补一个 `windowNumberForCLI` 只读属性。
5. 在 `TestRunner` 里补 `CLIPageTarget.parse` 的解析用例（纯逻辑，不需要起真机）。

## 与「快照冻结」的关系

旧的 `NM_SNAPSHOT_FREEZE`（冻结时钟 + 固定 fixture 做逐像素回归）已随探针一并移除。
逐像素回归若还要做，基座应改为「同一份真实页面 + 固定窗口 id + 固定外观」，而不是给生产代码注入假数据。

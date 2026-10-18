# 05 验收记录（骨架轮：只记 P0 / 阻塞项）

日期：2026-10-17 · 阶段 3（骨架发散，免审查轮）

## verify 结果（`odops verify <file> --template web-prototype --platform desktop`）

| 版本 | 自包含 | CSS 内联 | 6 变量 | 无裸色值 | data-od-id | accent 预算 | 画布 320 | anti-slop lint | 结论 |
|---|---|---|---|---|---|---|---|---|---|
| a.html | ok | ok | ok | ok | ok（7 区块） | 0 次 | ok | 干净 | 通过 |
| b.html | ok | ok | ok | ok | ok（6 区块） | 0 次 | ok | 干净 | 通过 |
| c.html | ok | ok | ok | ok | ok（4 区块） | 0 次 | ok | 干净 | 通过 |

唯一 warn（三版相同、非阻塞）：`:root` 只声明了骨架阶段 6 个占位变量，缺 47 个官方 schema 槽位 —— **阶段 6 填色时整段逐字粘贴 apple 包的 56 槽位**，届时该 warn 消失。

**P0 / 阻塞项：无。**

## 未覆盖（骨架阶段有意不做）

- 渲染层度量（`--browser`：点击区 / 对比度 / 溢出）——等阶段 6 上色后统一跑；
- 深色态实机核对——`prefers-color-scheme` 只做了变量重绑占位；
- 交互（hover / focus-visible / 键盘）——阶段 5；
- 人工 checklist 的 P1/P2（一个 decisive flourish、section rhythm 等）——骨架阶段不适用。

## 人工目视（3 版并排截图 `03-compare.png`）

- 三版内容均完整落在 320×600 内，无裁切、无横向滚动；
- 真实数据齐全：网速、今日流量、IP/Wi-Fi、5 条进程、6 天流量、4 个入口；
- a 版保留 NSMenu 语言（无卡片、分隔线、右对齐快捷键、勾选态）；b 版卡片层次；c 版磁贴密度 —— 差异是结构级，不是配色级。

## 待办（带进下一阶段）

1. 阶段 6：`:root` 换成 apple 56 槽位；语义色需要派生文字级（`--success`/`--warn` 压白底 12px 只有 3.03:1 / 4.44:1，不达 4.5:1，见 `02-style.md`）。
2. 阶段 6：圆角 / 材质 / 阴影定档（macOS Sonoma 浮层观感）。
3. 阶段 5：进程行在 18pt 行高下的 hover 命中区与键盘可达性，需要 `--browser` 实测。

---

# r2 轮（tab 结构，2026-10-17）

## verify 结果（`odops verify <file> --template web-prototype --platform desktop`）

| 版本 | 自包含 | CSS 内联 | 6 变量 | 无裸色值 | data-od-id | accent 预算 | 画布 320 | anti-slop lint | 结论 |
|---|---|---|---|---|---|---|---|---|---|
| r2/t1.html | ok | ok | ok | ok | ok（3 区块） | 0 次 | ok | 干净 | 通过 |
| r2/t2.html | ok | ok | ok | ok | ok（3 区块） | 0 次 | ok | 干净 | 通过 |
| r2/t3.html | ok | ok | ok | ok | ok（3 区块） | 0 次 | ok | 干净 | 通过 |

唯一 warn 与 r1 相同（`:root` 只有骨架 6 个占位变量，缺 47 个 apple 槽位），非阻塞，阶段 6 整段粘贴消除。

**P0 / 阻塞项：无。**

## r2 交互实测（agent-browser，session `proto-r2`）

三版 × 三个 tab 逐个真点击，结果：

| 版本 | 点击「剪贴板」 | 点击「系统」 | 回到「网络」 | 面板溢出 |
|---|---|---|---|---|
| t1 | 可见 pane=clip，选中项=剪贴板 | 通过 | 通过 | 无 |
| t2 | 可见 pane=clip | 通过 | 通过 | 无 |
| t3 | 可见 pane=clip | 通过 | 通过 | 无 |

- 切换后仅目标 pane 可见（`hidden` 属性），`aria-selected` / `tabindex` 同步；额外支持 ←/→ 键盘切换。
- 三个 pane 的内容高度实测：网络 303px、剪贴板 224px、系统 132px —— 面板 `max-height:600px` 自适应，均无滚动。
- **未覆盖**：真机浮层里的系统级材质（vibrancy）、鼠标悬停态、深色态实机 —— 属阶段 6；对比度与点击区未跑 `--browser`。

## r2 待办（带进下一阶段）

1. 选定版后清理：落选两版 + `03-r2-compare.{html,png}` + r1 的 a/b/c 与 `03-compare.{html,png}`（先列显式路径）。
2. 阶段 6：`max-height:600px` 下的自适应高度与 macOS 浮层真实观感（圆角 / 材质 / 阴影）一起验证。
3. tab 切换状态要覆盖「进程在跑 vs 空闲」「剪贴板为空」等空态 —— 阶段 5。

---

# 阶段 4–8（t1 选定后，2026-10-17）

## 各阶段产物与 verify

| 阶段 | 产物 | verify 结果 |
|---|---|---|
| 4 填充 | `04-fill.html` | P0 全过（内容/空态补齐，仍灰阶） |
| 5 交互 | `05-interaction.html` | P0 全过；交互实测见下 |
| 6 填色 | `06-color.html` | `:root` = 官方 56 槽完整粘贴 ok / 无裸色值 ok / accent 预算 0（accent 只用于选中 tab 与焦点环） |
| 7 动效 | `07-motion.html` | P0 全过 |
| 8 原型 | `08-prototype.html` | `--browser` 见下 |

## 08 `odops verify --template web-prototype --platform desktop --browser`

- 单文件自包含 ok · CSS 内联 ok · 6 语义变量 ok · **官方 56 槽完整粘贴 ok** · 无裸色值 ok
- 3 个顶层区块 `data-od-id` 全覆盖 ok · 强调色预算 0 次 ok · 画布 320 对齐 brief ok
- 官方 anti-slop lint（--fail-on p1）干净 ok
- **无横向溢出 ok** · **文本对比度达标（正文 4.5:1 / 大字 3:1）ok**
- warn：5 个交互元素高度 <44px（桌面平台判 warn，触屏才是 P0）。**口径更正（r4）**：工具报「5 个」但只列出前 4 个标签；实际 5 个 = 3 个分段 tab（26px）+ 2 个演示切换按钮（25px）。桌面鼠标目标 25–26px 是 macOS 常态，**有意保留**
- warn：<14px 文字 8 处（11–12px）—— 320pt 密集面板的必然选择，见「有意偏离」

**P0 阻塞项：0。**

> 注：verify 输出没有给出 `screensScanned / taps / fonts / contrast` 计数（本版本 odops 不打印），所以这几项按「未覆盖」记，不按「全绿」记。

## 交互实测（agent-browser，session `proto-author`）

| 行为 | 实测结果 |
|---|---|
| tab 点击切换（三版 3 tab） | 通过，`aria-selected` 与 pane 同步 |
| ←/→ 键盘切换 | 通过（`keydown` 处理 + 焦点转移） |
| 剪贴板条目点击 | 显示「已复制」，**1.6s 后回退**为原类型标签（实测 1.7s 后读回「链接」） |
| 开机自启动 | `aria-checked` true→false、勾选图标隐藏、文案「已开启→已关闭」、toast 同步 |
| 剪贴板设置… / 退出 | 均有 toast 交代，无死点击 |
| 空态切换（演示件） | 「有数据 / 空态」两态互斥，剪贴板与进程各一套空态 |
| 深浅色 | `prefers-color-scheme` 重绑语义 token，浅色/深色截图各一张 320×600 |

## 模版 checklist 逐条（P0）

| 项 | 结论 |
|---|---|
| 无 `:root` 外裸色值 | 通过（深色源值也放在 `:root`） |
| 标题用 `font-display` | 通过（SF Pro Display 栈） |
| accent ≤2 处/屏 | 通过（选中 tab 文字 + 焦点环） |
| 无紫渐变 | 通过（无渐变） |
| 无 emoji 图标 | 通过（全部 inline SVG 单线 1.5px 圆角端点） |
| 无编造指标 | 通过（全部来自用户给的菜单数据） |
| 无填充文案 | 通过 |
| 无远程图片依赖 | 通过（无图片） |
| `data-od-id` 覆盖顶层 section | 通过（3 个） |
| 窄屏回流 | 不适用（brief: responsive=no，固定 320） |
| 无 `scrollIntoView` | 通过（无调用） |

## 有意偏离

1. **菜单字号 12–13px**：不套 apple `--text-base:17`（营销页尺度），见 `02-style.md`。
2. **`--orange` / `--dark-orange`**：apple 包无 systemOrange 槽位，`--warn` 是黄色压小字偏橄榄；按项目 UI 规范补语义槽。
3. **深色原始值放第一个 `:root`**：为满足「裸色值只在 `:root`」的机械检查，`@media` 只做语义重绑。
4. **浮层进入 120ms**：低于 craft 的 200–300ms 建议，lead 指定；位移仅 2px，120ms 更贴 native 手感。
5. **点击区 25–26px**：桌面平台 warn 项，macOS 菜单项常态高度。
6. **`:has()` 选择器**：用 `.v:has(.tri-down)` 给下行跑文字级色，依赖 Chrome 105+ / Safari 15.4+；实现端改 Swift 后无此问题。

## 未跑 / 未覆盖

- 真机浮层 vibrancy 材质与圆角裁剪（Safari/AppKit 与 Chrome 渲染不同）；
- `reduced-motion` 只在 CSS 层兜底，未在浏览器里用媒体模拟复核；
- 深色下逐个 token 的计算后对比度未单独跑工具，仅依赖 verify 的浅色判定 + 目视。

## 待办（给实现 agent）

1. 按 `07-contract.md` 排除演示件：**2 个带 `demo-only:*` 标记的部件**（版本标签、状态切换条）+ 2 项样式/动画层隔离（`body` 灰底留白、`panel-in` 改由 NSWindow 动画）。实现端由 NSWindow 承载，原型里的 24px 外留白与居中不搬。
2. 剪贴板条目来源要接 `NSPasteboard` 变更通知，相对时间每秒刷新（相对时间文本不进 tabular-nums）。
3. 开机自启动走 `SMAppService`，失败时 toast 报错文案。
4. 进程列表空态与剪贴板空态要接真实数据源。


---

# r4 定稿前修复（2026-10-17）

## verify 复跑

`odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser`

- **exit code：0**
- **PASS：12 · WARN：2 · FAIL：0**
- 2 条 warn 与 r3 相同且均为有意保留：点击区 25–26px（5 个，工具只列出前 4 个）、11–12px 小字。

## 修复清单

| # | 级别 | 问题 | 修法 |
|---|---|---|---|
| 1 | P1 | toast 遮住底部「退出 / 剪贴板设置…」点击 | `.toast` 加 `pointer-events:none` |
| 2 | P1 | 「近 7 日流量」标题与 6 条数据冲突 | 标题改「近 6 日流量」+ 日期区间 10/11—10/16，与真实菜单（今日单独一行 + 逐日 entries）对齐 |
| 3 | P1 | 「剪贴板设置…」挂了 ⌘⇧V（真实菜单无此快捷键） | 改 `⌘,`（ClipboardPanelController.swift:19）；⌘⌥V 是唤起面板，不挂设置项 |
| 4 | P2 | 空态时计数仍写死 5 个 / 5 条 | 计数改为 `#procs-count` / `#clips-count`，空态归零 |
| 5 | P2 | hover 覆盖选中 tab 的强调蓝 | `.seg button:not([aria-selected="true"]):hover` |
| 6 | P2 | 示例 URL 含 AI 品牌字样 | 换成 `https://developer.apple.com/documentation/appkit` |
| 7 | P2 | tab ↔ pane 缺 ARIA 关联 | tab 加 `aria-controls`，pane 加 `role="tabpanel"` + `aria-labelledby` |
| 8 | P2 | 「退出 NetworkMonitor」与真实菜单项不符 | 改「退出」（保留 ⌘Q） |
| 9 | P2 | checklist 口径：warn「5 个」只列 4 个、演示件「3 个」 | 已按实际上限更正（见上） |

## 未动（按审查结论保留）

点击区 25–26px、11–12px 小字、body 灰底与 24px 外留白（**口径更正 r7**：320 视口下面板正好贴边、实测不裁切；只有视口 <320px 时才会左右裁，预览裁切属预览环境，实现端由 NSWindow 承载）。

## 截图

`shots/08-light.png`（网络页浅色）· `shots/08-dark.png`（网络页深色）· `shots/08-light-clip.png`（剪贴板页浅色）· `shots/08-light-sys.png`（系统页浅色），均 320×600。


---

# r6 定稿（v2 + 真实 App 图标，2026-10-17）

## verify

`odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser`
- **exit code：0**
- **PASS 12 · WARN 2 · FAIL 0**

warn 仍是保留项：5 个交互元素 28px / 25px（桌面鼠标目标）、<14px 文字（密集面板）。

## 本轮改动

1. 进程 5 项换成本机真实 App（Safari / Google Chrome / Terminal / Notes / Finder），图标 `data:image/png;base64` 内嵌（48×48 源图 → 20×20 显示，圆角 4px、`aria-hidden`、不裁切）。
2. 剪贴板条目 + 类型图标（链接 / 命令 / 文本）、系统页 + Wi-Fi / 勾选 / 电源图标、三个 tab + 小图标；全部 inline SVG 1.5px 线性、`currentColor`、深浅色跟随。
3. 补回 r4 修项：toast `pointer-events:none`、近 6 日口径、`⌘,`、空态计数归零、hover 不盖选中、`aria-controls`/`role="tabpanel"`/`aria-labelledby`、示例 URL、退出文案。
4. v2 语义补齐：sparkline 数据源注释、今日进度条「占今日总量 80% / 20%」、进程占比条「以列表最大进程为 100% 基线」。

## 未覆盖 / 待办

- 图标为静态预览素材（base64），实现端按 `NSWorkspace.shared.icon(forFile:)` 动态取图，见 `07-contract.md`。
- 真机 vibrancy、`prefers-reduced-motion` 媒体模拟未复核。
- 柱状图 x 轴显示日号（11–16），实现端可改为完整日期。


---

# r7 复审修复（2026-10-17）

## verify

`odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser`
- **exit code：0** · **PASS 12 · WARN 2 · FAIL 0**

## P1 修复与验证证据

| # | P1 | 修法 | 验证 |
|---|---|---|---|
| 1 | 剪贴板条目点击回归 | 恢复 `data-clip` / `role="button"` / `tabindex="0"` 三个属性 | 真点击 `[data-clip="1"]` → 「已复制」；1.7s 后读回「链接」✓ |
| 2 | 柱状图比例失真 | `.bar` 改 `grid-template-rows: 12px 64px 12px`，柱区固定 64px，`height:calc(var(--h) * 0.64px)`，去掉百分比 | 实测 6 根：**35.19 / 20.47 / 48 / 27.52 / 64 / 23.03 px**（5.6 最高）✓ |
| 3 | 自启动勾选不随状态 | 勾选 SVG 加 `#launch-check`，JS 切换 `visibility`；关闭态加 `.off` 类（`--muted`） | 关闭后 `aria-checked=false`、文案「已关闭」、`visibility:hidden`、class `on off` ✓ |

## P2 修复

4. 空态演示：剪贴板列表补 `data-clip-list`，空态切换生效（实测 clips 隐藏、空态显示、计数「0 条」）。
5. 系统页拆成「IP 地址 / Wi-Fi」两行，各带图标（IP 用矩形+线图标、Wi-Fi 用波形图标）。
6. `.toggle .on.off{color:var(--muted)}`：关闭态不再用强调蓝。
7. Terminal 图标深色衬底：`@media (prefers-color-scheme: dark){ .app-icon.term{background:rgba(255,255,255,.10);box-shadow:0 0 0 1px var(--border);} }`，其余 4 个不变。
8. 更正「320 视口裁 24pt」说法（见上）。

## 截图

6 张主截图（网络/剪贴板/系统 × 浅深）+ 2 张自启动关闭态（`08-light-sys-off.png` / `08-dark-sys-off.png`）+ 1 张空态（`08-light-clip-empty.png`）。

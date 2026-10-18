# 07 契约：演示件与产品件的边界

原型 `08-prototype.html` 是单文件交付件。下面把「为评审 / 演示存在」的部件与「要进产品」的部件分开，
实现时按表机械排除 —— 不要凭记忆判断。

## 演示件清单（不进产品）

| 部件 | `data-od-id` | 是否进产品 | 隔离方式 |
|---|---|---|---|
| 页头版本标签（"NetworkMonitor · 菜单栏面板原型 · 顶部细分段"） | `demo-only:variant-tag` | 否 | 实现时不渲染；纯 HTML 一行，删掉不影响任何功能 |
| 「有数据 / 空态」状态切换条 | `demo-only:state-toggle` | 否 | 默认不在产品中出现；若开发期需要看空态，按两层闸：构建层排除 + 运行层默认关闭（连点「关于」里的版本号解锁），不要常驻可见 |
| 桌面灰底 + 24px 外留白 + 页面居中 | —（`body` 样式） | 否 | 真实浮层由 NSWindow / NSPanel 承载，不需要页面底色与居中；`body` 的背景与 padding 全部丢掉 |
| `panel-in` 进入动画（120ms） | —（`.panel`） | **是**（但由系统层实现） | Swift 侧用 NSWindow 出现动画 / `NSAnimationContext`，不照搬 CSS keyframes |

## 产品件（要进产品）

| 部件 | `data-od-id` | 说明 |
|---|---|---|
| 顶部细分段控件 | `t1-seg` | 三段：网络 / 剪贴板 / 系统；`aria-selected` ↔ 选中态，←/→ 键切换 |
| 内容区 | `t1-content` | 三个 pane 互斥显示 |
| 网络页 | `pane-net` | 实时速率、今日流量、活跃进程 5 行、近 7 日 6 天 |
| 剪贴板页 | `pane-clip` | 5 条条目 + 相对时间 + 类型标签 + 「剪贴板设置…」入口 |
| 系统页 | `pane-sys` | IP / Wi-Fi / 开机自启动（可切）/ 退出 ⌘Q |
| 空态 ×2 | `[data-empty="clip|procs"]` | 剪贴板空 / 进程无流量空；各一句话 + 单线 SVG |
| 状态提示 toast | `#toast` | 复制反馈 / 设置入口 / 退出确认的轻提示（2s） |

## 状态与交互映射（给实现 agent）

| 原型行为 | 产品对应 |
|---|---|
| 点击 tab / ←→ | 切换选中 pane，保留焦点 |
| 点击剪贴板条目 → "已复制" 1.6s 回退 | 写入剪贴板 + 行内短暂反馈 |
| 点击开机自启动 → 勾选态切换 + toast | `SMAppService` 注册 / 注销，失败时 toast 报错 |
| 点击「剪贴板设置…」→ toast | 打开设置面板（原型未实现） |
| 点击「退出」→ toast | `NSApplication.terminate` |

## 有意偏离（记录在案）

1. `--orange` / `--dark-orange` 是 apple 包没有的槽位（apple 的 `--warn` 是黄色，压小字偏橄榄）——按项目 UI 规范补的 systemOrange 语义槽，深色源值同样只出现在 `:root` 一次。
2. 两套深色原始值（`--dark-*`）放在第一个 `:root` 里而非 `@media` 内，是为了满足「裸色值只能出现在 `:root`」的机械检查；`@media` 只做语义重绑。
3. 菜单字号用 12–13px，不套 apple 的 `--text-base:17`（营销页尺度），见 `02-style.md`。
4. `panel-in` 120ms 低于 craft 建议的 200–300ms 进入时长 —— lead 指定值，浮层小、位移 2px，120ms 更贴 native 手感的观感。


---

## 图标素材（r6 补充）

| 类型 | 原型内 | 是否进产品 | 实现端做法 |
|---|---|---|---|
| 进程 App 图标 | 5 张 48×48 PNG 以 `data:image/png;base64` 内嵌，20×20 显示 | **否**（静态预览素材） | `NSWorkspace.shared.icon(forFile: appBundlePath)` 按进程动态取图，不打包任何 App 图标 |
| 类型/功能图标（链接、命令、文本、Wi-Fi、勾选、电源、tab 三个） | inline SVG，1.5px 线性、圆角端点、`currentColor` | 是 | Swift 侧改用 SF Symbols 等价符号，颜色跟随 `NSColor` 语义色 |
| 演示壳（版本标签 + 有数据/空态） | `demo-only:*` 标记 | 否 | 按本文件「演示件清单」隔离 |

> 内嵌图标合计约 24 KB（5 × 48×48 PNG 转 base64），单文件原型 46 KB；不引任何外部资源。


## 画布尺寸口径（r11 补充）

- 菜单栏面板：320×600（`00-brief.md`）。
- 剪贴板历史面板：640×260（`00-brief-clipboard.md`），**与菜单面板不同源**，两者各自按自己的画布实现；不要用 320 的宽度去裁剪贴板面板。

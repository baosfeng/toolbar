# r1 原型审查报告 — `.open-design/08-prototype.html`

- 审查对象：`.open-design/08-prototype.html`（macOS 菜单栏下拉面板，320 宽，顶部细分段 tab：网络 / 剪贴板 / 系统）
- 对照：`00-brief.md`（platform desktop · canvas 320x600 · responsive no · dark_mode required · zh-CN）· `07-contract.md` · `05-checklist.md` · `04-rounds.md`
- 审查日期：2026-10-17 · 审查人：proto-reviewer
- 取证环境：odops（daemon OK v0.24.1）· agent-browser 0.34.0，session `proto-reviewer`（收工只关本会话）
- 截图目录：`.open-design/reviews/shots/`（清单见文末）
- **结论：P0 = 0，P1 = 3，P2 = 10。机械门禁与作者「P0=0」判断成立；但 3 条 P1 里有 2 条用户一眼能看见/点到，建议修完再交用户拍板。**

---

## 一、必查项逐条结论

### 1. 独立复跑 `odops verify`（P0 = 0 属实 ✅）

命令与退出码：

```bash
odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser
# EXIT=0
```

完整输出（逐条）：

| # | 条目 | 结果 |
|---|---|---|
| 1 | 单文件自包含（无外部 script / link / img / 字体） | ok |
| 2 | CSS 内联 | ok |
| 3 | `:root` 含核心 6 个语义变量 | ok |
| 4 | `:root` 是官方 56 槽的完整粘贴 | ok |
| 5 | 所有颜色都走 token，无裸色值 | ok |
| 6 | 3 个顶层区块都有 `data-od-id` | ok |
| 7 | 强调色用法 0 次 | ok |
| 8 | 澄清单未要求响应式 → 固定画布交付 | ok |
| 9 | 画布宽与澄清单一致（320px） | ok |
| 10 | 官方 anti-slop lint（`--fail-on p1`）干净 | ok |
| 11 | 无横向溢出 | ok |
| 12 | 文本对比度达标（正文 4.5:1 / 大字 3:1） | ok |
| 13 | 5 个交互元素高度 <44px（桌面判 warn） | warn（`button(25px) button(25px) button(26px) button(26px)`） |
| 14 | <14px 文字（11–12px） | warn |

**FAIL = 0，PASS = 12，WARN = 2，退出码 0** → 作者 `05-checklist.md:95`「P0 阻塞项：0」**属实**。
两条 warn 均已在 `07-contract.md`「有意偏离」登记（菜单项 25–26px、12–13px 字号），桌面平台按 warn 处理，不升级。

> 覆盖度说明（按技能要求）：本版 odops **不打印** `screensScanned / taps / fonts / contrast` 计数，故这几项**不记「全绿」**；下文第 4 条用自写脚本补测了深色对比度（每页 11–25 个文本节点，见证据）。

### 2. 模版 checklist 人工过（作者覆盖度：P0 基本齐，P1/P2 未列）

`odops template web-prototype --file references/checklist.md`（EXIT=0）逐条核对：

| checklist 项 | 等级 | 实测 | 作者是否记录 |
|---|---|---|---|
| 无 `:root` 外裸色值 | P0 | 通过（`grep -nE "#[0-9a-fA-F]{3,8}"` 仅 `:root` 内；注释已去 hex） | 有 |
| 标题用 `var(--font-display)` | P0 | 通过（`h1,h2,h3{font-family:var(--font-display)}` 第 117 行） | 有 |
| accent ≤2 处/屏 | P0 | 通过（选中 tab 文字 + 焦点环） | 有 |
| 无紫渐变 | P0 | 通过（文件内无 `gradient`） | 有 |
| 无 emoji 图标 | P0 | 通过（`\p{Extended_Pictographic}` 零命中；图标全 inline SVG） | 有 |
| 无编造指标 | P0 | **发现数值自相矛盾**，见 P1-2 | 有（自评通过，实测不通过） |
| 无填充文案 | P0 | 通过（无 lorem / Feature One） | 有 |
| 真实世界指代用正确图片 | P0 | N/A（无任何图片） | **未列** |
| 无远程图片依赖 | P0 | 通过（无 `img` / `link` / `src`；唯一的 `http` 是剪贴板示例文本） | 有 |
| 内容图保比例不裁切 | P0 | N/A（无图） | **未列** |
| 顶层 `<section>` 都有 `data-od-id` | P0 | 通过（`t1-panel` / `t1-seg` / `t1-content`） | 有 |
| 窄屏回流 | P0 | 按 brief `responsive: no` 不适用 | 有（标 N/A） |
| 无 `scrollIntoView()` | P0 | 通过（文件内零命中） | 有 |
| P1 八条（one decisive flourish / section rhythm / 标题 <14 词 / lead 文本 / CTA 文案 / hover 态 / 数字 `.num` / 单一图片风格） | P1 | hover 态与 `.num` 通过；其余多为营销页项，320pt 面板 N/A | **仅记了 2 类** |
| P2 四条（`text-wrap` / `color-mix` / 磨砂 topnav / 系统字体） | P2 | `color-mix` 已用（符合）；其余 N/A | **未列** |

作者漏记：2 条图片类 P0（本产物 N/A，建议写明「不适用」以免被读成漏检）、P1 全部 8 条、P2 全部 4 条 → 记 P2-10。

### 3. 三个 tab 页内容（逐页截图，均不破版）

真实点击（`agent-browser click '[data-tab="clip"]'`）后逐页截图（元素截图，面板真实尺寸）：

| 页 | 面板实测尺寸 | 内容核查 |
|---|---|---|
| 网络 | 320×397 | 实时下行/上行、今日流量、活跃进程 5 行（`5 个` 与行数一致）、近 7 日 6 行 |
| 剪贴板 | 320×264 | 5 条（`5 条` 与行数一致）、相对时间递增、类型标签、`剪贴板设置…` 入口 |
| 系统 | 320×172 | IP、Wi-Fi、开机自启动（可切）、退出 |

- 无破版、无裁切、无横向滚动；最长剪贴板条目（39 字符）正确省略号截断（`scrollWidth 258 > clientWidth 204`）。
- 文案均为真实菜单语义（与 `MenuBarManager.swift:203/207/211` 的菜单项对得上），无编造功能。唯一编造是快捷键，见 P1-3。
- 空态可用（`light-04/05`），但头部计数不同步，见 P2-4。

### 4. 深色模式（`set media dark`，三页各一张）

```bash
agent-browser --session proto-reviewer set media dark     # EXIT=0
agent-browser --session proto-reviewer eval "matchMedia('(prefers-color-scheme: dark)').matches"
# true；:root --bg=#1c1c1e --surface=#2c2c2e
```

- 无浅灰遮罩错色：`@media` 只做语义重绑（第 93–113 行），深色原值全部在第一个 `:root`；面板底色、分隔线、hover/active 均正确转深（`dark-01/02/03`）。
- **对比度独立实测**（自写脚本：逐文本节点取 computed color + 向上找不透明背景，`color-mix` 走 canvas 归一化；浅/深 × 三页共 6 组）：

| 模式 / 页 | 文本节点数 | 最低对比度 | <4.5:1 项 |
|---|---|---|---|
| light / net | 25 | 4.66 | 0 |
| light / clip | 22 | 4.66 | 0 |
| light / sys | 11 | 4.66 | 0 |
| dark / net | 25 | 4.66 | 0 |
| dark / clip | 22 | 4.66 | 0 |
| dark / sys | 11 | 4.66 | 0 |

→ 深色对比度**达标**（作者 `05-checklist.md:140` 记为「未单独跑」，本次补上，结论通过）。
- 深色下选中 tab 的强调蓝 `#0a84ff` 压 `#1c1c1e` ≈ 4.6:1，刚过线，实现时不要把它调暗。
- 排查备注：初次深色截图曾见「系统」tab 一片浅灰，为 `transition: background` 150ms 过渡中的瞬时帧（等 400ms 后重拍消失），**不是缺陷**，已重拍。

### 5. AI / Token 残留（UI 文案零命中 ✅）

```bash
grep -niE "token|模型|会话|AI |工具调用|reasoning|用量|统计|分析|智能|deepseek|gpt|claude" .open-design/08-prototype.html
# EXIT=0
# 9:    /* apple 设计体系 token — odops style apple --tokens 的 56 个官方槽位（声明逐字，注释已去：
# 253:  ...<span class="txt">https://github.com/deepseek-ai</span><span class="kind">链接</span>...
```

- 第 9 行是 CSS 注释（token 说明），不是 UI 文案 → 合规。
- 第 253 行是剪贴板示例条目里的一个 GitHub URL，不是功能文案，但属 AI 痕迹（建议换掉，P2-7）。
- 页面内无 AI 分析 / Token 概览 / 24h 柱状图 / 历史用量 / 模型 / 工具调用 / 会话统计字样；`<title>` 干净；三个 tab 内无任何相关区块。

### 6. 交互真实可用（全部真点击 / 真按键，无 `el.click()`）

| 行为 | 命令 | 结果 |
|---|---|---|
| tab 点击切换 | `click '[data-tab="clip"]'` | `aria-selected` 与可见 pane 同步（`clip` 可见、`net/sys` hidden）✅ |
| ←/→ 键盘切换 | `focus '[data-tab="clip"]'` → `press ArrowRight` → `press ArrowRight` → `press ArrowLeft` | activeElement `clip→sys→net→sys`，可见 pane 同步，含首尾环绕 ✅ |
| 剪贴板条目「已复制」1.6s 回退 | `click '[data-pane="clip"] [data-clip="2"]'` | 立即 `已复制` → 1.7s 后回读 `命令`，`data-flash` 已清除 ✅ |
| 开机自启动勾选切换 | `click '#launch-row'` ×2 | `aria-checked true→false→true`、勾选图标 `visible→hidden→visible`、文案 `已开启→已关闭`、toast 同步 ✅ |
| 设置入口反馈 | `click '#settings-row'` | toast「剪贴板设置面板（原型未实现）」✅（键盘空格激活同样生效） |
| 退出入口反馈 | `click '#quit-row'` | toast「已请求退出 NetworkMonitor」✅ |
| toast 自动隐藏 | `sleep 2.2` 后读 | `hidden = true`（2s）✅ |
| 空态切换 | `click '[data-state="empty"]'` / `full` | 剪贴板列表↔空态、进程列表↔空态互斥切换 ✅ |
| hover 态 | `hover '[data-clip="3"]'` | 背景从透明变 `#f5f5f7` ✅ |

**唯一交互缺陷：toast 遮挡底部行 2 秒**，见 P1-1（`agent-browser` 明确报 `Element '#quit-row' is covered by <div#toast>`）。

### 7. 演示件隔离（HTML 与契约一致 ✅，脚本未登记）

```bash
grep -no 'data-od-id="demo-only:[a-z-]*"' .open-design/08-prototype.html
# 197:data-od-id="demo-only:variant-tag"
# 198:data-od-id="demo-only:state-toggle"
```

- HTML 内 2 个 `demo-only:*` 锚点 ↔ `07-contract.md:10-11` 表内 2 行，**一一对应**；其余 2 行（body 底色/留白、`panel-in`）本就无 `data-od-id`，靠选择器/类名定位，与表一致。
- **机械移除实测**：`eval "document.querySelectorAll('[data-od-id^=\"demo-only:\"]').forEach(e=>e.remove())"` 后 tab 切换、剪贴板点击、空态块仍正常（`paneCount:3`、`emptyBlocks:2`、无报错）；`reload` 后恢复。
- 缺口：演示脚本 `setState` 段（第 360–374 行）不在隔离表里。删掉两个演示元素后该段变惰性代码（无报错但仍在文件里）→ 记 P2-10（实现端整份 HTML 丢弃，不影响交付）。

### 8. 尺寸与溢出（320 无横向滚动，高度 ≤600 ✅）

```bash
# 视口 320
eval: {"vw":320,"scrollW":320,"clientW":320,"overflowX":false}
# 视口 400
eval: {"vw":400,"scrollW":400,"clientW":400,"overflowX":false}
```

| pane | pane 内容高 | 面板高 | 面板宽 | 内部溢出 |
|---|---|---|---|---|
| net | 357 | 397 | 320 | 无 |
| clip | 224 | 264 | 320 | 无 |
| sys | 132 | 172 | 320 | 无 |

- 面板 `max-height:600px` 未被触发（最高 397），无纵向/横向滚动，`body` 也无溢出。
- 300pt / 340pt 压力探测（浏览器内临时改宽，不改产物）：300 宽下 `pane scrollWidth 298 = clientWidth 298`，数值不折行（`.hero2 .val` 高度 24.2px 单行），排版不破。
- ⚠️ 预览陷阱（P2-6）：`body` 有 24px padding 且 flex 居中，320 视口下面板两侧各被裁 24pt，而 `scrollWidth` 检测**看不出来**（对称溢出不可滚动）。截图/自测请用元素截图或视口 ≥368 宽。

### 9. 数值一致性（发现 2 处硬伤）

| 原型展示 | 真实/应然 | 结论 |
|---|---|---|
| 今日流量 ↓12.5 GB ↑3.2 GB | 应等于「今天」那一行（`TrafficTracker.todayRx/tx`） | ❌ 与最近一天行（10/16 ↓2.0 GB ↑520 MB）冲突 |
| 「近 7 日流量」+ 6 行（10/11—10/16） | 真实菜单是「今日」+ `entries[1...]` 逐日（`MenuBarManager.swift:406-430`），标题写 7 日就该有 7 天 | ❌ 标题与行数不自洽 |
| 活跃进程 5 行 / 标题「5 个」 | 数量一致 | ✅ |
| 剪贴板 5 行 / 标题「5 条」 | 数量一致 | ✅ |
| IP 192.168.1.42、Wi-Fi「Home-5G」 | 示例值，语义与真实菜单项一致 | ✅（真实菜单文案为「IP / Wi-Fi / 总计」） |
| 退出 NetworkMonitor ⌘Q | 真实菜单项标题为「退出」，`keyEquivalent "q"`（`MenuBarManager.swift:211`） | ⚠️ 文案多了应用名，见 P2-5 |
| 剪贴板设置… ⌘⇧V | 真实：该菜单项**无**快捷键；唤起面板是 ⌘⌥V；⌘, 打开设置 | ❌ 编造快捷键，见 P1-3 |

---

## 二、问题清单

### P0 — 阻塞交付（打不开 / 破版 / 主流程不可用 / AI 残留文案）

**无。** `verify` 退出码 0（12 PASS / 2 WARN / 0 FAIL），三页均可打开、不破版、主流程（tab 切换 + 复制 + 开关）全部可用，AI/Token 功能文案零命中。

### P1 — 应修（用户能看见/点到，或不修会把错误带进实现）

**P1-1 toast 有 2 秒遮挡底部可点行，点击被吞**
- 证据：
  ```bash
  agent-browser --session proto-reviewer click '#launch-row'   # EXIT=0
  agent-browser --session proto-reviewer click '#quit-row'
  # ✗ Element '#quit-row' is covered by <div#toast> at its click point ...
  # 几何：quit {y:220,bottom:246} vs toast {y:216,bottom:246} → overlap:true，pointer-events:auto
  ```
  截图 `shots/light-06-sys-toast.png`：toast 整条盖住「退出 NetworkMonitor」。
- 定位：`.toast{position:absolute;left:10px;right:10px;bottom:10px;…}`（第 175 行，无 `pointer-events`）；`#toast`（第 280 行）；受影响行 `#quit-row`（第 277 行）、`#settings-row`（第 268 行）。
- 影响：系统页切完「开机自启动」后 2 秒内点不到退出；剪贴板页点完条目后可挡住「剪贴板设置…」。toast 是产品件（`07-contract.md:25`），实现时容易照抄成真缺陷。
- 建议：`.toast{pointer-events:none}`（保留 `aria-live` 朗读），或把 toast 抬到内容区上方/改为顶部。

**P1-2 「近 7 日流量」只有 6 天，且今日数值与最近一天冲突**
- 证据：HTML 第 238–248 行；标题「近 7 日流量 10/11 — 10/16」（第 239 行）但只列 6 条（10/11…10/16）；今日流量「12.5 GB / 3.2 GB」（第 216–218 行）与 10/16 行「2.0 GB / 520 MB」（第 246 行）无法自洽。
- 定位：`.days` 列表（第 240–247 行）、`.rowline` 今日流量（第 215–219 行）、`h2` 标题（第 239 行）。
- 真实产品：`buildTrafficSubmenu/updateTrafficSubmenu` 输出「今日 ↓… ↑…」+ `entries[1...]` 逐日（`MenuBarManager.swift:406-430`），`TrafficTracker.weekEntries` 是日期降序、今天在最前。
- 影响：用户对照真实菜单会直接看出「今日 12.5 GB」比「昨天 2.0 GB」还小；实现 agent 会把这个矛盾带进 UI。
- 建议：补 10/17（今天）一行使 7 行成立，且今日行数值 = 顶部「今日流量」；或把标题改成「近 6 日」。

**P1-3 「剪贴板设置… ⌘⇧V」是编造快捷键**
- 证据：
  ```bash
  grep -n "剪贴板设置" NetworkMonitor/Sources/NetworkMonitor/MenuBarManager.swift
  # 203: menu.addItem(menuItem(title: "剪贴板设置…", action: #selector(openClipboardSettings),
  #      ← menuItem 的 keyEquivalent 参数缺省为 ""，即无快捷键
  grep -n defaultPanelToggle NetworkMonitor/Sources/NetworkMonitor/Clipboard/GlobalHotKey.swift
  # 17: static let defaultPanelToggle = HotKeyCombo(keyCode: 9, modifiers: UInt32(cmdKey | optionKey))  # ⌘⌥V
  # ClipboardPanelController.swift:19  /// ⌘, 打开剪贴板设置
  ```
- 定位：第 268 行 `<span class="kbd">⌘⇧V</span>`。
- 影响：原型是给用户拍板 + 给实现 agent 的契约，写错快捷键会被照搬（且 `07-contract.md` 未列为“有意偏离”）。
- 建议：改成产品真实值（该行不显示快捷键；若必须给一个，⌘, 才是设置入口），或删除该 `.kbd`。

### P2 — 待办 / 记录类

1. **演示空态与头部计数打架**：空态下标题仍写「活跃进程 5 个」（第 221 行）、「最近复制 5 条」（第 251 行）。截图 `light-04/05`。定位：`setState()`（第 362–371 行）未同步计数文本。演示件不阻塞，但用户点「空态」时第一眼就是矛盾。
2. **hover 覆盖选中 tab 的强调色**：`.seg button[aria-selected="true"]{color:var(--accent)}`（第 186 行）在前，`.seg button:hover{color:var(--fg)}`（第 187 行）在后且同特异性 → 悬停选中项时蓝色变近黑（实测 `rgb(0,113,227)` → `rgb(29,29,31)`），“选中”提示被削弱。建议加 `[aria-selected="true"]:hover{color:var(--accent)}`。
3. **预览壳在 320 视口居中裁切**：`body{padding:24px; align-items:center}`（第 115–116 行）+ 面板固定 320 → 320 视口左右各裁 24pt，且 `scrollWidth` 检测不出来（对称溢出不可滚动）。`07-contract.md:12` 已声明 body 样式不进产品，故不影响实现；但**打开预览/截图请用视口 ≥368 或元素截图**（本报告截图均为元素截图）。
4. **演示数据含 AI 品牌 URL**：`https://github.com/deepseek-ai`（第 253 行）。不是 UI 功能文案、不触发第 5 条的合格判据，但用户已明确要清掉 AI 痕迹，建议换成中性示例（如 `https://github.com/apple/swift`），免得评审时被读成残留。
5. **退出文案与真实菜单不一致**：「退出 NetworkMonitor」（第 277 行）vs 真实菜单项「退出」（`MenuBarManager.swift:211`）。桌面菜单栏习惯省略应用名，建议对齐。
6. **示例日期陈旧**：10/11–10/16，而当前 2026-10-17；且「今日」没有对应行。建议用 `今天 / 昨天 / 10/15…` 相对标签，或按当前日期生成。
7. **上传列整列着橙色**：`.days .v:last-child{color:var(--up)}`（第 159 行）+ 每行上行值 → 6 行全是强调色，会稀释「今日 / 主指标」的视觉重心。建议只高亮今天一行或改用 `--muted`。
8. **a11y 语义不完整**：tab 无 `aria-controls`，pane 无 `role="tabpanel"` / `aria-labelledby`（第 204–207、210/250/270 行）。实现端转 AppKit 影响有限，但作为原型契约建议补。
9. **verify warn 数字与明细不符**（工具侧）：`odops` 输出「有 5 个交互元素高度 <44px」但只列 4 个；作者 `05-checklist.md:92` 照抄成 5 个。属工具统计口径问题，记一笔避免后续对账困惑。
10. **文档小出入**：`05-checklist.md:144` 写「按 07-contract.md 排除 3 个演示件」，`07-contract.md` 实际是 2 个带 `data-od-id` 的演示件 + body 样式 + `panel-in`（4 行）；且演示脚本 `setState` 段（第 360–374 行）未写进隔离方式。另：作者 checklist 表未列 2 条图片类 P0（N/A）与 P1/P2 全部条目（见本报告第 2 条）。

---

## 三、截图清单（`.open-design/reviews/shots/`）

| 文件 | 内容 | 用途 |
|---|---|---|
| `light-01-net.png` | 网络页（浅色，320×397） | 三页目视之一 |
| `light-02-clip.png` | 剪贴板页（浅色，320×264） | 最长条目截断、类型标签 |
| `light-03-sys.png` | 系统页（浅色，320×172） | IP / Wi-Fi / 开关 / 退出 |
| `light-04-net-empty.png` | 网络页空态（浅色，320×422） | 空态可用性 + 与「5 个」矛盾 |
| `light-05-clip-empty.png` | 剪贴板页空态（浅色，320×233） | 空态可用性 + 与「5 条」矛盾 |
| `light-06-sys-toast.png` | 系统页 + toast（浅色） | P1-1 证据：toast 盖住退出行 |
| `dark-01-net.png` | 网络页（深色，320×397） | 深色核对 |
| `dark-02-clip.png` | 剪贴板页（深色，320×264） | 深色核对 |
| `dark-03-sys.png` | 系统页（深色，320×172） | 深色核对 |
| `probe-300-net.png` | 面板临时改 300pt 宽 | brief `min_supported:300` 排版不破 |
| `probe-340-net.png` | 面板临时改 340pt 宽 | brief 340pt 上限 |

---

## 四、与作者结论的对照

| 作者声明（`05-checklist.md`） | 本审查复跑 | 结论 |
|---|---|---|
| `verify --browser` P0 全过、P0 阻塞项 0 | EXIT=0，12 PASS / 2 WARN / 0 FAIL | ✅ 属实 |
| 官方 56 槽完整粘贴 / 无裸色值 / accent 0 次 / 画布 320 | 逐条复现在报告第 1–2 条 | ✅ 属实 |
| 对比度达标（正文 4.5:1） | 浅色 3 页 min 4.66 | ✅ 属实 |
| 深色对比度「未单独跑」 | 本次补测：深色 3 页 min 4.66，0 项不达标 | ✅ 补上，通过 |
| 交互实测（tab / ←→ / 1.6s 回退 / 开关 / toast / 空态） | 全部真点击复现通过 | ✅ 属实（**但要补 toast 遮挡问题**） |
| 「无编造指标」通过 | 今日流量与近 7 日行冲突、近 7 日只 6 天 | ❌ 不属实（P1-2） |
| 「无编造功能/无死点击」 | 剪贴板设置的 ⌘⇧V 编造 | ⚠️ 部分不属实（P1-3） |
| 演示件 3 个、可机械排除 | HTML 只有 2 个 `demo-only:*`；移除后功能正常 | ⚠️ 数量口径不符（P2-10），可机械排除 ✅ |

**审查方立场**：同意作者「P0=0、门禁可通过」的结论，但**不同意「现在就可交用户拍板」**——P1-1（toast 遮挡「退出」）和 P1-2（今日/近 7 日数值打架）用户点两下就会撞见，P1-3 会把假快捷键带进实现。三条都好改（各 1–3 行），建议修完复跑一次 `verify` 再交付。

## 五、未覆盖（如实标注）

- 真机 `NSPanel` vibrancy 材质、圆角裁剪与 Safari 渲染差异（原型无法覆盖，属实现阶段）；
- `reduced-motion` 只做了 CSS 兜底，未用媒体模拟逐个动画复核（非本次交付判据）；
- 触屏 44px 判据不适用（brief `platform: desktop`，按 warn 处理）；
- 未跑 `odops od tools deliverable-syntax check`（需 `OD_TOOL_TOKEN`，裸 CLI 拿不到，按技能要求记「没跑」，不作通过证据）。

---

# r4 增量复审（作者修复后复验，2026-10-17）

- 范围：只复验 r1 报出的 **3 条 P1 + 6 条被声称修复的 P2**，加一次 `verify` 复跑；不重跑全量。
- 产物仍是就地修改的 `.open-design/08-prototype.html`；agent-browser session `proto-reviewer`（只关本会话）。
- **结论：3 条 P1 全部修复且复验通过；6 条 P2 全部修复；r1 另有 3 条 P2 属「作者已登记为不动/待办」或设计取舍，不阻塞。可交用户拍板。**

## 1. verify 复跑（与作者口径一致 ✅）

```bash
odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser
# EXIT=0
```

| 项 | r1 | r4 |
|---|---|---|
| PASS（ok） | 12 | 12 |
| WARN | 2 | 2（`5 个交互元素 <44px`、`<14px 文字 8 处`） |
| FAIL | 0 | 0 |

逐条 ok 与 r1 完全一致（自包含 / CSS 内联 / 6 变量 / 56 槽 / 无裸色值 / 3 区块 `data-od-id` / accent 0 次 / 画布 320 / lint 干净 / 无横向溢出 / 对比度达标），**修复未引入任何新 FAIL 或新 warn**。

## 2. P1 复验（逐条命令 + 输出）

### P1-1 toast 遮挡底部行 → **已修复 ✅**

```bash
agent-browser --session proto-reviewer click '#launch-row'   # EXIT=0
agent-browser --session proto-reviewer eval "...getComputedStyle(toast).pointerEvents"
# "{\"toast\":\"已关闭开机自启动\",\"hidden\":false,\"pe\":\"none\"}"      ← pointer-events:none 生效
agent-browser --session proto-reviewer click '#quit-row'      # EXIT=0，不再报 covered
agent-browser --session proto-reviewer eval "...toast.textContent"
# "{\"toast\":\"已请求退出\",\"hidden\":false}"                         ← 点击真的落到退出行
```

对照 r1：当时同一串命令会输出 `✗ Element '#quit-row' is covered by <div#toast> ...`。**遮挡复现命令现在重放成功**。
定位：`.toast{…pointer-events:none}`（第 175 行）；`#quit-row` 第 277 行、`#settings-row` 第 268 行均可正常点。

### P1-2 「近 7 日」与 6 条数据冲突 → **已修复 ✅**

```bash
agent-browser --session proto-reviewer eval "...h2.textContent / .days li"
# "{\"title\":\"近 6 日流量 10/11 — 10/16\",\"rows\":6,
#   \"dates\":[\"10/11\",\"10/12\",\"10/13\",\"10/14\",\"10/15\",\"10/16\"],
#   \"today\":{\"down\":\"12.5 GB\",\"up\":\"3.2 GB\"},\"lastRow\":\"10/162.0 GB520 MB\"}"
```

- 标题与行数自洽（6 条 / 近 6 日 / 10/11—10/16）。
- 与真实菜单语义一致：`MenuBarManager.swift:406-430` 是「今日」单独一行 + `entries[1...]` 逐日（`TrafficTracker.weekEntries` = 今天在最前的 7 条）→ 原型「今日流量」+「近 6 日」正好对上，**不再出现同一天两套数值**（唯一带“今日”含义的数值只剩顶部 12.5 GB / 3.2 GB）。
- 决策已记录：`04-rounds.md:48`、`05-checklist.md:167`。

### P1-3 剪贴板设置编造快捷键 → **已修复 ✅**

```bash
agent-browser --session proto-reviewer eval "...#settings-row .kbd / #quit-row .kbd"
# "{\"settingsKbd\":\"⌘,\",\"quitKbd\":\"⌘Q\"}"
grep -nE "⌘⇧V|⌘⌥V" .open-design/08-prototype.html   # EXIT=1（零命中）
```

- 设置项现为 `⌘,`，与源码一致（`ClipboardPanelController.swift:19`：⌘, 打开剪贴板设置）。
- `⌘⌥V`（唤起面板的 `defaultPanelToggle`，`GlobalHotKey.swift:17`）**没有**被误挂到设置项；退出仍是 `⌘Q`，与 `MenuBarManager.swift:211` 的 `keyEquivalent "q"` 一致。

## 3. P2 复验（作者声称修了 6 条）

| r1 编号 | 项 | 复验证据 | 结论 |
|---|---|---|---|
| P2-1 | 空态计数 | 点「空态」→ `{"clips":"0 条","procs":"0 个"}`；点回「有数据」→ `{"procs":"5 个","clips":"5 条"}` | ✅ |
| P2-2 | hover 盖掉选中 tab 强调蓝 | 选中「网络」`rgb(0,113,227)` → `hover` 后仍 `rgb(0,113,227)`；hover 未选中「系统」仍变 `rgb(29,29,31)` | ✅ |
| P2-4 | 示例 URL 含 AI 品牌 | `[data-clip="1"] .txt` = `https://developer.apple.com/documentation/appkit`；`grep deepseek` 零命中 | ✅ |
| P2-5 | 退出文案 | `#quit-row .lead` = `退出`（⌘Q 保留） | ✅ |
| P2-8 | tab/pane ARIA | 3 个 tab 均有 `aria-controls` 且目标存在；3 个 pane 均 `role="tabpanel"` + `aria-labelledby` 指回 tab id | ✅ |
| P2-10 | checklist 口径 | `05-checklist.md:144` 改为「2 个 `demo-only:*` + 2 项样式/动画层隔离」；`05-checklist.md:92` 补 warn 组成说明 | ✅ |
| P2-9 | odops warn「5 个」只列 4 个 | 实测按钮高度：演示按钮 24.5px ×2 + 分段 tab 26px ×3 = **5 个 `<button>` <44px**，作者口径正确；工具只截断显示 4 个标签 | ✅（口径已核实） |

## 4. 版式回归（修复未破坏）

- 三页浅色 + 三页深色截图（`shots/r4-light-{net,clip,sys}.png`、`shots/r4-dark-{net,clip,sys}.png`）：tab 栏、数值栅格、剪贴板行、系统页均与 r1 一致，无错位、无换行。
- 尺寸：net 320×397 / clip 320×264 / sys 320×172（与 r1 相同，≤600）；`scrollWidth 400 = clientWidth 400`（视口 400），各 pane `scrollHeight = clientHeight` → 无横向/纵向滚动。
- 交互回归：剪贴板条目「已复制」→ 1.7s 回退 `命令`；←→ 键盘切换（`net` ← wrap → `sys`，`activeElement=tab-sys`）；`agent-browser errors` 无页面报错。
- 深色截图取默认态（开机自启动「已开启」+ 勾选可见），修复未改配色，无需重测对比度（CSS 未动）。

## 5. 仍未收敛项（均 P2，不阻塞交付）

| 项 | 状态 | 说明 |
|---|---|---|
| r1 P2-3：320 视口下 body padding 使面板左右各裁 24pt | 作者登记为不动（`05-checklist.md`「未动」） | 属预览壳，契约已声明 body 样式不进产品；**评审截图请用元素截图或视口 ≥368** |
| r1 P2-6：示例日期 10/11–10/16 陈旧（当前 10/17） | 未改 | 示例数据，不构成自相矛盾；实现时由真实数据替换 |
| r1 P2-7：近 6 日每行上行值整列橙色（第 159 行） | 未改 | 设计取舍，建议实现时只高亮今天一行或降为 `--muted`，留给用户拍板时确认 |

## 6. r4 截图清单（`.open-design/reviews/shots/`）

`r4-light-net.png` · `r4-light-clip.png` · `r4-light-sys.png` · `r4-dark-net.png` · `r4-dark-clip.png` · `r4-dark-sys.png`

## 7. 复审结论

**可交用户拍板（是）。** r1 的 3 条 P1 全部修复且有重放证据，6 条被声称修复的 P2 逐条目视通过，`verify` 复跑 12 PASS / 2 WARN / 0 FAIL、EXIT=0，版式与交互无回归。剩余 3 条 P2 均为非阻塞项（其中 1 条已由作者登记为预览壳取舍）。

---

# r6 增量复审（v2 数据仪表盘定稿，2026-10-17）

- 产物：`.open-design/08-prototype.html`（46KB / 350 行，v2：hero+sparkline、今日双进度条、进程占比条、近 6 日柱状图、5 个真实 App 图标）
- 方式：`odops verify` 复跑 + agent-browser 真点击（session `proto-reviewer`，只关本会话）；只验本轮变化与 r4 修项回归，不重跑全量
- **结论：P0 = 0 · P1 = 3 · P2 = 5 → 建议先修 3 条 P1 再交用户拍板（三条都是局部改动）**

## 1. verify 复跑（与 r4 口径一致 ✅）

```bash
odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser
# EXIT=0
```
PASS 12（自包含 / CSS 内联 / 6 变量 / 56 槽 / 无裸色值 / 3 区块 data-od-id / accent 0 次 / 画布 320 / lint 干净 / 无横向溢出 / 对比度达标）· WARN 2（`5 个交互元素 <44px：button(28px)×3 + button(25px)`、`<14px 文字`）· FAIL 0。

## 2. r4 修项回归（逐条重放）

| r4 修项 | 实测 | 结论 |
|---|---|---|
| toast `pointer-events:none` | 点 `.toggle` 弹 toast 后点 `#quit-row`：`{"toast":"已请求退出"}`，无 covered 报错；`pe=none` | ✅ 未回退 |
| 近 6 日口径 | `近 6 日下行 / 10/11 — 10/16 · GB` + 6 根柱（11…16） | ✅ 未回退 |
| 设置项 `⌘,` | `#settings-row .v` = `⌘,`；`grep "⌘⇧V\|⌘⌥V"` 零命中 | ✅ 未回退 |
| 选中 tab hover 保持强调蓝 | `rgb(0,113,227)` → hover 后仍 `rgb(0,113,227)` | ✅ |
| tab/pane ARIA | 3 tab 有 `aria-controls`，3 pane `role=tabpanel`+`aria-labelledby` | ✅ |
| 退出文案 / 示例 URL | `退出`、`developer.apple.com/documentation/appkit` | ✅ |

> 注意：r4 的另一条「空态计数归零」**代码还在但已不可达**（见 P2-4），属演示件失效。

## 3. 图标质量（5 个全部有效）

```bash
python3 -c "…抽 data URI → sha256 与 /tmp/appicons48/*.png 比对…"
# 1 match=Safari.png(4490B) 2 Google-Chrome.png(4030B) 3 Terminal.png(2578B) 4 Notes.png(2736B) 5 Finder.png(3750B)
# 全部 PNG 48×48 RGBA
```
浏览器实测：`naturalWidth=48`、显示 `20x20`、`border-radius:4px`、`aria-hidden="true"`、`broken=false` —— **5 个都是真图、非破图、无重复**。
深色观感（`r6-zoom-dark-procs.png`）：Safari / Chrome / Notes / Finder 均清晰；**Terminal 偏暗**（平均 RGB `[19,19,19]`，面板深色底 `#1c1c1e`，块面对比约 1.1:1，20px 下只剩 2–3px 白色 `>_` 提示）→ P2-7。Finder 蓝底在深色下辨识度良好。

## 4. 三页浅/深截图核对（`r6-*.png`）

| 页 | 面板尺寸 | 核对结果 |
|---|---|---|
| 网络 | 320×493 | hero + sparkline、双进度条、5 进程带图标+占比条、6 根柱（10/16 蓝底高亮）；无重叠/截断/横向溢出 |
| 剪贴板 | 320×302 | 5 条齐全，**第 5 条「swift build -c release」右侧「命令」标签存在且可见**（kindW=20px，right 345 ≤ liRight 347）→ lead 担心的缺失不存在 |
| 系统 | 320×186 | Wi-Fi + IP、自启动开关、退出（图标为线性电源） |

- 视口 400：`scrollWidth=400=clientWidth`，各 pane 无内部溢出；面板高 493/302/186，均 ≤600。
- 对比度（自写脚本，浅/深 × 三页共 6 组）：文本节点 39/22/9，**min 4.66，0 项 <4.5:1**（深色同样达标）。
- AI/Token 残留复检：`grep -niE "token|模型|会话|AI |工具调用|reasoning|deepseek|gpt|claude"` 唯一命中第 7 行 CSS 注释（token 说明）→ 合规。

## 5. 数据语义自洽（除柱高 bug 外均成立）

- 今日进度条：实测 219/274 = **80%**、55/274 = **20%**，80+20=100 ✅（分母注释为 12.5+3.2=15.7 GB，79.6% / 20.4% 四舍五入 ✅）
- 进程占比条：Safari 1.2 MB/s 作 100% 基线，实测 100 / 70 / 20 / 8 / 2 % ↔ 1.2 MB、860 KB、240 KB、96 KB、24 KB ✅
- 近 6 日数值 3.1 / 1.8 / 4.2 / 2.4 / 5.6 / 2.0 ✅ 与 `--h` 期望百分比一致（但渲染失真，见 P1-2）

## 6. 问题清单（r6）

### P0 — 无

### P1 — 应修

**P1-1 剪贴板条目点击彻底失效（r4 可用的产品件行为回退）**
```bash
grep -c "data-clip=" .open-design/08-prototype.html      # 0（r4 为 5）
agent-browser --session proto-reviewer click '.clips li:nth-child(2)'
agent-browser --session proto-reviewer eval "…kind.textContent"   # "命令"（应短暂变「已复制」再 1.6s 回退）
agent-browser --session proto-reviewer eval "[…].map(li=>({role:li.getAttribute('role'),tabindex:li.getAttribute('tabindex')}))"
# 全部 role:null tabindex:null → 键盘也不可达
```
定位：第 257–261 行 `<li>` 丢了 `data-clip` / `role="button"` / `tabindex="0"`；JS 第 313 行仍按 `[data-clip]` 绑定 → 绑定到 0 个元素。影响：`07-contract.md` 明列「点击剪贴板条目 →『已复制』1.6s 回退」，用户点剪贴板页会以为坏了。

**P1-2 近 6 日柱状图比例失真（3.1 / 4.2 / 5.6 三根一样高）**
```bash
agent-browser … eval "…[...document.querySelectorAll('.bar')].map(b=>({v:b.querySelector('b').textContent,h:b.querySelector('i').getBoundingClientRect().height,hSpec:b.style.getPropertyValue('--h')}))"
# 渲染高度: 31 / 20 / 31 / 28 / 31 / 23 px
# 规格:    55% / 32% / 75% / 43% / 100% / 36%（.bar 列高 64px → 期望 35 / 20 / 48 / 28 / 64 / 23）
```
定位：`.bars{height:64px}` + `.bar` 内「数值 b + 柱 i + 日期 span」三段 + `gap:3px`，`.bar i{height:var(--h);flex-shrink:1}`（第 155–160 行）→ 超过剩余空间的柱被压到同一上限（31px），**5.6 GB 那根与 3.1 GB 视觉等高，5.6 不再是最高柱**；`--h` 值本身是对的（第 247–252 行）。修法：给 `.bar i` 设 `flex:0 0 auto` 并把 `.bars` 高度加到 ~78px（或改成 label 绝对定位）。

**P1-3 开机自启动勾选图标不随状态变化**
```bash
agent-browser … eval "…{checked:.toggle[aria-checked],state:#launch-state,checkVisible:getComputedStyle(.toggle svg)}"
# {"checked":"false","state":"已关闭","checkVisible":{"display":"inline","vis":"visible","opacity":"1"}}  ← 关闭态勾仍可见
```
截图 `r6-sys-off-state.png`：呈现「✓ 开机自启动　已关闭」。定位：第 271 行勾选 SVG 改为静态内联图标，JS（第 329–334 行）只改 `aria-checked` 与文案，不再切 `visibility`（r4 有）。修法：按状态切勾选图标的 `visibility/display`，或换成开/关两种 icon。

### P2 — 待办

4. **空态演示整体失效（demo-only）**：点击「空态」抛 `THROW: Cannot set properties of null (setting 'hidden')`——`setState()` 第 341 行查 `[data-clip-list]`，而 `<ul class="clips">`（第 257 行）没有该属性；结果空态不出现、`clips-count/procs-count` 不归零，但 `aria-pressed` 已切到「空态」（状态自相矛盾）。
5. **系统页 IP 值失去标签**：第 269 行把 IP 塞进 Wi-Fi 行右侧（`Wi-Fi「Home-5G」 192.168.1.42`），真实菜单是 IP / Wi-Fi 两项；右侧数字现在读起来像 Wi-Fi 属性。
6. **「已关闭」仍用强调蓝**：`.toggle .on{color:var(--accent)}`（第 179 行）固定强调色，关闭态不降级为 `--muted`。
7. **Terminal 图标深色下偏暗**：平均 RGB `[19,19,19]` vs 深色底 `#1c1c1e`（≈1.1:1），20px 下近似黑块（见 `r6-zoom-dark-procs.png`）；建议 `img` 外套 1px `--border` 环或深色下加 `outline`。
8. **预览裁切口径更正（自查）**：r1/r4 报告写「320 视口下左右各被裁 24pt」——**实测不成立**：320 视口面板 `left=0 / right=320`，正好贴边不裁切；只有视口 <320（如 300）才左右各裁 10pt（`left=-10/right=310`）。此前结论有误，特此更正。

## 7. 截图清单（`.open-design/reviews/shots/`）

`r6-light-net.png` · `r6-light-clip.png` · `r6-light-sys.png` · `r6-dark-net.png` · `r6-dark-clip.png` · `r6-dark-sys.png` · `r6-sys-off-state.png` · `r6-zoom-light-procs.png` · `r6-zoom-dark-procs.png`

## 8. r6 结论

**不建议现在交用户拍板（否）**：机械门禁（verify EXIT=0、12 PASS / 0 FAIL）与视觉方向都成立，但 3 条 P1 都是用户点两下就会遇到的——剪贴板页点了没反应、柱状图最高的 5.6 GB 与 3.1 GB 一样高、关掉开关后勾还在。三条都是局部 CSS/属性改动，修完复跑 `verify` 并重放上面 3 条复现命令即可放行。

---

# r7 增量复审（P1×3 + P2×4 修复验证，2026-10-17）

- 方式：`odops verify` 复跑 + 重放 r6 的 3 条 P1 复现命令 + 4 条 P2 专项核 + 三页浅/深重截（session `proto-reviewer`，只关本会话）
- **结论：P0 = 0 · P1 = 0 · r6 的 3 条 P1 与 4 条 P2 全部修复 → 可交用户拍板（是）**；仅剩 2 条 P2 小项（不阻塞）

## 1. verify 复跑

```bash
odops verify .open-design/08-prototype.html --template web-prototype --platform desktop --browser
# EXIT=0
```
PASS 12 · WARN 2（`5 个交互元素 <44px`、`<14px 文字`）· FAIL 0 —— 与 r6 同口径，无新增问题。

## 2. r6 三条 P1 重放结果

**P1-1 剪贴板条目交互 → 已修复 ✅**
```bash
agent-browser … eval "…{n:document.querySelectorAll('[data-clip]').length, role, tabindex}"
# {"n":5,"li2":{"role":"button","tab":"0","kind":"命令"}}
agent-browser … click '[data-clip="2"]'      # EXIT=0
# 0.15s: {"afterClick":"已复制","flash":"kind flash"}
# 1.7s:  "命令"                              ← 回退到原类型（第 2 条本身就是「命令」）
```
键盘路径同样可用：`focus '[data-clip="3"]'` → `press Enter` → 「已复制」→ 1.7s 回退「文本」。
（作者说的「回退『链接』」是口误：第 1 条才是链接，第 2 条原值是「命令」，实测回退正确。）

**P1-2 柱状图比例 → 已修复 ✅**
```bash
agent-browser … eval "…[...document.querySelectorAll('.bar')].map(b=>({v,h,hSpec}))"
# 3.1→35.19px(55)  1.8→20.47(32)  4.2→48(75)  2.4→27.52(43)  5.6→64(100)  2.0→23.03(36)
# 期望 35.2 / 20.48 / 48 / 27.52 / 64 / 23.04 → 全部 ±0.05px，5.6 GB 为最高柱
```
实现：`.bar{grid-template-rows:12px 64px 12px}` + `.bar i{height:calc(var(--h) * 0.64px)}`（第 159–161 行），`--h` 为纯数字。柱状图语义标签「10/11 — 10/16 · GB」与 11…16 六根柱一致。

**P1-3 自启动关闭态 → 已修复 ✅**
```bash
agent-browser … click '.toggle'
# {"checked":"false","state":"已关闭","color":"rgb(152, 152, 157)","vis":"hidden"}   ← 深色下 --muted，#98989d
```
浅色下同类值为 `--muted #6e6e73`；勾选 SVG `#launch-check` 关闭时 `visibility:hidden`（第 278、339 行）；`.toggle .on.off{color:var(--muted)}`（第 183 行）。截图 `r7-dark-sys-off.png`：无勾、「已关闭」灰色、无 toast 遮挡。

## 3. 四条 P2 复验

| r6 P2 | 实测 | 结论 |
|---|---|---|
| 空态演示失效 | 点「空态」→ `{"clipsCount":"0 条","procsCount":"0 个","clipEmptyShown":true,"procsEmptyShown":true}`；`[data-clip-list]` 存在（第 261 行），`querySelector('[data-clip-list]').hidden=false` 返回 `ok` 不抛错；点回「有数据」→ `5 条/5 个` | ✅ |
| 系统页 IP 失去标签 | 两行：`IP 地址 192.168.1.42` / `Wi-Fi Home-5G`（第 275–276 行，每行各带线性图标） | ✅ |
| 「已关闭」仍用强调蓝 | 关闭态实测 `rgb(152,152,157)`（深色）/ `#6e6e73`（浅色），不是 `rgb(0,113,227)` | ✅ |
| Terminal 深色图标 | 新增 `.app-icon.term{background:rgba(255,255,255,.10);box-shadow:0 0 0 1px var(--border)}`（仅深色媒体查询，第 153–155 行）；8× 放大图 `r7-zoom-dark-terminal.png` 中衬底块 + 描边清晰可辨 | ✅（数值上衬底 1.34:1 / 描边 1.49:1，略低于 1.5:1 阈值但目视清晰，属可接受） |

## 4. 布局与截图核对（`r7-*.png`，均元素截图、无 toast）

| 页 | 面板尺寸（r6 → r7） | 结论 |
|---|---|---|
| 网络 | 493 → **523** | 柱状图改 grid 后 +30px，仍 ≤600；6 根柱高低分明，10/16 保持蓝底高亮；无横向溢出 |
| 剪贴板 | 302 → 302 | 5 条 + 类型标签（含第 5 条「命令」）；无截断 |
| 系统 | 186 → **230** | IP / Wi-Fi 拆两行后 +44px，仍 ≤600；开关与退出完整 |

- 视口 400：`scrollWidth=400=clientWidth`；各 pane `scrollWidth=clientWidth`、`scrollHeight=clientHeight`（无内部溢出）。
- 截图前主动 `reload` 并确认 `#toast.hidden=true`，**没有复现「toast 遮挡退出」的时序假象**（关闭态那张也等 2.2s toast 消失后重拍）。
- AI/Token 残留复检：唯一命中仍是第 7 行 CSS 注释 → 合规。

## 5. 剩余问题（P2，不阻塞）

1. **`:root` 外的裸色值**：`.app-icon.term{background:rgba(255,255,255,.10)}`（第 154 行）未走 token；因不是 hex，`verify` 的机械检查仍报 ok。建议加 `--icon-plate` / `--icon-plate-ring` 两个槽位，保持「所有颜色走 token」的口径。
2. **Terminal 衬底对比度**：1.34:1（衬底）/ 1.49:1（描边），接近但未达 1.5:1；深色下目视可辨，若用户反馈偏弱可把衬底提到 14% 或描边换 `--muted`。

## 6. r7 截图清单（`.open-design/reviews/shots/`）

`r7-light-net.png` · `r7-light-clip.png` · `r7-light-sys.png` · `r7-dark-net.png` · `r7-dark-clip.png` · `r7-dark-sys.png` · `r7-dark-sys-off.png` · `r7-zoom-dark-terminal.png`

## 7. r7 结论

**可交用户拍板（是）**：r6 的 3 条 P1（剪贴板点击、柱高失真、关闭态勾选）与 4 条 P2（空态、IP 标签、关闭态颜色、Terminal 衬底）全部修复并有重放证据；`verify` EXIT=0、12 PASS / 0 FAIL；三页浅深截图无破版、无重叠、无横向溢出。剩余 2 条 P2 属 token 口径与观感微调，可在实现阶段一并处理。

---

# r10 剪贴板收敛稿审查（`.open-design/03-layouts/clip/final.html`，2026-10-17）

- 范围：只审剪贴板收敛稿；`08-prototype.html`（已冻结）只读比对 token，未改动
- 方式：`odops verify` + agent-browser 真点击/真按键（session `proto-reviewer`，只关本会话）
- **结论：层级倒置已到位（用户否决点解决）；但 2 条 P1 交互缺陷（页脚明示的 ⌘1–9 无响应、↑↓ 选中不滚入可视区）会让用户再撞一次 → 建议修完再交验收。P0=0 · P1=2 · P2=3**

## 1. verify 复跑

```bash
odops verify .open-design/03-layouts/clip/final.html --template web-prototype --platform desktop --browser
# EXIT=0
```
PASS 12（自包含 / CSS 内联 / 6 变量 / 56 槽 / 无裸色值 / `data-od-id` / accent 0 次 / lint 干净 / 无横向溢出 / 对比度达标）· WARN 2（`14 个交互元素 <44px：input 20px、button 22px…`、`<14px 文字`）· FAIL 0。

> 注意：「画布宽与澄清单一致（320px）」是**误命中**——剪贴板面板实际 `640×260`，`verify` 在产物里找到 `.search{max-width:320px}` 就当画布声明成立（`~/.local/bin/odops:1807` 的 `declared` 判据）。见 P2-3。

## 2. 层级倒置（用户最在意的点）→ 已到位 ✅

| 判据 | 实测 | 结论 |
|---|---|---|
| 卡片内 App 名文字 | `grep -c "Safari\|Chrome\|Terminal\|Notes\|Finder"` = **0**；8 张卡 `textContent` 全部无 App 名；App 图标 `alt="" aria-hidden` | ✅ 彻底不存在 |
| `×3` 粘贴次数 | `grep -c "×3"` = **0**（`⌘1…⌘8` 是快捷键徽标，不是次数） | ✅ 已移除 |
| 内容区占卡片高度 | `.c-text/.c-thumb` 136px ÷ 卡片 196px = **0.69**（8 张全部 0.69，≥60%） | ✅ |
| App 图标尺寸/权重 | `12×12`（≤14px）、`opacity:.75`、位于底部 meta 行；正文 11px / meta 10px | ✅ 权重低于内容 |

截图 `r10-clip-light.png` / `r10-clip-dark.png` / `r10-clip-light-card.png`（单卡放大）：卡片视觉重心是内容，底部只有 12px 图标 + 相对时间 + 类型线性图标。

## 3. 词中断回归 → 未回归 ✅

```bash
# computedStyle: word-break=normal, overflow-wrap=break-word, white-space=normal
# 逐字符 Range 断行检测（7 张文本卡）
# 卡1 URL 2 行，断在「.」后：appkit 完整、documentation 完整 → ok:.|c
# 卡2 xcodebuild 4 行：断在空格 / 连字符（ok: |N, ok:-|c, ok: |b）
# 卡4 git commit 3 行：断在空格（ok: |m, ok: |t）
# 卡8 JSON 2 行：断在「:」后（ok::|[）
# 其余中文卡按字断行（中文无空格，属正常）
# => hasMidWord 全部 false，无一处从单词中间断开
```
4 条长内容（URL / xcodebuild 命令 / git commit / JSON）逐一量过，均无词中断。

## 4. 交互回归

| 行为 | 实测 | 结论 |
|---|---|---|
| 搜索过滤 | 输入 `git` → 可见 1 张（`git commit -m …`） | ✅ |
| 类型过滤 | 「文本」→ 3 张（kind=text,text,json）；「收藏」→ 2 张（fav=1） | ✅ |
| 无结果空态 | 输入 `zzzz` → 可见 0、`.empty` 显示「没有匹配的剪贴板条目 / 试试换个关键词或切换类型」 | ✅ |
| ↑↓ 选中 | ArrowDown 卡1→卡2，ArrowUp 卡2→卡1，`.sel` 与 `aria-selected` 同步 | ✅ 逻辑正确 |
| **↑↓ 选中是否可见** | 连按 6 次 ArrowDown 选中第 7 张：卡片 rect `1295–1479`，可视区 `131–769`，`scrollLeft` 仍为 **0** → 选中项完全在视口外 | ❌ **P1-2** |
| Enter / Esc | toast「已粘贴到前台 App」/「已收起面板」 | ✅ |
| **⌘1–9 直选** | `press Meta+3` 后选中项仍是第 1 张、toast 无变化；全文件无 `metaKey` / `keyCode` / `Digit` 分支 | ❌ **P1-1** |
| 收藏星切换 | 点第 2 张的星：`data-fav 0→1`、`class="star on"`、`aria-pressed=true`，卡片仍是原选中项、无跳转、无 toast | ✅ 不触发卡片跳转 |

## 5. 视觉一致性（与冻结的 `08-prototype.html` 比对）

```bash
python3 比对两文件第一个 :root 的 token 字典
# final 77 个 token，08 77 个；缺少=[] 多出=[] 取值不同=[]  → 完全同源
```
- 面板：`border-radius:12px`、`box-shadow:0 16px 40px color-mix(--shadow 16%)` 与 08 一致；
- 字号阶梯：正文 12 / 内容 11 / meta 10（与 08 的 12 / 11 / 10 一致）；圆角：卡片 10 / 控件 8 / 徽标 6 / 头像 3；
- 深色：`@media` 只重绑语义 token（同 08 写法），无遮罩错色。

## 6. 问题清单

### P0 — 无

### P1 — 应修

**P1-1 页脚明示的「⌘1–9 直选」未实现**
```bash
grep -nE "metaKey|keyCode|Digit" .open-design/03-layouts/clip/final.html   # 0 命中
agent-browser … press "Meta+3"
agent-browser … eval "{sel: .card.sel.dataset.text, toast}"
# {"sel":"https://developer.apple.com/documentation/appkit","toast":"已收起面板"} ← 选中未变、无反馈
```
定位：页脚提示第 177 行 `⌘1–9 直选`、每张卡 `⌘1…⌘8` 徽标（第 168–175 行）；`keydown` 处理（第 208–213 行）只有 ↑↓ / Enter / Escape。用户会照提示按 ⌘3，页面毫无反应。

**P1-2 ↑↓ 选中不滚入可视区（横向卡片轨 8 张只露 3.2 张）**
```bash
# 连按 6 次 ArrowDown 后：
{"selText":"今天的咖啡钱 ¥32.00","scrollLeft":0,"cardLeft":1295,"cardRight":1479,
 "railLeft":131,"railRight":769,"fullyVisible":false}
```
定位：`.cards{overflow-x:auto}`（第 130 行）+ `select()`（第 188–190 行）只切 class，未同步 `cards.scrollLeft`。第 4–8 张的选中态永远看不见（也看不见 ⌘4–8 徽标所在卡片）。
修法：`select()` 里补 `cards.scrollLeft = clamp(卡片 offsetLeft - 12, …)`（**不要用 `scrollIntoView`**——模版 checklist 明确禁它在 OD 预览 iframe 里滚动外层页面）。

### P2 — 待办

1. **示例内容像设计批注、且含 AI 字样**：第 170 行内容「会议纪要 10/16 — 菜单栏面板改版：三段式 tab，AI 相关入口全部移除。」——不是真实剪贴内容，且用户已拍板要清掉 AI 痕迹；建议换成中性示例（如「季度复盘会 · 10/16 14:00」）。
2. **卡片缺 `role`**：`.card` 有 `tabindex=0` + `aria-selected`，但没有 `role="option"`（或 `listbox/option` 结构），`aria-selected` 在 `listitem` 上不合法；建议 `.cards[role=listbox]` + `.card[role=option]`。
3. **画布口径需确认**：剪贴板面板实际 `640×260`，而 `00-brief.md` 的 `canvas: 320x600` 是菜单面板口径；`verify` 的「画布宽一致」是 `.search{max-width:320px}` 误命中。请在 `00-brief.md` / `07-contract.md` 注明这是第二个画布（或让 verify 的判据认 `.panel` 的实际宽度），否则实现 agent 会拿 320 去裁这个面板。
4. **横向轨的滚动可见性**：8 张卡在 640 宽下只露 3.2 张，鼠标用户靠滚轮横滚（`.cards::-webkit-scrollbar` 高 6px）；与 P1-2 同源，修键盘滚动后建议也给轨尾一个渐隐遮罩提示。

## 7. 截图清单（`.open-design/reviews/shots/`）

`r10-clip-light.png`（640×260 元素截图）· `r10-clip-dark.png` · `r10-clip-light-card.png`（单卡放大，用于层级比对）

## 8. r10 结论

**层级问题已解决（可交的核心诉求），但不建议此刻交验收**：用户否的点是「没突出剪贴内容、反而突出软件名」，这一条已用 4 项量化证据确认修好（App 名 0 命中、×3 0 命中、内容占 69%、图标 12px/75% 权重）。剩 2 条 P1 都是页脚已明示的键盘能力（⌘1–9 直选、↑↓ 选中可见），用户一按就发现，改动量约 20 行；修完复跑 `verify` + 重放上面两条命令即可交。

---

# r11 最终复审（剪贴板收敛稿，2026-10-17）

- 范围：只验 r10 的 2 条 P1 + 3 条 P2 + 一次 verify + 交互回归；未改动任何产物
- 方式：`odops verify` + agent-browser 真按键/真点击（session `proto-reviewer`，只关本会话）
- **结论：P0 = 0 · P1 = 0 · P2 = 0（r10 遗留 3 条已全部关闭）→ 可交用户验收（是）**

## 1. verify 复跑

```bash
odops verify .open-design/03-layouts/clip/final.html --template web-prototype --platform desktop --browser
# EXIT=0 · PASS 12 · WARN 2 · FAIL 0
```
WARN 仍为 `14 个交互元素 <44px`、`<14px 文字`（桌面面板常态，与 r10 一致）。

## 2. 两条 P1 重放（真事件）

**P1-1 ⌘1–9 直选 → 已修复 ✅**
```bash
agent-browser … press "Meta+3"
# {"idx":2,"text":"周会纪要 10/16 —","toast":"已粘贴到前台 App"}
agent-browser … press "Meta+8"
# {"idx":7,"scrollLeft":914,"toast":"已粘贴到前台 App"}
```
定位：第 215–216 行 `else if(e.metaKey && /^[1-9]$/.test(e.key)){ … select(idx); toast('已粘贴到前台 App') }`；`idx<v.length` 越界保护（Meta+9 在 8 条时无动作，符合预期）。

**P1-2 ↑↓ 选中滚入可视区 → 已修复 ✅**
```bash
Meta+1 复位 → {"idx":0,"scrollLeft":0}
↓×6    → {"idx":6,"scrollLeft":722,"cardRect":[573,757],"rail":[131,769],"inView":true}
↑×5    → {"idx":1,"scrollLeft":192,"cardRect":[143,327],"inView":true}   ← 反向也能回滚
```
定位：第 191–194 行 `select()` 内按 `getBoundingClientRect` 差值调 `cardsEl.scrollLeft`（左右各留 12px 内边距），**未使用 `scrollIntoView`**（`grep -c scrollIntoView` = 0，符合模版 checklist）。

## 3. 三条 P2 关闭

| r10 P2 | 复验证据 | 结论 |
|---|---|---|
| 示例内容含 AI 字样 / 像批注 | 文案改为「周会纪要 10/16 — 面板改版评审：三段式 tab、快捷键、空态。」；`sed` 去掉 base64 后 `grep "AI"` **零命中**（此前命中全是 app 图标 base64 噪声） | ✅ |
| 卡片缺 `role` | `.cards[role=listbox]`，8 个子元素**全部** `role="option"`（`nonOption:0`），`aria-selected` 在 option 上合法 | ✅ |
| 画布口径 | 新增 `.open-design/00-brief-clipboard.md`：`canvas: 640x260`、`min_supported: 640`、并注明「本画布 640×260 与菜单栏面板的 320×600 不同源，实现时按各自尺寸，不要按 320 裁切」；`07-contract.md:61` 同步登记 | ✅ |

## 4. 交互回归（真点击/真按键）

| 行为 | 证据 | 结果 |
|---|---|---|
| 搜索 | 输入 `git` → 可见 1 张 | ✅ |
| 类型过滤 | 「文本」→ kinds `["text","text","json"]` | ✅ |
| 收藏过滤 | 「收藏」→ favs `["1"]`（默认只有会议纪要一条收藏） | ✅ |
| 无结果空态 | 输入 `zzzz` → `emptyShown:true`，可见 0 | ✅ |
| Enter / Esc | toast「已粘贴到前台 App」/「已收起面板」 | ✅ |
| 点星不跳转 | 点第 2 张星：`fav 0→1`、`class="star on"`、`aria-pressed=true`、选中项仍为 idx 0、无 toast | ✅ |

## 5. 视觉与截图

- `r11-clip-light.png` / `r11-clip-dark.png`（元素截图 640×260，`#toast.hidden=true`，无遮罩假象）：布局与 r10 一致，无破版；深色下卡片/工具栏/收藏星对比正常。
- 页面无横向溢出（`docOverflow:false`）；卡片轨内部横向滚动为设计（8 张卡，键盘选中已自动滚入）。
- 层级判据维持 r10 结果（App 名 0、×3 0、内容占 69%、App 图标 12px/75%）。

## 6. r11 结论

**可交用户验收（是）。** r10 的 2 条 P1 已重放通过（⌘3/⌘8 选中与 toast、↓×6 滚入 722px、↑×5 回滚 192px），3 条 P2 均关闭（示例文案无 AI 字样、listbox/option 结构合法、640×260 已入单独 brief 与 contract），verify `EXIT=0` 12 PASS / 2 WARN / 0 FAIL，回归全部通过，浅/深截图无破版。

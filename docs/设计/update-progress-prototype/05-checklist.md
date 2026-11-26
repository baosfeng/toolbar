# 05 自测清单 —— 关于 › 更新卡（检查更新 / 下载安装）

产物：`08-prototype.html`（单文件自包含，760×540 = `SettingsSkeletonMetrics.windowWidth/Height`）
画布：窗口整体（侧栏 168 + 内容区 592，页头常驻 + 正文滚动）
预览：http://127.0.0.1:51179/ （`odops preview` 常驻，改文件自动刷新）
证据原件：`evidence-draft.log` / `evidence-verify.log` / `evidence-shots.log` / `evidence-preview.log`

---

## 1. 机器门禁结果

### `odops draft` —— **exit 0 · PASS**

| 检查 | 结果 | 实测值 |
|---|---|---|
| 打开 | ok | file:// 加载成功，无页面 JS 报错 |
| 破图 | ok | 无 `<img>`（全部图标为 CSS / 伪元素） |
| 溢出 | ok | 横向溢出 **0px**（画布 760） |
| 空屏 | ok | 正文 **649 字** |
| 配色 | ok | **21 处**非灰颜色（`button.on` bg `rgb(0,86,179)` / `div.it` bg `rgba(0,113,227,.12)`） |
| 文案 | ok | 无 lorem / Feature One / 示例文本 |

### `odops verify --browser` —— **exit 0 · P0 = 0**

已过（12 项）：

- 单文件自包含（无外部 script / link / img / 字体）
- CSS 内联
- `:root` 含核心 6 个语义变量
- `:root` 是官方 56 槽的完整粘贴
- 所有颜色都走 token，**无裸色值**
- 2 个顶层区块都有 `data-od-id`
- 强调色用法 0 次（正文内 accent 全走 `--accent-ink` 语义色）
- 澄清单未要求响应式 → 按固定画布交付
- 画布宽与澄清单一致（760px）
- 官方 anti-slop lint（`--fail-on p1`）干净
- 无横向溢出
- 文本对比度达标（正文 4.5:1 / 大字 3:1）

WARN（3 条，均为桌面原生窗口的预期项，不改）：

| warn | 判定 | 理由 |
|---|---|---|
| 2 个 emoji 字符 | 保留 | 是 B 版清单的勾选字形（`✓` 走 `::after` 绘制而非文案），非 emoji 图标 |
| 14 个交互元素 <44px | 保留 | desktop 平台判据：点击区 44px 只在触屏是 P0；设置窗口按 macOS 控件档 22pt |
| <14px 文字 | 保留 | 设置页定稿度量就是 10.5–12pt（`SettingsSkeletonMetrics` / `SettingsTheme` 字号表），窗口尺度比面板每档 +1.5pt |

覆盖度（照实话报）：browser 审计扫描 **1 屏**（760×540 单画布）；点击区 14 个、对比度全量文本、溢出 1 次；两版（A/B）与 9 个状态各自的实测在 §3。

---

## 2. 两版取舍（只差进度展示形态）

| | **版 A · 单条阶段进度条** | **版 B · 阶段清单** |
|---|---|---|
| 形态 | 一条 6pt 高、水平四等分的分段条；当前段在自己的格子里按字节百分比填充并跑流光，已过段整格实心，未来段留空；条下是四段刻度（下载·校验·安装·重启，已完成打勾、当前加圈、失败打感叹号） | 最上方一条**总进度条**（0–100% 混合进度）+ 下方四行 checklist；每行 = 状态圈 + 段名 + **自己的小进度条** + 该段的百分比 + 该段的细节（字节 / SHA / 换包方式） |
| 一眼看到 | 「现在在第几段 + 当前段走到哪」——把四段压成一条，横向空间全给字节级精度 | 「还剩几段、每段各自的完成度」——四行并列，能对比不同段的进度与口径 |
| 适合 | 用户只想确认「在下、还有多久」（单次升级的多数场景） | 安装卡出问题时排查（哪一段卡住、卡住的段自己的百分比留在哪） |
| 代价 | 单条只能表达「当前段百分比」，跨段总量要靠刻度脑补；窄到 592pt 内容区时每段仅 ~132pt，字节细字只能挪到条下方一行 | 四行 + 小条占高约 100pt（比 A 多 26pt），把新版本说明区顶下去一截；小条 92pt 宽下百分比只能给 3 位（`42%` / `100%`） |
| 实测几何 | 段宽 132pt ×4，gap 3pt；当前段填入 **56px = 132×42%** | 总条全宽 552pt；行高 22pt ×4；小条 92pt；行内 `名字 58 / 小条 92 / 百分比 30 / 细节 flex` |

**共同部分（两版完全一致，不做差异）**

- 版本信息五行：当前版本 / 最新版本（accent）/ 发布时间 / 安装包（架构 · 大小）/ 完整性（SHA-256 状态）
- 新版本说明：固定高度 88pt 内部滚动，按「标题 / 条目 / 段落」分块（与 `SettingsReleaseNotesView` 同口径）；只在「发现新版本」之后才出现
- 失败块：`warn-soft` 底 + 感叹号 + 三行（标题 / 原因 / 已保留内容），两种失败口径各自文案
- 操作行：左说明 + 「检查更新」+ 主按钮（`下载并安装` / `下载中…` / `重试安装`）
- 顶部「关于」页头常驻，滚动时不丢上下文

---

## 3. 6+ 状态覆盖（都已截图，可逐个核对）

状态切换器在页面顶部（`data-od-id="demo-only:state-switcher"`，演示件不进产品）；也可直接用 URL：`08-prototype.html?state=<状态>&variant=<a|b>#shot`。

| 状态 | 版 A 表现 | 截图 |
|---|---|---|
| **未检查**（idle） | 进度区隐藏；五行占位「—」；主按钮置灰「下载并安装」；说明区隐藏 | `shots/state-idle.jpg` |
| **检查中**（checking） | 只出一条不确定进度条（34% 流光），分段刻度隐藏——没字节可报就不假报 | `shots/state-checking.jpg` |
| **有新版本**（available） | 进度区隐藏；最新版本 1.32.0 accent；完整性「SHA-256 · 发布方提供」；主按钮「下载并安装」可点；说明区出现 | `shots/state-available.jpg` |
| **下载中 42%**（downloading） | 首段 active 填 42%（实测 56px/132pt）+ 流光；刻度「下载」加圈；右下「2.1 MB/s · 剩余约 3 秒」；左下「已下载 5.1 MB / 12.2 MB」 | `shots/proto-a-light.jpg` / `proto-a-dark.jpg` |
| **校验中**（verifying） | 第 1 段 done（满格），第 2 段 active；完整性行变「正在核对 SHA-256」 | `shots/state-verifying.jpg` |
| **安装中**（installing） | 前两段 done，第 3 段 active；细节「备份 → 暂存位预演 → 原子换包」 | `shots/state-installing.jpg` |
| **待重启**（relaunch） | 三段 done，第 4 段 active；提示「重启后屏幕录制 / 辅助功能可能需重新授权」 | `shots/state-relaunch.jpg` |
| **失败·下载不完整** | 第 1 段转 `warn-ink` 并保留 42%；刻度「下载」标感叹号；失败块三行（下载不完整 / 网络中断 / 已保留在临时目录，重试从 42% 续传）；主按钮「重试安装」 | `shots/state-failed.jpg` |
| **失败·权限不足** | 前两段 done、第 3 段转 `warn-ink`；失败块（没有写入权限 / /Applications 需要管理员权限 / 安装包保留可手动装）；SHA 仍显示「已核对」 | `shots/state-failed-permission.jpg` |
| 版 B 的两个失败态 | 清单里失败行自己的小条保持断点百分比，其余行灰/勾 | `shots/state-b-failed.jpg` / `state-b-failed-permission-dark.jpg` |

多于 6 个：实际覆盖 **9 个状态**（含 verifying / installing / relaunch 三段拆分与两种失败原因）。

---

## 4. 深浅色

- 令牌：官方 `apple` 设计体系 `:root` 56 槽**逐字粘贴** + 项目角色层（`ThemeCatalog.apple` 语义：surface / cardFill / bandFill / track / hairline / cardStroke / accent / ok / warnInk / ghost），深色用 `prefers-color-scheme` 换绑，调用点不写第二份。
- 实测：`proto-a-light` / `proto-a-dark` / `proto-b-light` / `proto-b-dark` 四张，深色下卡片底 `#2b2b2f`、面板底 `#1b1b1d`，文字三档对比度全部 ≥4.5:1（verify 对比度项 ok）。
- 无 `color-scheme` 冲突；深色截图由 `agent-browser set media dark` 模拟（`odops shot` 不支持深浅切换，用 `src/shots.sh`）。

---

## 5. 截图清单（`.open-design/update-progress/shots/`）

| 文件 | 内容 | 大小 |
|---|---|---|
| `proto-a-light.jpg` | 版 A · 下载中 42% · 浅色 | 70.8 KB |
| `proto-a-dark.jpg` | 版 A · 下载中 42% · 深色 | 67.5 KB |
| `proto-b-light.jpg` | 版 B · 下载中 42% · 浅色 | 71.2 KB |
| `proto-b-dark.jpg` | 版 B · 下载中 42% · 深色 | 68.1 KB |
| `state-idle.jpg` | 未检查 | 56.3 KB |
| `state-checking.jpg` | 检查中 | 57.4 KB |
| `state-available.jpg` | 有新版本 | 63.4 KB |
| `state-verifying.jpg` | 校验中 | 72.8 KB |
| `state-installing.jpg` | 安装中 | 72.9 KB |
| `state-relaunch.jpg` | 待重启 | 75.0 KB |
| `state-failed.jpg` | 失败 · 下载不完整 | 78.2 KB |
| `state-failed-permission.jpg` | 失败 · 权限不足 | 80.7 KB |
| `state-b-failed.jpg` | 版 B · 失败（清单形态） | 73.7 KB |
| `state-b-failed-permission-dark.jpg` | 版 B · 权限失败 · 深色 | 74.2 KB |

全部 760×540、真 JPEG（`agent-browser` 的 `screenshot` 实为 PNG 字节，已用 `sips` 转真 JPEG 再交付）。

---

## 6. 本轮修掉的门禁红灯（改前 → 改后）

| # | 问题 | 证据（改前） | 修法 | 改后 |
|---|---|---|---|---|
| 1 | `:root` 缺核心语义变量 `--surface` / `--border` | `_verify.log`：FAIL「:root 缺核心语义变量」 | 把项目角色层补成官方 56 槽完整声明 | ok |
| 2 | 2/2 顶层区块缺 `data-od-id` | `_verify2.log`：FAIL | 侧栏 / 内容区 / 演示控制条各补锚点 | ok（2 区块全有） |
| 3 | 4 处裸色值 `#fff` | `_verify2.log` warn | 改 `--check-ink` / `--accent-on` token | 0 处裸色值 |
| 4 | 对比度不足 5 处（3.65:1 / 3.87:1 / 1.49:1…） | `_verify2.log` FAIL | 勾选字形改 `::after` 绘制、禁用态不用 `opacity`、正文 accent 换 `--accent-ink`、演示条激活底改 `#0056b3` | 全部 ≥4.5:1 |
| 5 | `var(--fg2)` 未定义（6 处，规则被静默丢弃） | 手工扫描 | 统一为 `--fg-2` | 0 处未定义变量 |
| 6 | 两版进度区**同时可见**（假差异） | `proto-a-light` 首张：A/B 两条都出现 | 删掉按状态强行 `display:block` 的规则，交回 variant 选择器 | 每版只出一条 |
| 7 | `state=available` 时页面被自动滚到中途（顶部标题与「应用」卡被切掉） | `state-available` 首张 | 自动滚动只在真的执行中 / 失败时触发 | 顶部完整 |
| 8 | 侧栏缺「系统」项（11 分类只画了 10 个） | 截图 | 补回 | 11 分类齐全 |

---

## 7. 交给实现方的对表约定

1. **状态源只有一个**：`UpdateInstallState.stage`（idle / downloading / verifying / installing / readyToRelaunch / failed）+ 现有 `UpdateCheckState`（idle / checking / upToDate / available / failed）。原型里的 9 个形态是这两者的组合，不新增案例。
2. **文案不新造**：进度区顶部直接复用 `UpdateInstallText.statusLine(_:)`（「正在下载安装包…」/「正在校验安装包…」/「正在安装（备份当前版本）…」/「已安装，即将重启」）；按钮标题复用 `UpdateInstallText.buttonTitle(_:)`；ad-hoc 授权提示复用 `UpdateInstallText.reauthorizationNotice`。
3. **字节级进度需要 Core 补一条能力**：现在 `UpdatePackageDownloading.downloadPackage(from:)` 只返回一次 `Data`（`UpdatePackageDownload.swift:73-76`），没有进度回调。要落地版 A/B 的百分比，需给协议加 `progress: @Sendable (Int64, Int64) -> Void`（或返回 `AsyncStream<UpdateDownloadProgress>`），由 `URLSessionHTTPTransport` 用 `URLSessionDownloadDelegate` / `URLSession.bytes(for:)` 上报；**这是本轮唯一的 Core 接口变更**。
4. **UI 口径放 UI 库**：`UpdateInstallProgressText`（百分比、已下载/总大小、速度、剩余时间的格式化 + 阶段进度派生）放进 `NetworkMonitorUI`，纯函数可被 TestRunner 直接断言（与 `UpdateInstallText` / `UpdateCheckText` 同位置同风格）。
5. **失败要保留已下载内容**：原型失败块第三行写「已下载内容保留在临时目录，重试从 42% 续传」——需要安装器把部分数据与已完成字节数留在临时目录（当前 `downloadPackage` 失败即丢），并在重试时传给下载层做续传；不做续传就把这行改成「重新下载」。
6. **两种失败原因的文案来源**：下载不完整 ← `UpdateInstallError.downloadFailed` / `.checksumMismatch`；权限不足 ← `.targetNotWritable` / `.backupFailed`。原型里的两句直接对应这两个 case 的 `userMessage`，实现时不要另写。
7. **说明区固定高 88pt**（原型内实测）：实现沿用 `SettingsReleaseNotesView.contentHeight = 132` 的固定高度 + 内部滚动思路，但窗口内可用高度更紧，建议按 88–100pt 取；说明为空（未检查 / 检查中）时整块隐藏，不占位。
8. **自动滚动**：进入 downloading / failed 时把更新卡滚进视野（`SettingsPageStack` 的 scrollToVisible），用 `scrollTo` 而非 `scrollIntoView`。
9. **演示件隔离**：顶部状态切换器 `data-od-id="demo-only:state-switcher"` 整块不进产品，实现时按 `07-contract` 的演示件表机械排除；`?state= &variant= &theme= &\#shot` 四个 URL 参数同理。

---

## 8. 待办 / 未验证

- **未验证：真实字节进度的刷新节拍**。原型用 CSS 动画模拟流光是 1.5s 线性循环；真实下载回调可能每 100–300ms 一次。实现时需确认「进度条宽度 transition 0.5s + 回调 200ms」不会互相打断（建议宽度 transition 降到 `--motion-fast` 或直接按帧更新）。
- **未验证：`readyToRelaunch` 的倒计时**。原型只画静态「已安装，即将重启」，没画 3-2-1 倒计时；若要倒计时需再确认「是否允许取消」。
- **未验证：深色下 B 版四行小条的 3pt 高度可辨识度**。深色截图里非活跃行的小条与轨道几乎同色（`--track #3a3a3e` vs 卡片底 `#2b2b2f`），需要真机 2x 下核对；如果太弱，B 版小条应改 4pt。
- **待用户拍板**：版 A 还是版 B（§2 取舍表）。拍板后清理落选版对应的 CSS 段（`.stagebar`/`.ticks` 或 `.steps`）与截图。
- **待用户拍板**：「检查更新」与「安装」两张卡合并成一张「更新」卡——这是用户「看不到进度」的直接成因（进度在下面那张卡、还要往下滚），但会动现有 `SettingsAboutPane` 的四卡结构（应用 / 检查更新 / 安装 / 会话 → 应用 / 更新 / 会话）。
- **待覆盖：`upToDate`（已是最新）**。原型 9 态里没画这一态（用户点名的是进度问题）；实现前需补一张「已是最新 · 上次检查 5 分钟前」的空态确认，避免它和 idle 混淆。
- **未跑**：`odops gallery` 对比页。本轮两版在同一份 HTML 里用 `variant` 切换，没另出并排对比页；若用户要并排选版，再补 `gallery`。
- **产物归档**：本目录 `_logs-archive/`（30 个过程日志）与 `_dark.html`（早期草稿副本）为本地过程件，不进 git；`odops keep --check` 前可清掉。

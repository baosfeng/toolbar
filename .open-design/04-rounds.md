# 04 返工轮记录

## r1 · 骨架三版（a / b / c）

- 用户反馈：**三版都不满意**，原话「可以拆分为子 tab」。
- 结论：结构方向错了 —— 不是「单页怎么排信息」，而是「信息要不要分页」。a/b/c 全部作为落选基线保留在 `03-layouts/`（未删，等 r2 选定后统一清理）。

## r2 · tab 结构三版（t1 / t2 / t3）

- 触发：r1 反馈。
- 只改一个方向：把一级内容拆成 3 个 tab。其余（真实数据、灰阶、320×≤600、无 AI/Token 字样）沿用。
- 三版差异只在 **tab 的位置与形态**：t1 顶部分段 / t2 底部 tab bar / t3 左侧竖向 rail。
- 本轮允许的唯一交互：tab 真实切换（已用 agent-browser 实测，见 05-checklist.md）。
- 相比 r1 的结构性变化：
  1. 一屏信息量下降，但每屏更聚焦（用户诉求「一次只看一件事」）；
  2. 浮层高度随内容自适应（网络页 ≈ 520pt，系统页 ≈ 320pt），比 r1 三版都矮；
  3. 「剪贴板」从一条入口行升级成一个完整页（5 条历史 + 设置），这是 r1 里被压缩掉的内容。
- 待办：用户挑定后，落选版 + 对比页清理；进入阶段 4 填充。

## r2 选定：t1 顶部分段控件

- decision：用户选定 t1（顶部分段），`cp 03-layouts/r2/t1.html 03-layout.html`，进入阶段 4–8。
- 选定即收敛，**清理清单（显式路径，不用通配符）**：
  - `.open-design/03-layouts/a.html`
  - `.open-design/03-layouts/b.html`
  - `.open-design/03-layouts/c.html`
  - `.open-design/03-layouts/r2/t2.html`
  - `.open-design/03-layouts/r2/t3.html`
  - `.open-design/03-compare.html`
  - `.open-design/03-compare.png`
  - `.open-design/03-r2-compare.html`
  - `.open-design/03-r2-compare.png`
- 保留：`03-layouts/r2/variants.md`、`04-rounds.md`、`05-checklist.md`、`03-layout.html`。

## r3 · 阶段 4–8 一次推进（2026-10-17）

- 4 填充：剪贴板改相对时间 + 类型标签；补两处空态（剪贴板 / 进程）；条目与设置行补可点语义。
- 5 交互：tab 点击 + ←/→、hover/focus-visible/active 三态、复制「已复制」1.6s 回退、自启动勾选态切换 + toast、设置/退出 toast、空态演示切换。
- 6 填色：apple 56 槽整段粘贴（含深色源值），上下行语义色派生文字级色，圆角/浮层材质/焦点环。
- 7 动效：浮层 120ms 淡入 + 2px 上移、tab 150ms 交叉淡入、hover 150ms、`prefers-reduced-motion` 全兜底。
- 8 原型：`08-prototype.html`，verify --browser P0 全过，深浅色截图各一张 320×600 落 `shots/`。
- 过程中修的坑：`verify --browser` 报 demo 标签对比度 3.33:1 → 改用 `--muted`；`agent-browser` 的 viewport 是 `set viewport`、深色是 `set media dark`（不是 `media`）。


## r4 · 定稿前修复（2026-10-17）

- 审查结论：P0=0，3 条 P1 + 6 条 P2，只改这些点，不重做结构、不换风格。
- P1：toast 加 `pointer-events:none`（不再挡住底部点击）；「近 7 日流量」→「近 6 日流量」；「剪贴板设置…」⌘⇧V → ⌘,。
- **decision（P1-2）**：选「标题对齐条数」而不是「补第 7 天」。理由：真实菜单是「今日」单独一行 + 逐日 `entries[1...]`（MenuBarManager.swift 406–430），原型里今日流量已在页首单独一行，日列表就是 6 天；补第 7 天会造出菜单里不存在的一行，且会让今日页首与列表最后一天出现同一天两个数值 —— 这正是要避免的冲突。
- P2：空态计数归零、hover 不覆盖选中强调蓝、示例 URL 换中性地址、tab↔pane 补 ARIA、退出文案与真实菜单一致、checklist 两处口径更正。
- 复跑 verify：exit 0，12 PASS / 2 WARN（两条 warn 均为桌面平台有意保留项）。截图补到 4 张（网络/剪贴板/系统浅色 + 网络深色）。

## r5 · 视觉层三版对照（2026-10-17）

- 用户反馈（原话）：「排版不合理，ui 不好看」——否决 08 的视觉质量。结构（t1 顶部分段 + 三页内容）保留，只重做视觉层。
- leader 诊断 6 条对应解决：① 等权清单 → 三版都用字号/行高/徽标/柱形拉开层级；② 没有主角 → 速率 26px 成为唯一 hero；③ 纯文字表 → 近 6 日全部图形化（柱状图）；④ 调试壳污染 → demo 壳移到面板下方 24px、11px muted；⑤ 层次留白 → 4pt 网格 + 组间距 12–20 + 材质（v1 毛玻璃）；⑥ 无身份识别 → 字母徽标 + 最新一天高亮。
- 三版方向与取舍见 `03-layouts/v/variants.md`：
  - **v1 精致原生**：毛玻璃材质 + 字母徽标 + 细柱状图（最新一天蓝）；系统一致性最好。
  - **v2 数据仪表盘**：sparkline + 双进度条 + 带宽占比条 + 带数值柱状图；密度最高、噪音也最高。
  - **v3 极简留白**：大留白少线条、Top 3 + 查看全部、紧凑柱形无标注；最克制但默认屏信息不全。
- 修掉的坑：面板阴影里的 `#000` 裸色值 → 补 `--shadow` token；`--meta` 在 10px 小字下 4.27:1 → 统一换 `--muted`；深色下 `--dark-accent-active` 太深（2.5:1）→ 改 `#409cff`。
- 交付：`03-v-compare.{html,png}` + `shots/v{1,2,3}-{light,dark}.png` 共 6 张。

## r6 · 定稿 v2 + 真实 App 图标（2026-10-17）

- 用户选定 **v2 数据仪表盘**，追加要求：「把图标等带进去，比如 app 的图标等等」。
- 定稿：`cp 03-layouts/v/v2.html 08-prototype.html`，并补齐 r4 已修项（toast `pointer-events:none`、近 6 日口径、`⌘,`、空态计数、hover 不盖选中、`aria-controls`/`tabpanel`/`aria-labelledby`、示例 URL、退出文案）。
- 本轮改动：
  1. 进程改为本机真实 5 个 App（Safari / Google Chrome / Terminal / Notes / Finder），图标取 `/tmp/appicons48/` 48×48 PNG 以 **base64 data URI 内嵌**，显示 20×20、`aria-hidden`；
  2. 剪贴板条目加类型图标（链接 / 命令 / 文本，线性 SVG），系统页加 Wi-Fi / 勾选 / 电源图标，三个 tab 加小图标；
  3. v2 视觉手段补语义：sparkline 注释写明真实数据源（`MenuBarManager.swift` 的 `downHistory` / `upHistory`，60 点 1s 采样）；今日进度条标签写明「占今日总量 80% / 20%」；进程占比条注释写明以列表最大进程为 100% 基线；近 6 日柱状图保留数值 + 10/16 高亮。
- 清理清单（显式路径，先记后删）：
  - `.open-design/03-layouts/v/v1.html`
  - `.open-design/03-layouts/v/v3.html`
  - `.open-design/03-v-compare.html`
  - `.open-design/03-v-compare.png`
  - `.open-design/shots/v1-light.png`、`.open-design/shots/v1-dark.png`
  - `.open-design/shots/v2-light.png`、`.open-design/shots/v2-dark.png`（先归档到 `history/`）
  - `.open-design/shots/v3-light.png`、`.open-design/shots/v3-dark.png`
  - 保留：`03-layouts/v/variants.md`、`03-layouts/v/v2.html`（作为定稿源）。


## r7 · 复审修复（2026-10-17）

- 复审结论：P0=0，3 条 P1（含 1 条 r4→r6 回归）+ 4 条 P2，只改这些点。
- P1：① 剪贴板条目恢复 `data-clip`/`role=button`/`tabindex`（回归修复，真点击验证「已复制」→1.6s 回退）；② 柱状图改固定柱区（grid 12/64/12 + `calc(--h*0.64px)`），实测 35.19/20.47/48/27.52/64/23.03；③ 自启动勾选图标随状态显隐 + 关闭态文字转 `--muted`。
- P2：空态选择器修正（`data-clip-list`）、系统页 IP/Wi-Fi 拆两行带图标、关闭态不用强调蓝、Terminal 图标深色衬底、checklist 裁切口径更正。
- 截图补：自启动开/关两态（浅深）+ 空态 1 张。

## r8 · 剪贴板历史面板三版（2026-10-17）

- 用户指出漏项：App 里贴屏幕底部的 640×260 剪贴板历史面板从未进原型；菜单栏面板验收挂起，先做这个。
- 需求单：`00-brief-clipboard.md`（640×260、贴底、不抢焦点、键盘优先）。
- 三版：p1 横向卡片流（640×260，现状结构 + 视觉升级）/ p2 紧凑纵向列表（640×360）/ p3 左列表 + 预览（760×340）。方向与取舍见 `03-layouts/clip/variants.md`。
- 共同：搜索实时过滤、类型过滤、↑↓ 选中、Enter/Esc 提示、⌘1–9 徽标、收藏星切换、空态、深浅色、真实 App 图标。
- 修的坑：`&#8984;`（⌘ 实体）被 verify 当成裸色值 `#8984` 误报 12 处 → 换字面字符后归零；`clip/` 目录未建导致首次生成失败。
- verify：三版 exit 0（`--browser`）。对比页 `03-clip-compare.{html,png}`，截图 `shots/clip-{p1,p2,p3}-{light,dark}.png`。

## r9 · 按设计体系重画（2026-10-17）

- 用户反馈：「p1 结构可以，但设计风格不喜欢」，要求用原型 skill 结合设计风格重画对比；范围扩到**菜单面板 + 剪贴板面板一起换**。
- 四个风格包：`raycast` / `linear-app` / `clean` / `notion`，各出 menu（320 宽，t1 三段 tab）+ clip（640×260，p1 卡片流）两页 = 8 页。
- 做法：每个包读 `odops style <id> --tokens`，`:root` 去注释后整段粘入，再按该包的真实视觉特征写 override（字重 / 圆角 / 边框阴影 / 密度 / 强调色预算 / 明暗基调），不是只换 token 颜色。
- 修的坑：① `--shadow` 初版追加在 `:root` 闭合后 → verify 报 1 处裸色值，改到 `:root` 内；② linear 的「已开启」用靛紫 `#5e6ad2` 在深底只有 3.71:1 → 改 `--accent-hover`（#828fff）；③ raycast 缺 `.bar.last` 高亮 → 补红色「最新一天」柱（红只做点状原则下的唯一例外，记在 variants）。
- 门禁：8 页全部 exit 0（P0=0）。共性 warn（非阻塞）：点击区 28px、12px 小字、clip 页 640 画布与 320 brief 不同源。
- 产物：`03-style-compare.{html,png}`（4 列）+ `shots/style-{raycast,linear,clean,notion}-{menu,clip}.png` 8 张。

## r9 · 剪贴板收敛稿（用户拍板后）

- 用户原话：「只做剪贴板的原型，之前的原型我挺满意的，别改了」「第一个没把剪贴历史突出，反而突出了软件名等不相关的内容」「菜单面板使用我之前满意的版本」。
- 决策：**菜单面板冻结**（`08-prototype.html` = v2 + 真实图标，不再改动、不再套任何新风格）；只重做剪贴板面板。
- 否决点（p1 的问题）：来源 App 名 / 相对时间 / ×N 粘贴次数被做成整行最显眼，剪贴内容反而成了次要——层级倒置。
- 本轮改动（`03-layouts/clip/final.html`）：
  1. 视觉语言与冻结菜单面板 v2 完全一致（同一套 apple 56 token、圆角 12/10、`backdrop-filter` 材质、1.5px 线性图标、深浅色）；
  2. 卡片 184×196，内容区约 130px（≥66%，7 行上限），文本 11–12px/1.5，`word-break:normal + overflow-wrap:break-word` —— 去掉了 p1 的 `developer.appl/e.com` 式词中断；
  3. 元信息降级：左上类型图标 12px + ⌘N 10px muted；右下相对时间 10px muted；来源 App **只留 12px 图标**（无文字）；粘贴次数 `×N` 移除；
  4. 选中态改 `1.5px accent 描边 + accent 5% 底色`，去掉 p1 的 scale(1.02) 与阴影跳变。
- **App 图标取舍（最终判断）**：保留，但只留 12px 图标在卡片右下角、与相对时间同一行；删除 App 名文字。理由见 `03-layouts/clip/variants.md`。
- 4 个风格产物（`03-layouts/style/*`）标注为**用户未选，待清理**（等用户验收 final 后再删）。

## r11 · 剪贴板收敛稿复审修复

- 复审确认层级倒置到位（App 名 0 命中、×N 已移除、内容区占 0.69、词中断 0 例）。
- **P1-1 ⌘1–9 直选**：补 `e.metaKey && /^[1-9]$/` 分支 → `select(idx)` + 与 Enter 相同的 toast。实测 Meta+3 → idx 2（第 3 张「周会纪要」）+ toast「已粘贴到前台 App」。
- **P1-2 ↑↓ 滚入可视区**：`select()` 内用 `getBoundingClientRect` 比较卡片与 `.cards` 容器，按差值调 `scrollLeft`（**未用 `scrollIntoView`**）。实测连按 6 次 ↓ → idx 6、scrollLeft=722、卡片 rect [573,757] 落在可视区 [131,769] 内。
- P2：示例内容换成中性真实文案（去 AI 字样与设计批注语气）；`.cards` 加 `role="listbox"`、卡片 `role="option"`；`00-brief-clipboard.md` 与 `07-contract.md` 注明 640×260 与菜单面板 320×600 不同源。
- 复跑 verify：**exit 0**，12 ok / 0 FAIL。

## r12 · 剪贴板字号与密度上调（用户：「字体太小，空间利用率不够」）

| 项 | 改前 | 改后 |
|---|---|---|
| 卡片正文 | 11px / 1.5 | **13px / 1.45** |
| 命令 / URL 等宽 | 11px | 12px（URL 加 `<wbr>` 断点，不在词中断） |
| meta（时间 / ⌘N） | 10px | 11px |
| 类型图标 | 12px | 14px |
| 工具条控件 | 12px / 高 26 | 13px / 高 24 |
| 面板内边距 | 12px | 10px |
| 工具条高 | 40px | 32px |
| 底部提示行高 | 24px | 24px（字 10→11px） |
| 卡片 | 184×196，padding 9/10 | **176×198**，padding 10 |
| 卡片 gap | 8px | 10px |
| 搜索框最大宽 | 320px | 400px（弹性，min 300） |

**实测验收数字**：卡片高 198 / 面板 260 = **76.2%**（≥74%）；正文 computed fontSize **13px**、lineHeight 18.85px、`.c-text` 高 132px → **7.0 行**（≥6）；卡片宽 176px，640 宽下 **3 张完整 + 1 张部分**（第 4 张露 72px ≈ 41%）；`scrollWidth == clientWidth`，无横向溢出；URL 断行点为 `.` / `/`，无词中断。
- 说明：lead 要求「第 4 张露 60%」，实测 176px 宽只能露 41%；若要 60% 需卡片宽降到 168px（3.6 宽 = 620）。本轮按明确给的 176px 执行，留待确认。
- verify：**exit 0**，11 ok / 0 FAIL。

## r13 · 剪贴板最后两处空间浪费

- **meta 两行合并成一行**：卡片底部改为单行 flex —— 左「类型图标 14px + ⌘N + 星标」，右「相对时间 11px + App 图标 12px」，行高 16px 贴底；省掉原来的「⌘1 ☆」独立一行，卡片内容区多出 22px 垂直空间。
- **URL / 命令 / JSON 等宽降一档到 12px**（正文文本仍 13px）：`.card[data-kind="link|cmd|json"] .c-text`。实测长 URL 每行从 **19.6 字符 → 21.3 字符**（卡内容宽 154px，字符宽 7.22px），`https://developer.apple.com/documentation/appkit` 少断一次（3 行）。
- 内容区 `flex:1` 且顶部对齐、meta 贴底，不再居中留白。
- verify：**exit 0**，11 ok / 0 FAIL。
- 卡宽保持 176px（按 lead 指令不降 168，优先保证字号）。

## r13.1 · 卡片内容垂直居中

- 问题：内容 3–4 行时全部压在上方、meta 贴底，中间留一大片空白 —— 正是用户抱怨的「空间利用率不够」的观感来源。
- 改法：文本内容外包一层 `.c-body{flex:1;min-height:0;display:flex;align-items:center}`，内容少时上下留白对称；内容多时自然占满。图片卡 `.c-thumb` 同样 `align-items:center`。`.c-foot` 加 `margin-top:auto` 仍贴底。
- 未动：卡宽 176、正文字号 13/12、meta 单行、`<wbr>` 断行规则、其他任何样式。
- verify：**exit 0**，11 ok / 0 FAIL。截图已重截。

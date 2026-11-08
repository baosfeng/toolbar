# Token tab · 4 屏原型（A / B 两版）

- 产物：`.open-design/harness-token-screens/screens.html`（单文件，1313 行，无外部依赖）
- 截图：`.open-design/harness-token-screens/shots/` 共 20 张 —— 16 张主图（A/B × 4 屏 × 浅/深）+ 4 张用量屏「滚到底」补图。320×600，jpg q80，最大 35KB
- 输入：`docs/设计/harness-token-监控-原型/交接.md`（口径与量级）、同目录 a/b/c 原型里的 34 天日表 / 项目表 / 模型表 / 今日与昨日 24 桶、`.open-design/02-style.md`（apple 尺度取舍）、`NetworkMonitor/…/PaneCardStyle.swift`（颜色 / 字号 / 圆角，只读参考）

## 1. 怎么打开

```
file:///Users/bsfeng/IdeaProjects/toolbar/.open-design/harness-token-screens/screens.html#v=A&s=overview&theme=light
```

URL 片段参数（也可直接点面板里的控件）：

| 参数 | 取值 | 说明 |
|---|---|---|
| `v` | `A` / `B` | 两个版本 |
| `s` | `overview` / `usage` / `cache` / `rank` | 4 屏 |
| `theme` | `light` / `dark` | 浅 / 深（缺省跟随系统） |
| `range` | `today` / `d7` / `d30` | 范围分段 |
| `day` `mode` `metric` `dim` | `yest` / `cmp` / `req` / `model` | 二级开关的初始态 |
| `scroll` | `bottom` | **只给截图用**：加载后把内容区滚到底 |

右上角（320 视口之外、不进产品）有演示控件：A/B 切换、浅/深切换，标了 `data-od-id="demo-only:controls"`。

## 2. 层级：一条屏切换 + 一条范围切换

| 层 | 控件 | 规格 | 为什么这么分 |
|---|---|---|---|
| 应用级 | 网络 / 剪贴板 / 传送 / 额度 / Token | 26pt，5 段，带 12px 图标 | 不属于本页，只保留上下文 |
| 页头 | Token 用量 · 全部 DSH 会话 · 刷新 | 22pt | 页名 + 数据源 + 刷新 |
| **一级：屏** | 概览 / 用量 / 缓存 / 排行 | **28pt 实心胶囊**，选中块用页面底色抬升 + 1px ring | 换的是「整页内容」，权重最高 |
| **二级：范围** | 今日 / 7 天 / 30 天 | **20pt 纯文字 + 2px accent 下划线**，无容器、无底色 | 换的是「同一页的统计窗口」 |

差异只靠「容器 + 抬升」vs「纯文字 + 下划线」，不靠字号大小 —— 320pt 里字号一挤就分不清主次。范围切换只影响汇总、天趋势与排行分母；**按小时图有自己的今日/昨日开关，不受范围影响**（卡头写死「今日 · 截至 14:05」）。

## 3. 四屏内容

### 概览（3 块 + 跳转）
1. **Hero**：范围总量（含缓存读，量级口径）`355.8M` + 较昨日同期 `×19.2` + 右上「● 14:05」数据时刻；B 版多一条缓存读/未缓存/输出的组成条 + 占比图例。
2. **四族卡 2×2**：未缓存输入 4.98M（1.4%）· 输出 2.11M（0.6%）· 缓存读 348.7M（98.0%）· 请求数 3,107（占 30 天 7.7%）。每张卡：值 + 占比 + 千分位全值 + 近 7 天 sparkline。
3. **近 7 天迷你条**：合计 2.42B / 日均 345.4M / 峰值 10-18 566.7M / 命中率 98.9%。
4. 三枚跳转（按小时 / 缓存明细 / 排行）—— 二级页的入口。

### 用量（3 块，可滚动）
1. **按小时主图**：24 桶；`今日 | 昨日`、`堆叠 | 对比`、`Token | 请求数` 三组开关；堆叠自下而上「缓存读 → 未缓存输入 → 输出」；当前时刻竖线；hover 出「缓存读/未缓存/输出/请求数」明细。
2. **近 14 天**（范围切 7 / 30 天时窗口跟着变）：无会话日画斜纹，不插值、不补假数据；今日柱用 `--fg` 高亮；图例写明「每日合计 / 无会话 / 今日」。
3. **今日 vs 昨日同期**：0–14 时四行小表（今日 / 昨日同期 / 倍数），倍数为主信号；下方一句说明为什么倍数偏大。

### 缓存（3 块 + 口径句）
1. **大命中环** 98.6% + 缓存读 348.7M / 未缓存 4.98M / 复用倍率 70.1×。
2. **三块固定口径**：今日 98.59% · 近 30 天 98.45% · 今日 24 桶最低 97.4%（10 时）。条形统一用 **95–100% 缩放刻度**（0–100 时三块都贴着满格，看不出差别），24 桶另有热条 + hover 看每桶命中率。
3. **缓存读 vs 未缓存分解**：100% 堆叠条 + 今日 24 桶命中率折线（面积图，截止到 14 时，不向右补零）。
4. **口径句**：命中率 = 缓存读 ÷（缓存读 + 未缓存输入）；命中部分单价更低，**比例高不等于省得多**，本页不折算金额。

### 排行（1 块）
维度切换（按项目 / 按模型）+ 全宽占比条 + Top 8 + 其余合并。每行：名次 / 名称 / 会话数·请求数 / 值 / 占比 / 占比条。排序口径写在卡头「输入 + 输出，不含缓存读」，页脚写合计 186.7M。

## 4. A / B 差异

| 维度 | A（4 屏等权） | B（概览更重、用量更强） |
|---|---|---|
| Hero 主数字 | 24pt | 30pt |
| Hero 组成条 | 无 | 有（缓存读 98.0% / 未缓存 1.4% / 输出 0.6%） |
| 四族卡 | 56pt 高，sparkline 44×12 | 61pt 高，56×16 |
| 按小时图 | 132pt，无 y 轴 | 176pt，y 轴 + 3 条网格线 |
| 14 天趋势 | 64pt | 96pt |
| 命中环 / 折线 | 86pt / 40pt | 92pt / 44pt |
| 排行副信息 | 会话数 · 请求数 | + 缓存读 |
| 首屏高度 | 概览 / 缓存 / 排行 **444/444 不滚动**；用量 588 | 概览 / 缓存 / 排行 444/444；用量 **664**（滚 220） |

两版共用同一份 DOM、同一份数据与同一套 token，差异全部走 `--hero-num` / `--chart-h` / `--trend-h` / `--ring` 等屏权重变量 + 三个 B 专属模块（组成条、图例数值、排行缓存列），不存在两套结构。

## 5. 取舍

- **A 的取舍**：四屏分量一致，谁都不抢戏，任何一屏打开都是同一节奏；代价是 Hero 只给一个总数 —— 335M 里 98% 是缓存读这件事，得往下看四族卡才知道。
- **B 的取舍**：第一屏就回答「今天多烧了多少 + 大头是不是缓存」，用量图有 y 轴可以读数；代价是用量屏必须滚动 220pt，且 Hero 更高，概览的四族卡离折线更远。
- **共同代价**：用量屏 3 个图卡放不进 444pt 的一屏，一定要滚动 —— 这是「一屏 8 块」改成「3 块 + 二级页」的必然结果，不是没排好。
- **推荐 B**。用户反馈的是「太密集」而不是「信息少」：B 把密度从「一屏 8 块」降成「一屏 3 块」，同时把最关键的两个数（总量 vs 昨日同期、缓存占比）在第一屏讲完；A 更均匀，但概览的「为什么这么大」要靠下钻。若担心滚动，可把 B 的用量图降到 160pt（只影响这一屏）。

## 6. 数据口径与自洽

- **今日** = 交接.md 的 10-24 行：4,976,763 / 2,107,626 / 348,674,382 / 3,107。
- **近 7 天** = 10-18…10-24 共 7 个有数据日：25.81M / 12.39M / 2.379B / 17,185（合计 2.42B）；对比周期 = 10-11…10-17，+12.3%。
- **近 30 天** = 09-25…10-24 窗口内 **19 天有数据**（09-27→10-07 无会话）：86.41M / 38.15M / 5.499B / 40,255（合计 5.62B）。数据只覆盖 34 天，30 天范围没有可比上一周期 → Hero 显示「—」并写明「30 天窗口内 19 天有数据 · 无可比同期」，不编一个假同期。
- **累计 34 天** = 123,844,537 / 62,819,879 / 10,162,026,489 / 72,683 —— 与日表逐项求和完全相等（`node` 复算过）。
- **按小时的归一**：今日 24 桶抓到 14:05，抓取时刻晚于日表快照，整体比日表大 1.16 倍；按列等比归一到日表（合计精确等于 4,976,763 / 2,107,626 / 348,674,382 / 3,107，末位差额补进峰值桶），保证同一屏里 hero、图例、请求数互相对得上。昨日 24 桶是全天数据，本身与 10-23 行相等。
- **「较昨日同期」= 00:00–14:05 同一时钟窗口**。昨日该窗口只有 18.5M（昨日用量集中在 19–23 时），所以是 ×19.2；对比卡里写明了原因，避免被读成夸张数字。
- 所有占比 / 命中率 / 倍率 / 日均都来自同屏数据现算，没有硬编码的假比值。

## 7. 与实现同源 / 有意偏离

**同源**（照 `PaneCardStyle` 取值）：四族色（浅/深各一套，`uncached/cache/output/request` + ink + cardFill）、卡片底 `#F5F5F7/#26262A`、卡片圆角 9、轨道 `#E4E4EA/#39393F`、网格、hairline、字号梯（hero 24 / 卡值 19 / meta 10 / axis 8.5 / segment 10.5 / chip 9.5）；深色只重绑语义 token，原始值只在 `:root` 出现一次。

**有意偏离**（写在这里，不偷偷改实现口径）：
1. 卡片内边距 7/4（Swift）→ 9/7（原型）：原型里要放折线与双列文字，2pt 会更糊。
2. 小字颜色不用 `--meta` / `--muted` 原值：`#86868b` 压白底对 9–10px 只有 3.3:1、`#6e6e73` 压 `#eeeff2` 只有 4.4:1（`odops verify` 会判 P0）。按 `02-style.md` 记过的坑派生 `--meta-text` / `--muted-text`（向 `--fg` 混）。
3. 触控目标是 26–30pt（< 44pt）：桌面浮层，`verify --platform desktop` 只报 warn。
4. 页头 h1 用 `--font-body` 而非 `--font-display`：13pt 的菜单标题在 macOS 上就是 SF Pro Text，Display 档留给 ≥20pt。

## 8. 门禁证据

```
$ odops verify .open-design/harness-token-screens/screens.html --template web-prototype --platform desktop --browser
  ok    单文件自包含（无外部 script / link / img / 字体）
  ok    CSS 内联
  ok    :root 含核心 6 个语义变量
  ok    :root 是官方 56 槽的完整粘贴
  ok    所有颜色都走 token，无裸色值
  ok    5 个顶层区块都有 data-od-id
  ok    强调色用法 0 次
  ok    画布宽与澄清单一致（320px）
  ok    官方 anti-slop lint（--fail-on p1）干净
  ok    无横向溢出
  ok    文本对比度达标（正文 4.5:1 / 大字 3:1）
  warn  有 20 个交互元素高度 <44px（触屏平台是 P0）   ← 桌面浮层，非阻塞
  warn  小于 14px 的文字                                ← 与实现字号梯同源，非阻塞
exit=0

$ odops lint .open-design/harness-token-screens/screens.html --fail-on p1
clean — 0 findings (P0 0 · P1 0 · P2 0)
exit=0
```

**320 宽实测**（agent-browser，viewport 320×600，A/B × 4 屏 × 浅/深 共 16 个状态）：

```
A/overview/light: 320=320  body 320=320  innerOverflow=0  scrollH=444
A/usage/light:    320=320  body 320=320  innerOverflow=0  scrollH=588
A/cache/light:    320=320  body 320=320  innerOverflow=0  scrollH=444
A/rank/light:     320=320  body 320=320  innerOverflow=0  scrollH=444
B/overview/light: 320=320  body 320=320  innerOverflow=0  scrollH=444
B/usage/light:    320=320  body 320=320  innerOverflow=0  scrollH=664
B/cache/light:    320=320  body 320=320  innerOverflow=0  scrollH=444
B/rank/light:     320=320  body 320=320  innerOverflow=0  scrollH=444
（dark 8 个状态同上）
```

**真交互实测**（agent-browser 真点击，非 `el.click()`）：4 屏切换 ✓ · 3 个范围 ✓ · 排行维度 ✓ · 今日/昨日 ✓（24 列、昨日全天）· 堆叠/对比 ✓（灰柱为对照日）· Token/请求数 ✓（请求数合计 3,107）· hover 出明细 ✓ · 刷新转圈 ✓ · 浅/深 ✓ · 概览跳转 ✓。

## 9. 复现

`odops shot` 只吃文件路径、不吃 URL 片段，所以截图用一个 320×600 的 iframe 包装页传状态（包装页只在 `/tmp`，不进仓库）：

```bash
cat > /tmp/A-usage-light.html <<'EOF'
<!doctype html><meta charset="utf-8"><style>html,body{margin:0;padding:0;width:320px;height:600px;overflow:hidden}iframe{display:block;width:320px;height:600px;border:0}</style><iframe src="file:///Users/bsfeng/IdeaProjects/toolbar/.open-design/harness-token-screens/screens.html#v=A&s=usage&theme=light"></iframe>
EOF
odops shot /tmp/A-usage-light.html --width 320 --height 600 \
  --out .open-design/harness-token-screens/shots/A-usage-light.jpg
```

批量（8 状态 × 浅深）：

```bash
for v in A B; do for s in overview usage cache rank; do for t in light dark; do
  sed "s|#v=A&s=usage&theme=light|#v=$v&s=$s&theme=$t|" /tmp/A-usage-light.html > /tmp/shot.html
  odops shot /tmp/shot.html --width 320 --height 600 \
    --out .open-design/harness-token-screens/shots/$v-$s-$t.jpg
done; done; done
```

## 10. 待拍板（3 条）

1. **选 A 还是 B**（推荐 B）。
2. **概览的「总量」口径**：现在 hero 是 in+out+cache 的合计（355.8M），明确标了「含缓存读 / 单价不同只看量级」。要不要改成「缓存读为主 + 另两项小字」，或干脆分三行？
3. **「较昨日同期」的展示**：现在给倍数（×19.2）并附一句解释。若担心倍数读起来像异常，可改成「+1,820%」或只给百分比不解释 —— 但数据就是这个形状（昨日白天几乎没跑）。

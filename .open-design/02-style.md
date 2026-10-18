# 02 设计风格

- style: `apple`（默认 iOS / macOS 内置包）
- 选择依据：项目自有风格「无」（`odops doctor` 已确认）；用户未另行指定；本项目是 macOS 原生菜单栏应用，apple 包与 `.reasonix/skills/toolbar-ui-standards` 的系统色 / SF 字体 / 4pt 基准语义天然对齐。

## 与项目 UI 规范的语义映射

| 项目规范 | apple 包 token | 用法 |
|---|---|---|
| `systemGreen` 下行 | `--success`（#16a34a） | 下行数值与小箭头 |
| `systemOrange` 上行 | `--warn`（#eab308） | 上行数值与小箭头 |
| `labelColor` | `--fg`（#1d1d1f） | 主文本、进程名 |
| `secondaryLabelColor` | `--muted` / `--meta` | 次要说明、快捷键、单位 |
| `monospacedDigitSystemFont` | `--font-mono` + `font-variant-numeric: tabular-nums` | 所有速率 / 流量 / 日期数字 |
| 4pt 基准 | `--space-1: 4px` 起 8 档 | 全部内边距与行距 |
| 深浅色自适应 | 阶段 6 用 `prefers-color-scheme` 重绑语义 token | 深色只换绑定，不换结构 |

> ⚠️ 阶段 6 填色时的已知坑（记录在案）：`--success` / `--warn` 原色压白底做 12px 小字分别只有 3.03:1 / 4.44:1，不够 4.5:1。填色阶段需要派生"文字级"语义色（向 `--fg` 混），**图标与数字都用派生色**；SDK 里的 systemGreen 在深色下同理。

## token 表（`odops style apple --tokens` → `:root` 56 槽位，逐字取用）

```css
--bg: #ffffff;              --surface: #f5f5f7;        --surface-warm: #fbfbfd;
--fg: #1d1d1f;              --fg-2: #424245;           --muted: #6e6e73;        --meta: #86868b;
--border: #d2d2d7;          --border-soft: #e8e8ed;
--accent: #0071e3;          --accent-on: #ffffff;      --accent-hover: #0077ed; --accent-active: #0066cc;
--success: #16a34a;         --warn: #eab308;           --danger: #dc2626;
--font-display: "SF Pro Display","SF Pro Icons","Helvetica Neue",Helvetica,Arial,sans-serif;
--font-body:    "SF Pro Text","SF Pro Icons","Helvetica Neue",Helvetica,Arial,sans-serif;
--font-mono:    "SF Mono",ui-monospace,"JetBrains Mono",Menlo,Monaco,Consolas,monospace;
--text-xs: 12px;  --text-sm: 14px;  --text-base: 17px;  --text-lg: 21px;
--text-xl: 28px;  --text-2xl: 40px; --text-3xl: 56px;   --text-4xl: 80px;
--leading-body: 1.47;       --leading-tight: 1.05;      --tracking-display: -0.015em;
--space-1: 4px;  --space-2: 8px;  --space-3: 12px;  --space-4: 16px;
--space-5: 20px; --space-6: 24px; --space-8: 32px;  --space-12: 48px;
--section-y-desktop: 100px; --section-y-tablet: 64px;   --section-y-phone: 40px;
--radius-sm: 8px; --radius-md: 12px; --radius-lg: 18px; --radius-pill: 980px;
--elev-flat: none;  --elev-ring: 0 0 0 1px var(--border);  --elev-raised: 0 12px 32px rgba(0,0,0,0.08);
--focus-ring: 0 0 0 4px color-mix(in oklab, var(--accent), transparent 65%);
--motion-fast: 150ms; --motion-base: 220ms;
--ease-standard: cubic-bezier(0.28, 0, 0.22, 1);
--container-max: 1024px; --container-gutter-desktop: 22px;
--container-gutter-tablet: 18px; --container-gutter-phone: 16px;
```

## 尺度取舍（有意偏离，必须记录）

apple 包是**营销页尺度**：`--text-base: 17px` 是网页正文基准，`--text-2xl: 40px` 是活动大标题。320pt 菜单浮层里直接套会撑爆：

| 角色 | 原型用值 | 对应 apple token | 说明 |
|---|---|---|---|
| 菜单项 / 进程名 | 13px | 介于 `--text-xs`(12) 与 `--text-sm`(14) 之间 | macOS NSMenu 原生字号 13px，不取 17 |
| 次要说明 / 快捷键 | 11–12px | `--text-xs`(12) | 快捷键与单位 |
| 分区小标题 | 12px + `--muted` | `--text-xs` | 不用 `--text-sm` 及以上 |
| 卡片内主数值（速率） | 21–24px | `--text-lg`(21) | 不用 `--text-2xl`(40) |
| 大数值（hero 速率） | 24–28px | `--text-xl`(28) | 上限，浮层不需要 40+ |
| 面板总标题 | 15px | 介于 `--text-sm` / `--text-base` | 320pt 宽下不用 Display 级 |

行高（`--leading-body: 1.47`）在 13px 菜单行里偏大 → 菜单行固定 22pt 高（4pt 基准 24 的紧凑变体），**属于对 token 的有意偏离**，记在 `05-checklist.md`。

## 骨架阶段的状态

阶段 3 的 token 只用 6 个占位变量（灰阶）：

```
--bg:#ffffff  --surface:#f2f2f4  --fg:#1c1c1e  --muted:#6e6e73  --border:#d8d8dc  --accent:#1c1c1e
```

阶段 6 才把上面 56 槽位整段替换进来；现在不做 accent 预算、不做颜色对比度判定（骨架阶段判定项只有结构与 P0 阻塞项）。

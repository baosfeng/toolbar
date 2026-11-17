# Paste（pasteapp.io）能力与 UI 规格提炼

> 用途：给 Clipboard 产品实现方（macOS 客户端）的可落盘规格。
> 素材：/tmp/paste-research/txt/*.txt（20 篇帮助页正文）、pasteapp.io 首页/产品页与其 5 段官方动效视频、帮助页配图 17 张。
> 像素数据均来自截图量测（脚本见本章「量测方法」），未量到的项显式标 **未量测**。

---

## 0. 结论速览

1. Paste 的产品骨架 = **"常驻后台的剪贴板历史" + "可共享的 Pinboard 收纳" + "一个浮在所有 App 之上的横向面板"**。单一列表不是主角，横向卡片流 + 顶部 Pinboard 标签才是。
2. 键盘是一等公民：打开面板后**不用点任何东西**就能完成 搜索→选择→粘贴（⌘F / ←→ / Return / ⇧Return / ⌘1–9）。
3. 视觉上最独特的一招：**卡片头部颜色 = 来源 App 的主题色，头部图标 = 来源 App 的图标**，类型名只是文字标签。这让"从哪复制的"在 0 认知成本下被识别。

---

## 1. 功能规格表

优先级：**P0** = 没有它产品不成立；**P1** = 差异化与日常高频；**P2** = 加分/长尾。
来源列 = 帮助页文件名（/tmp/paste-research/txt/）。

### 1.1 唤出与关闭

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 唤出面板 | ⇧⌘V（Activate Paste，可改键/可清空） | 显示/隐藏 Paste 窗口，获得焦点 | 清空快捷键后仍可从菜单栏 P 图标打开；快捷键只由用户按键或其它宏触发，Paste 不会自己弹出 | P0 | keyboard-shortcuts.md, stop-paste-popping-up.md |
| 关闭面板 | Esc | 立即隐藏窗口，不改变剪贴板 | — | P0 | keyboard-shortcuts.md |
| 菜单栏常驻 | 后台运行 | 关窗不停采集；App Store 版有 "Run in background" 开关 | 关掉后台开关后 macOS 回收进程会导致停止采集 | P0 | what-paste-captures.md |
| 暂停采集 | ⌘T（或菜单栏 Pause Paste） | 选定时长内不记录任何复制 | 时长由用户选择，到点自动恢复 | P1 | exclude-apps.md |

### 1.2 Quick Paste（数字快贴）

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 快捷粘贴 1–9 | 先 ⇧⌘V 打开面板，**按住 ⌘ + 数字 1–9** | 直接粘贴当前列表第 N 项并关窗（不经过 Return） | 必须面板已打开；只覆盖当前列表可见顺序的前 9 项；**不支持为单个条目绑定自定义快捷键**（官方称在 roadmap） | P0 | quick-paste-with-numbered-shortcuts.md |
| 纯文本快捷粘贴 | ⇧⌘1–⇧⌘9 | 同上但剥格式 | 与上一行同源，⌘/⇧ 修饰键可在 Settings→Shortcuts 里换成任一单键 | P1 | keyboard-shortcuts.md |
| 修饰键可换 | Settings→Shortcuts → Quick Paste / Plain Text mode 两行 | 把 Quick Paste 的 ⌘、纯文本的 ⇧ 换成 Command/Shift/Control/Option 任一单键 | 是"修饰键"而不是完整快捷键 | P2 | paste-as-plain-text.md, keyboard-shortcuts.md |

### 1.3 选择与粘贴

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 单选 | ← / → | 移动选中项，面板内循环 | ⌘↑ 首项、⌘↓ 末项 | P0 | keyboard-shortcuts.md |
| 多选 | ⇧← / ⇧→ 扩选；⌘A 全选；⇧-click 范围选 | 可选中多项一起粘贴 | 多选粘贴按列表顺序输出；搜索结果里 ⌘A 选中的是**全部列表**范围内的命中项 | P0 | keyboard-shortcuts.md, organize-with-pinboards.md |
| 粘贴 | Return 或双击 | 把选中项写入系统剪贴板并（有辅助功能权限时）直接粘贴到前台 App | **单击只选中**，不粘贴也不写剪贴板 | P0 | keyboard-shortcuts.md, copy-paste-not-working.md |
| 直接粘贴到其它 App | 同上 | 通过辅助功能权限向前台 App 发送 ⌘V | 无辅助功能权限时降级为"只写剪贴板"，用户自己 ⌘V；macOS 升级后权限可能被静默关闭，需移除再重新添加（不能只关开关） | P0 | paste-directly-to-other-applications.md |
| 复制到剪贴板 | ⌘C | 只写剪贴板，不粘贴 | — | P1 | keyboard-shortcuts.md |
| 打开链接/文件 | ⌘O | 用默认 App 打开 | — | P1 | keyboard-shortcuts.md |
| 预览 | Space（Quick Look） | 浮层预览原内容 | — | P1 | keyboard-shortcuts.md |
| 删除 | Delete | 删除选中项（可 ⌘Z 撤销） | 删除 pin 过的条目会同时从 Pinboard 移除 | P0 | keyboard-shortcuts.md |

### 1.4 Pinboard（分组收纳）

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 新建 | 工具栏 + 按钮 / ⇧⌘N | 弹命名+选颜色，建成后进入标签行 | 名称与颜色必填；iOS 上在 pinboards 列表里的 + | P0 | organize-with-pinboards.md |
| 切换 | ⌘→ / ⌘←，或点击标签 | 在 Clipboard 与各 Pinboard 之间切换 | 这两个快捷键可改键 | P0 | keyboard-shortcuts.md |
| 加入 | 右键 Pin → 选目标板；或 Mac 上拖拽卡片到标签/板 | 条目进入该板 | **一条目同时只能属于一个板**；拖进新板即从旧板移出 | P0 | organize-with-pinboards.md |
| 批量加入 | 先 ⌘A / ⇧-click 选多项，右键 Pin → 选板 | 一次钉多张 | 搜索结果里全选会把已在其它板的条目也带上 | P1 | organize-with-pinboards.md |
| 不移除来源 | — | pin 后仍留在剪贴板历史 | 两处都能 unpin；离开历史后仍留在板上 | P0 | organize-with-pinboards.md |
| 排序 | 板内拖拽；标签行拖拽 | 自定义顺序 | — | P1 | organize-with-pinboards.md |
| 改名/删除 | 右键菜单 | 删除板会连带删除板内全部条目 | 这是不可逆删除，实现方建议二次确认 | P1 | organize-with-pinboards.md |
| 共享 | 右键 Share Pinboard / Manage Shared Pinboard | iCloud 原生共享；可设 只读 / 受邀可编辑 / 公开链接；可停止共享 | 协作者须装 Paste 且登录 iCloud；停止共享立即从所有人设备移除 | P2 | shared-pinboards.md |
| 团队授权 | 网站购买 seat，一把 license key 多设备激活 | 与 iCloud 家庭共享不同 | 属商业功能，不在客户端核心 | P2 | paste-for-teams.md |

### 1.5 Paste Stack（临时顺序栈）

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 开启栈 | ⇧⌘C（Activate Paste Stack） | 此后**每一次 ⌘C 都按顺序进栈**（Paste 向前台 App 发 ⌘C 抓取选择内容） | 清空该快捷键等于彻底关闭栈 | P0 | using-paste-stack.md, stop-paste-popping-up.md |
| 出栈粘贴 | ⌘V | 按栈方向（默认自上而下）依次粘贴 | 需要辅助功能权限 | P0 | using-paste-stack.md |
| 反转方向 | 点箭头按钮 | 改为自下而上出栈 | — | P2 | using-paste-stack.md |
| 自动消耗 | 每项被粘贴后 | 该条目自动从栈中消失（一次性） | — | P0 | using-paste-stack.md |
| 移除单项 | 右键 Delete / 双指左滑 | 从栈中删掉 | — | P1 | using-paste-stack.md |

### 1.6 编辑、命名、纯文本

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 编辑内容 | ⌘E 或右键 Edit | 就地编辑且**只改这一条**，保存后覆盖原条目、保留原格式 | 图片有旋转/提取文字等快捷动作；macOS 26+ 出现 Writing Tools | P0 | edit-items-before-pasting.md |
| 重命名 | ⌘R / 右键 Rename / 直接点标题 | 给条目起标题（卡片上显示为标题而非类型名） | 命名只是标签，不改内容 | P0 | edit-items-before-pasting.md |
| 新建文本条目 | ⌘N | 新建一条空白文本并进入编辑 | — | P1 | keyboard-shortcuts.md |
| 单条纯文本粘贴 | 面板内 ⇧Return，或右键 Paste as Plain Text | 剥格式粘贴该条 | ⇧Return **必须在 Paste 窗口内按**，在目标 App 的输入框里按只是换行 | P0 | paste-as-plain-text.md |
| 全局纯文本 | Settings→General → Always paste as Plain Text | 所有条目都剥格式粘贴 | Paste **不会改写系统剪贴板里的既有内容** | P1 | paste-as-plain-text.md |
| 撤销 | ⌘Z | 撤销删除/编辑等操作 | — | P1 | keyboard-shortcuts.md |

### 1.7 搜索与过滤

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 进入搜索 | 面板打开后直接打字，或 ⌘F | 即打即搜（增量） | ⌘F 在搜索已激活时切换为"显示全部过滤器" | P0 | search-and-filters.md |
| 在搜索框与结果间切换 | Tab | 焦点在两区间来回 | — | P1 | search-and-filters.md |
| 从搜索直接粘贴 | 输入后 Return → ←/→ 选 → Return | 第一次 Return 把焦点移到结果（结果保持过滤），再 Return 粘贴；Esc 退出搜索 | 结果出现时**始终有一项被选中** | P0 | search-and-filters.md |
| 过滤器 | 输入时在搜索框内出现候选（类型/App/日期/设备），点击右侧 ≡ 展开全部 | 选中后变成搜索框内的**token 芯片**，可与文字混排 | 激活的过滤器常驻可见、可叠加；搜索范围含已 pin 条目 | P0 | search-and-filters.md |
| 搜索图片内文字 | 直接输入 | OCR 命中并在图片预览里**黄底高亮关键词** | — | P1 | search-and-filters.md |
| 跳回原位置 | ⌘G（单选时）或右键 Show in → Clipboard / 板名 | 关闭搜索视图并定位到该条目所在的列表 | Show in 只在条目不在当前列表时出现 | P2 | search-and-filters.md |

### 1.8 采集、保留、隐私

| 功能 | 触发 | 行为 | 边界与例外 | P | 来源 |
|---|---|---|---|---|---|
| 自动采集 | 后台常驻 | 文本/链接/图片/文件/颜色都存 | iOS 后台读不到剪贴板，只在打开 App、分享扩展、Paste 键盘时采集；iPad 分屏常驻可自动采集 | P0 | what-paste-captures.md |
| 颜色识别 | 复制 6 位 hex | 生成 Color 条目（色块 + hex） | 必须像颜色：带 # 或至少含一个 A–F；`#FFF`、`rgb()`、色名、夹在文字中的 hex 都按文本存；纯 6 位数字（如 235442）仍按文本，避免验证码变色块 | P1 | what-paste-captures.md |
| 保留期限 | Settings→General → Keep History：1 天/1 周/1 月（默认）/1 年/永久 | 超期未 pin 的条目自动清除 | **pin 过的与板内条目永不随期限删除**；缩短期限时若已有更老历史，会询问是否立即删除且不可撤销 | P0 | control-history-retention.md |
| 清空历史 | Settings→General → Erase History（iOS 在列表名 → ⋯ → Erase） | 一次清掉全部历史 | pin 条目与 Pinboard 不受影响 | P1 | control-history-retention.md |
| 排除 App | Settings→Privacy → Ignore Applications（+/− 增删） | 该 App 内的复制不再记录 | 只影响**新复制**，历史里的旧条目要手动删；判据是"复制那一刻你所在的前台 App"；Apple 密码 App 默认在列表里 | P0 | exclude-apps.md |
| 忽略临时内容 | Settings→Privacy 开关 | 跳过 App 标记为临时的剪贴板内容 | — | P1 | exclude-apps.md |
| 忽略机密内容 | Settings→Privacy 开关 | 识别为密码/敏感数据时跳过 | 部分密码管理器浏览器扩展的复制方式检测不到，此时需把浏览器整个加入排除名单 | P0 | exclude-apps.md |
| 本地存储 + iCloud 同步 | Settings→General → iCloud sync（逐设备开关） | 数据只在设备与用户私有 iCloud，不经 Paste 服务器 | 首次同步大历史需要几分钟 | P1 | where-paste-stores-your-data.md |
| Intelligent Clipboard | 工具栏 ✨Suggestions | 依据前台 App 场景把最可能用到的历史项排前 | 需 macOS 26+ 与 Apple Intelligence；需屏幕录制权限；只在窗口打开时读取前台 App，关窗即丢；被排除的 App 不读、密码框不产生建议；右键按钮可 Turn Off | P2 | intelligent-clipboard.md |
| MCP 服务 | Settings→Intelligence → MCP & AI tools → Enable MCP → Connect AI Tool | 本机起 MCP server 让 Claude/Codex/Cursor 等检索历史 | 仅 Mac；只在你批准的连接下开放；连接方可能把内容发给自己的模型方 | P2 | paste-mcp.md |

### 1.9 键盘全表（可改键的只有 4 组，其余固定）

固定：Esc、←/→、⌘↑/⌘↓、⇧←/⇧→、⌘A、Return、⌘C、Space、⌘O、⌘R、⌘E、⌘N、Delete、⌘Z、⌘F、Tab、⌘G、⌘T、⌘,、⌘Q。
可改：Activate Paste（⇧⌘V）、Activate Paste Stack（⇧⌘C）、Show next/previous Pinboard（⌘→ / ⌘←）、Quick Paste 与 Plain Text 的修饰键。（keyboard-shortcuts.md）

---

## 2. 视觉规格

### 2.1 量测方法与坐标系

- 主量测图：官方产品视频 `card-2.mp4`（2400×916）第 5 帧，面板区域裁切 `crop-c2.png`（1800×740，原点在面板左上外 11/8 px）。
- 交叉校验图：搜索帮助页配图 `img-3.205-hsh03iw1m.png`（1680×800）、`img-2.1opqmoapliv33.png`、pinboard 配图 `img-1.16h379ecfuph7.png`。
- **pt 换算未标定**：视频无 DPI 元数据，若按"面板宽约 680–720 pt"（macOS 浮窗常见尺寸）反推，比例约为 **2.5–2.6 px/pt**。下表的 px 是量测值，pt 是估算值，实现时请以 **% 比例**为准再缩放到自选面板宽度。

### 2.2 面板形态与位置

| 项 | 量测值 | 比例 | 备注 |
|---|---|---|---|
| 面板尺寸 | 1780 × 719 px | 宽高比 **2.48 : 1** | 横向长条，非侧栏 |
| 面板圆角 | 约 40 px（估） | ≈ 5.6% 面板宽 | **未精确量测**（与卡片圆角同族） |
| 面板背景 | `#F6E1C9`（暖米色，不透明/近不透明） | — | 不是深色玻璃拟态；这是 Paste 的品牌底色 |
| 面板与桌面关系 | 浮在 App 之上、贴近屏幕中下部，占屏宽约 60–70% | — | 见 `shots/05`、`shots/06` |
| 工具栏行高 | 约 122 px（搜索胶囊 86 + 上下各 18） | ≈ 17% 面板高 | 单行承载：搜索、Pinboard 标签、Pin 加号 |
| 内容区内边距 | 左 47 px（卡左 58 − 面板左 11） | ≈ 2.6% 面板宽 | 上/下留白相同量级 |

### 2.3 卡片结构（核心）

三卡完全等距：卡左边界 58 / 636 / 1214，卡宽 **530 px**、卡高 **531 px**（≈ 1:1 正方），卡间距 **49 px**。

| 区段 | 量测值 | 占卡高 | 内容 |
|---|---|---|---|
| 头部 band | y 150–262，**113 px** | 21.3% | 左侧两行文字：**类型名**（"Link"/"Text"/"Image"/"File"/"Audio"/"Color"，粗体白字，字高约 23 px 帽高）+ **相对时间**（"3 minutes ago"，白字约 70–80% 不透明度，字高约 13 px）；右侧 **来源 App 图标**（约 90×90 px 圆角方图，压在头部右端并向右出血） |
| 内容区 | y 263–563，**301 px** | 56.7% | 按类型渲染：图片缩略/网页 og 图/文本预览（淡色纸底）/文件图标/音频封面/色块 |
| 底部 band | y 564–675，**112 px** | 21.1% | 白底；**标题**（深灰 `#363636`，粗体，约 24 px 行高，单行省略号）+ **副标题**（浅灰，域名/路径/字数，单行省略号） |
| 卡片圆角 | 约 38 px（由左上角像素拟合） | ≈ 7% 卡宽 | ≈ 13–15 pt @2.6 px/pt |
| 卡片投影 | 极轻或无（靠底色反差区分） | — | 拖拽/悬浮时才抬起 |

**卡片头部颜色 = 来源 App 主题色**（这是 Paste 的识别核心，不是"类型→固定色"）：

- 绿 `#34C658` + 白色气泡图标 = 来自 Messages 的链接
- 蓝 `#0087FE` + Safari 指南针 = 来自 Safari
- 石墨黑 `#1E1E20` + Notion N = 来自 Notion
- 红 `#FF383C` + Photos 彩色花 = 来自 Photos 的图片
- 琥珀 `#EBA215` + Mail 信封 = 来自 Mail 的文本
证据：`shots/01`、`shots/02`、`shots/03`、`shots/04`（同一类型 Link 出现绿/蓝/黑三种头色，三种头色分别对应三个 App 图标）。

类型徽标的第二形态：内容区右下角/右上角的**尺寸胶囊**（如 `2400 × 2400`、`1180 × 1260`、`860 × 520`）：深色半透明 `rgba(0,0,0,.55)` 圆角胶囊、白字、位于图片区底部居中或右下。文本类对应位置改为白底灰字 `N characters`。

### 2.4 搜索栏

| 项 | 量测值 | 比例 |
|---|---|---|
| 胶囊尺寸 | 1243 × 86 px | 宽 = 面板宽 **69.8%**，居中；高 86 px |
| 圆角 | 43 px（全圆角） | 高度的一半 |
| 底 | `#DDCAB3`（面板底 `#F6E1C9` 叠一层约 12% 黑） | 比面板底暗一档，不用描边 |
| 聚焦环 | **约 3 px 蓝环 `#0C86EF`（另有采样 `#2487FB`）**，整圈包裹胶囊 | 聚焦时出现，是面板里唯一的蓝色主元素 |
| 左侧 | 放大镜图标（无边框），随后是 **token 芯片**（App 名带图标、`Last week` 带日历图标、`Link` 带链接图标），芯片底比胶囊再深一档 | token 与输入文字同排混排 |
| 右侧 | 两个图标按钮：**ⓧ 清空**、**≡ 全部过滤器**（都在胶囊内） | 与左侧图标同视觉重量 |
| 输入提示 | 候选过滤下拉（"Link / Linear / Last Week / Last Month"）以带图标列表浮层出现在胶囊下方 | 输入即出 |

**状态切换（重要）**：无搜索时该行是 **Pinboard 标签行**（🕐 Clipboard 胶囊态 + 各板"彩色圆点 + 名称" + ＋）；一旦聚焦搜索，**标签被压缩成右侧一列彩色圆点**，把整行让给搜索胶囊。见 `shots/02` 与 `shots/04` 对比。

### 2.5 色板（量测 hex）

| 用途 | 值 | 来源 |
|---|---|---|
| 面板底 | `#F6E1C9` | crop-c2 |
| 控件凹陷底（搜索胶囊 / 激活标签） | `#DDCAB3` | crop-c2 |
| 焦点/选中蓝 | `#0C86EF`（采样区间 #0C86EF–#2487FB） | crop-c2、help-3 |
| 卡片底部白 | `#FFFFFF` | crop-c2 |
| 标题文字 | `#363636` | crop-c2 |
| 副标题文字 | 浅灰 ≈ `#8A8A8E`（**未精确量测**） | 目视 |
| 类型色：绿 | `#34C658` | crop-c2 |
| 类型色：蓝 | `#0087FE` | crop-c2 |
| 类型色：石墨 | `#1E1E20` | crop-c2 |
| 类型色：红 | `#FF383C` | help-3（255,56,60） |
| 类型色：琥珀 | `#EBA215` | help-3（234,162,21） |
| 文本卡片纸底 | `#F4EFC8` / `#E8F0FF` 一类淡色（**未精确量测**） | 目视 |

### 2.6 字号层级（px @量测图，未换算 pt）

- 卡片类型名（"Link"）：帽高约 23 px → 约 30–32 px 字号，Semibold，白。
- 卡片相对时间：字高约 13 px → 约 17–18 px 字号，Regular，白 75%。
- 卡片标题：约 24 px 行高 → 约 20–22 px 字号，Semibold，`#363636`。
- 卡片副标题（域名/字数）：约 17–18 px，Regular，浅灰。
- 搜索输入：约 22 px，Regular，深色。
- 标签文字（Clipboard / Useful Links）：约 24–26 px，Medium。
（同一套比例下：面板宽 2.7 px/pt 时，类型名≈12 pt、时间≈6.5 pt、标题≈8 pt——偏小，说明面板实际比估算更宽，**建议实现时直接按"面板宽 : 类型字号 ≈ 43 : 1"这一比例缩放**。）

### 2.7 交互态与动效（部分为推断，已标注）

| 状态 | 表现 | 依据 |
|---|---|---|
| 未选中卡片 | 无描边 | crop-c2 |
| 选中卡片 | **约 3 px 蓝色描边 `#0A84FF` 整圈**，无位移 | frames/card-1、card-3、hero |
| 悬停/选中附加入口 | 卡片右下角浮出**绿色圆形「＋」钉板按钮**；另一形态是**蓝色圆形箭头徽章**压在卡片右边缘（表示"直接粘到前台 App"） | hero、frames/card-4 |
| 右键菜单 | 毛玻璃白色浮层 + 分组分隔线；项：Paste to <App> / Paste as Plain Text / Copy / Edit / Rename / Delete / Pin ▸ / Quick Look / Share ▸；右侧显示快捷键（↵、⇧↵、⌘C、⌘E、⌘R、⌘X、Space） | shots/03 |
| Pin 子菜单 | 彩色圆点 + 板名列表 + “＋ Create Pinboard”，当前项为**蓝色高亮实心胶囊** | shots/03 |
| 打开/关闭动效 | 面板从底部下滑淡入（约 0.15–0.2 s），关闭反向 | frames 序列推断，**未精确量测** |
| 拖拽 | 卡片抬起、投影加深，拖到标签行时目标板高亮 | frames，**未精确量测** |

### 2.8 空态（**未获取**）

20 篇帮助页与官网素材中均无"无历史/无搜索结果"截图。建议实现时自行定义：居中单图标 + 一句说明 + （搜索无结果时）"清空过滤器"按钮；不要照抄猜测。

### 2.9 iOS 形态（对照用，非本次目标）

底部上滑面板：顶部一行「🕐 Clipboard ⌄」列表选择器 + 右侧放大镜；卡片横向滑动，缩略图占 2/3、文字区 1/3；时间用紧凑写法（`now / 15m / 2h / 4h / 6h`）。来源：`helpshots/img-4`(iOS 键盘扩展)、官网 hero 中的 iPhone/iPad。实现 macOS 端时不要照搬紧凑时间格式。

---

## 3. macOS 平台能力 vs Paste 特有体验

### 3.1 纯平台能力（换平台要重写）

| 能力 | 说明 | 来源 |
|---|---|---|
| 剪贴板读取 | 后台常驻轮询 NSPasteboard | what-paste-captures.md |
| Accessibility 权限 | 用 ⌘V/⌘C 注入前台 App；权限会因系统升级静默失效 | paste-directly-to-other-applications.md |
| Screen Recording 权限 | Intelligent Clipboard 才知道前台是哪个 App | intelligent-clipboard.md |
| Quick Look | Space 预览 | keyboard-shortcuts.md |
| iCloud 同步 / CloudKit 共享 | 私有库同步 + 原生共享面板 | where-paste-stores-your-data.md, shared-pinboards.md |
| Writing Tools | macOS 26+ 在编辑器内提供改写 | edit-items-before-pasting.md |
| 菜单栏常驻 / 后台运行 | LSUIElement 类行为 | what-paste-captures.md |
| iOS 后台限制 | iOS 后台读不到剪贴板 → 采集策略必须不同 | what-paste-captures.md |

### 3.2 Paste 特有体验（值得抄的产品决策）

1. **横向卡片流 + 顶部 Pinboard 标签**取代"左侧列表 + 右侧预览"（消息型 App 的形态，而不是文件管理器形态）。
2. **卡片头部颜色/图标 = 来源 App**，把"上下文"做成零成本的视觉线索；类型只用文字标签。
3. **搜索态与标签态共用一行**：搜索聚焦时标签压缩为圆点，一行空间两用。
4. **过滤器 = 搜索框内的 token 芯片**，与自然语言混排，而不是独立的筛选侧栏。
5. **数字快贴 ⌘1–9**：把"列表位置"直接变成快捷键，省掉一次确认。
6. **Paste Stack 是一个"临时板"**：复用 pinboard 的数据模型，只是复制后自动进栈、粘贴后自动出栈。
7. **未 pin 条目会过期，pin 过的永不过期**：用"保留期限"制造整理动机，同时保证"重要的不会丢"。

---

## 4. 图片素材（/tmp/tb-clip-gap/shots/）

| 文件 | 内容 | 为什么选它 |
|---|---|---|
| `01-panel-search-filter.png` | 面板 + 搜索框内 token（"Last week"）+ 结果卡片（Image/File/Image），含图片内文字高亮 | 一张图看全：搜索、token 过滤、三种卡片形态、尺寸胶囊 |
| `02-search-bar-and-tabs.png` | 工具栏特写：搜索胶囊（蓝聚焦环）+ 右侧圆点化的 Pinboard | 量测搜索栏与"标签压缩"状态的依据 |
| `03-context-menu-pin.png` | 右键菜单全貌 + Pin 子菜单（彩色圆点板名 + 蓝色高亮 + Create Pinboard） | 菜单结构与 Pin 交互的唯一清晰素材 |
| `04-pinboard-tabs.png` | 无搜索态的标签行：🕐 Clipboard（凹陷胶囊）+ 三个彩色板 + ＋ | 标签行的默认形态与配色 |
| `05-panel-on-desktop.png` | 完整面板浮在桌面上（2400×916 原始视频帧） | 面板与屏幕的比例、位置、背景关系 |
| `06-panel-over-app-glass.png` | 面板叠在邮件 App 之上的实景（loop.mp4 帧） | 真实使用位置 + 面板与前台 App 的层级关系 |

---
*量测脚本与中间裁切图留在 /tmp/tb-clip-gap/（crop-c2.png、frames/、helpshots/），可复算。*

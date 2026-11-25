# 截图数值参数「任意可调」与人性化交互 · 对标 Snipaste

> **何时阅读：** 要调截图标注里任何一个数值（线宽 / 字号 / 透明度 / 马赛克粒度 / 模糊强度 / 放大镜倍率 / 选区尺寸），或要接新的键盘、滚轮通路之前。
> 触发：用户反馈「不希望只能调 6 个档，要能像 Snipaste 那样用鼠标滚轮任意放大」，并要求先调研、后落地。
> 证据口径：「原文」= 官方 wiki（本地全文 `/tmp/snipaste-docs/*.md`）；「源码」= 本仓 file:line；「静态」= 本机 `/Applications/Snipaste.app` 的符号与翻译串；「推断」= 无直接证据的推理。
> 配套：功能面差距见 [Snipaste 官方文档逐项对照](../调研/Snipaste-官方文档逐项对照.md)；本轮自定义能力的改前改后见 [截图标注自定义-对标Snipaste](截图标注自定义-对标Snipaste.md)。

## 一、先说结论

**Snipaste 其实不是「任意连续值」，而是「一格一档的离散步进 + 四条互补通路 + 零注意力反馈」。** 用户感知到的「任意」来自四件事合起来，而不是一个无限滑杆：

1. **值域够宽**：笔宽 1–40、Alpha 0–255、贴图缩放上限 1000%；
2. **四条通路等价**：鼠标滚轮 / `1` `2` / `[` `]` / 工具条控件，任一都能改同一个值（「原文」内置快捷键.md 通用表末行；更新日志.md v2.4「除了鼠标滚轮和 1 2，也可以使用 [ ] 调节画笔粗细」）；
3. **光标本身编码当前值**：笔宽变了光标图案跟着变（「原文」更新日志.md v1.12；v2.3.1 还专门修过「外接鼠标滚轮时光标不刷新」）；
4. **工具条上常显数值**：效果级别有滑块 + 数值标签（「静态」`hs_effectLevel` / `lb_effectLevelLabel`）。

**我们的「只能调 6 个」不是值域不够，是入口离散。** 值的类型早就是 `CGFloat` 连续量，卡住的是三处硬编码档位表与一个仍然吸附的步进函数（§二）。

**并且**：官方文档里**没有任何**「滚得快跳得多」的加速曲线描述，全文涉及加速的只有两处，都不是滚轮——WASD 光标移动按住自动加速（v1.12）、触控板降低敏感度（v2.3.3）。二进制符号 `stepPenWidth` / `stepAlpha` / `increaseEffectLevel` 都不带 speed 参数，唯一带 `speedRate` 与 `onLongPressed` 的是长按型 `PlusMinusButton`（「静态」）。**所以「滚轮任意放大」的手感来自「档位密 + 步长小 + 有反馈」，不是来自加速算法。** 这条决定我们该做「多档 + 小步长 + HUD」，而不是拟合一条滚轮曲线。

## 二、我们卡在哪（file:line 实证）

| # | 现象 | 根因 | 证据 |
|---|---|---|---|
| 1 | 线宽只能 3 档 | `SnipLineWidthStepper.step` 是纯档位吸附（找最近档再 ±1），滚轮与 `[` `]` `1` `2` `=` `-` **全部**走它 | `NetworkMonitorUI/SnipLineWidthStepper.swift:20-29`；调用点 `SnipOverlayView+Editing.swift:80-86,132` |
| 2 | 真连续只在面板里，且一次 1pt | 只有二级面板的「−/+」两格调 `continuousStep`；2→40 要点 38 次，无长按加速 | `SnipOverlayView+Panel.swift:134-135`；`SnipLineWidthStepper.swift:52-55` |
| 3 | 字号「只有 6 个」 | 面板按 `fontSizePresets` 逐格画，正好 6 格 | `NetworkMonitorCore/Domain/Models/SnipTextStyle.swift:64`（`[12,16,20,28,40,56]`） |
| 4 | 透明度只有 3 格 | `alphas = [1.0, 0.6, 0.3]`；连续 alpha 只能走「颜色盘 → 自定义… → 取色板 → 透明度条」四步 | `SnipToolBarView.swift:96`；写回 `SnipOverlayView+Panel.swift:142-145` |
| 5 | 调完没有反馈 | 全仓无 OSD；数值只在**悬停气泡**里，鼠标离开按钮就看不到 | `grep -rn 'OSD' Sources` → 0 命中；气泡文案 `SnipToolBarView+Drawing.swift:208-227` |
| 6 | 滚轮/键盘改完线宽会丢 | `stepLineWidth` 只刷工具条，**不落偏好、不改选中标注**；同文件 `adjustTextFontSize` 两件都做了 | `SnipOverlayView+Editing.swift:80-86` vs `:92-103` |
| 7 | 滚轮没有修饰键分支 | `handleStyleScroll` 全程不读 `modifierFlags` | `SnipOverlayView+Editing.swift:121-134` |
| 8 | 马赛克 / 模糊强度无人能改 | 硬编码常量，无偏好键、无入口 | `SnipMosaicProcessor.swift:11,13`；`grep 'mosaic|blurRadius' SnipPreferenceKey.swift` → 0 |
| 9 | 放大镜倍率写死 | 边长 120pt、采样跨度 15pt 都是常量 | `SnipMagnifierDrawing.swift:68-69` |
| 10 | 选区步长写死 1pt | 无 ⇧ 粗调、无 ⌥ 微调 | `SnipOverlayView+Actions.swift:141-151` |

## 三、Snipaste 的数值通路全貌（按状态分层，不是一套）

同一根滚轮在不同状态下语义完全不同，靠「窗口类型 → 当前工具 → 有无选中 → 指针是否在工具条控件上」四级派发：

| 状态 | 滚轮作用于 | 等价通路 | 官方原文 / 出处 |
|---|---|---|---|
| 标注态 | 画笔粗细 | `1` `2`、`[` `]` | 「鼠标滚轮 或 1 2 或 [ ]｜调整画笔粗细（编辑模式时）」内置快捷键.md |
| 标注态（选中文字） | 文字字号 | 字号下拉框、拖文字框四角 | 更新日志.md v2.4；基础操作.md |
| 标注态（选中矩形/椭圆） | **Shift + 滚轮 = 整体缩放该图形** | — | 更新日志.md v2.11 |
| 标注态（马赛克/模糊矩形填充） | 模糊级别（粒度/强度） | 效果级别滑块 + 数值标签 | 更新日志.md v1.15；「静态」 |
| 标注态（指针在调色按钮上） | Alpha 透明度 0–255 | 颜色对话框数值输入 | 常见问题.md；高级技巧.md |
| 贴图态 | 缩放（指针为锚，上限 1000%） | `+` `-`、拖窗口边缘、中键复位 | 基础操作.md；issue #2264 |
| 贴图态 | **Ctrl + 滚轮 = 透明度** | Ctrl `+` `-` | 基础操作.md「设置贴图透明度」 |
| 截图选区态 | 父/子元素框选（**不是数值**） | Tab 切换检测模式 | 专业版.md |
| 全局 | 可整条关闭滚轮 | 首选项「禁用鼠标滚轮功能」 | 「静态」`disable_mouse_scroll` |

**三处对我们的直接启示**

1. **透明度不要绑修饰键**：Snipaste 在标注态是「在大颜色按钮上直接滚轮」，靠控件命中而不是 ⌃。我们覆盖层是自绘、没有独立控件级滚轮分发，因此**反过来可以用 ⌃/⌥**，但必须写进提示浮层，且**同一修饰键在全覆盖层只能有一个语义**（§八）。
2. **Shift + 滚轮缩放选中图形**（v2.11）成本低、感知强：我们已有「选中 + 改样式」的底座（`applyStyleToSelectedAnnotation`），缺的只是「按中心等比缩放 bounds」。
3. **「可整条关闭」是设计的一部分**：滚轮一旦被塞进两三种语义，就必须给开关，否则用户只能拔鼠标。

## 四、竞品怎么解决「粗调 + 精调」

| 工具 | 机制 | 出处 |
|---|---|---|
| Snipaste | 离散步进；无修饰键加速；长按 `+/-` 才加速 | §三 |
| CleanShot X | `]` 增粗、`[` 变细、`⌘]`/`⌘[` 调不透明度；`1`–`6` 直接跳尺寸档 | keyscreen.app |
| Shottr | 方向键 1px、**⇧+方向键 10px**；`[` `]` 缩放、⇧+`[` `]` = 10px | shottr.cc/kb/precision |
| Photoshop | 数值字段拖动 scrub；**⇧ 拖 = ×10**（官方 About scrubby sliders） | helpx.adobe.com |
| Figma | ⌥ 拖 scrub，光标位移即速率；⇧ 吸附到 nudge 值（量化而非加速） | 社区文档 |
| Krita | ⇧ + 左右拖改笔刷大小，拖得越远越快 | docs.krita.org |
| Blender | `F` 后移动鼠标改半径，光标旁 HUD 显示数字 | docs.blender.org |
| Apple HIG（Stepper） | 大范围值建议 **⇧-click 一次走 10 倍**，并建议「步进器 + 数字输入框」成对出现 | developer.apple.com |

**一条必须写死的判断**：Adobe 社区里「Shift 是加速还是精细」长期两种说法并存。所以这个语义**不能靠约定俗成**——要么全局唯一并在提示里写明，要么不做。

## 五、「任意可调」的落地口径

### 5.1 定义：不是无限滑杆，是「四通道 × 一个连续值」

| 通道 | 交互 | 步长 | 目的 |
|---|---|---|---|
| 粗调 | 鼠标滚轮 / 键位 | 1 个最小单位（线宽 1pt、字号 1pt、alpha 5%、粒度 1 块） | 手不离鼠标 |
| 快调 | ⇧ + 同一条 | ×8 个最小单位 | 2 → 40 不需要滚 38 次 |
| 精调 | ⌥ + 同一条 | 0.5 个最小单位（按渲染精度取整） | 半档微调 |
| 精确输入 | 点工具条数值 → 就地输入框 | 任意值（解析后夹进范围） | 面板调不准的出口 |
| 复位 | 双击数值控件 | 回偏好默认值（不是回 0） | 试错可无损回退 |

**值的类型保持 `CGFloat` 连续**，只在显示时取整；不引入枚举档位（那正是本轮要消掉的东西）。

### 5.2 参数表（范围取本仓既有口径，不新造）

| 参数 | 范围 | 默认 | 最小单位 | 现状入口 | 补齐入口 |
|---|---|---|---|---|---|
| 线宽 | 1–40 pt | 4 | 1 pt | 滚轮/键（吸附 3 档）+ 面板 −/+ | 去吸附、加 ⇧/⌥、加输入框、加 HUD |
| 文字字号 | 9–160 pt | 缺键回落 `max(lineWidth*5,14)` | 1 pt | 滚轮（10% 比例步）、`0`/`9`、面板 6 格 | 改定量步 + ⇧/⌥ + 输入框；6 格保留为快捷项 |
| 颜色透明度 | 0–100% | 100% | 5% | 面板 3 格 + 取色板 alpha 条 | ⌃ + 滚轮、3 格扩 5 格、HUD 显示百分比 |
| 马赛克粒度 | 2–32 px | 14 | 1 px | **无** | 选中马赛克工具时滚轮改粒度 |
| 模糊强度 | 1–40 px | 14 | 1 px | **无** | 选中模糊工具时滚轮改强度 |
| 放大镜倍率 | 2–16× | 8×（=120/15） | 1× | **无** | ⌥ + 滚轮（放大镜可见时） |
| 选区尺寸 | 1–100000 pt | — | 1 pt | 方向键/WASD 1pt、⌘/⌃/⇧ 单边、尺寸标签输入 | ⇧ 方向键 10pt |

> 选区「手柄隐藏阈值」Snipaste 是 `80 × DPI` 可配（高级设置.md），我们写死 40pt（`SelectionGeometry.swift:57-59`）。列第三批，先不动。

### 5.3 滚轮步长归一化（否则触控板一格就飞）

`NSEvent.scrollingDeltaY` 对鼠标滚轮是「行」（约 ±1），对触控板是「像素」（可 ±0.1 也可 ±40）。同一个 `> 0 ? 1 : -1` 会让触控板一次滑行触发几十档。口径：

```
余量累加：accum += deltaY
          当 |accum| >= 阈值时，按整数个步长消费，accum 减去已消费部分
          阈值：hasPreciseScrollingDeltas ? 8 : 1
惯性尾（momentumPhase != .none）不消费，只清余量
```

放纯函数 `SnipScrollStepper`，配单测（触控板小幅多次 = 1 步；鼠标一格 = 1 步；惯性尾 = 0 步）。

### 5.4 反馈：光标旁的 HUD（「人性化」的核心，不是装饰）

调整瞬间在光标右下 12pt 画一个圆角小标签：`线宽 12 pt` / `字号 28 pt` / `透明度 60%` / `马赛克 14 px` / `放大 8×`。

- 1.2s 无操作后淡出；连续调整只刷新文字不重开动画（否则会闪）；
- 复用现有自绘链路（在 `SnipOverlayView.draw` 里画，状态放 view），不新建窗口、不抢焦点；
- 工具条上的当前值**同时**常显（不依赖悬停）——现在只有悬停气泡（`SnipToolBarView+Drawing.swift:208-227`）。

### 5.5 代码结构（落地后的实际分层）

**纯口径（`NetworkMonitorUI`，TestRunner 直接断言）**

| 文件 | 内容 |
|---|---|
| `SnipNumericParam.swift` | 参数枚举（lineWidth / fontSize / opacity / mosaicBlock / blurRadius / magnifierZoom），每 case 给范围 / 最小单位 / 量化粒度 / 默认 / 单位 / 显示格式 |
| `SnipNumericIntent.swift` | 修饰键 → 意图的**唯一**映射（⌘ = fast、⌥ = fine、否则 coarse），含角标文案 |
| `SnipNumericStepper.swift` | `step(_:param:steps:intent:)`：夹取 + 量化 + 按意图换步长 |
| `SnipScrollStepper.swift` | 余量累加（鼠标一格 = 1 步、触控板够阈值才走、惯性尾不消费、单次最多 8 步） |
| `SnipNumericHUD.swift` | 读数文案与避让几何 |
| `SnipNumericInput.swift` | 输入框解析（`12` / `12pt` / `60%` / 非法返回 nil） |
| `SnipNumericSession.swift` | 一次截图的数值会话状态（滚轮余量 / 放大镜倍数 / 正在输入哪个参数） |

**Core（可被功能层与 UI 共用）**

| 文件 | 内容 |
|---|---|
| `SnipEffectStyle.swift` | 马赛克粒度 / 模糊强度（带在每条标注的 `style.effect` 上，画好的不随后续调整变样） |
| `SnipAnnotationScaler.swift` | ⇧ + 滚轮的整体缩放（以包围盒中心为锚，轨迹类与文字不参与） |

**App（`Sources/NetworkMonitor/Snip/Numeric/`，自成一族）**

| 文件 | 内容 |
|---|---|
| `SnipNumericController.swift` | 数值旋钮的唯一所有者：读值 / 写值 / 步进 / 滚轮四路分流 / 改选中图形 |
| `SnipNumericController+HUD.swift` | 读数显示与淡出、就地输入框的弹出与提交 |
| `SnipNumericHUDView.swift` | 读数气泡的自绘视图（monospacedDigit，读屏有 label） |
| `SnipNumericWiring.swift` | 把覆盖层状态用闭包接给控制器（控制器不反向持有视图类型） |
| `SnipBarNumericInteraction.swift` / `SnipBarInteraction.swift` | 工具条上「命中的那颗按钮代表哪个参数」与滚轮 / 双击判定 |

**为什么控制器是独立类而不是 `SnipOverlayView+扩展`**：同族合计门禁只允许变小，
按「类名 + 职责」继续堆扩展正是它要拦的形态。控制器自成一族（`Snip/Numeric/`），
覆盖层只留一个 `lazy var numeric` 与一行转发，主文件因此从 350 行回到 307 行。

## 六、人性化交互清单（20 条 · 我们已有 / 缺）

| # | 模式 | Snipaste 做法 | 我们 |
|---|---|---|---|
| 1 | 同一数值多通路等价 | 滚轮 / `1``2` / `[``]` | ✅ 滚轮 + 键位 + 面板格 + 工具条按钮 + 输入框五条，全部走同一份 `SnipNumericStepper` |
| 2 | 光标编码当前值 | 光标图案随笔宽变化 | ❌ 覆盖层全程无 `NSCursor` 设定（第 2 批待做） |
| 3 | 常显当前值 | 工具条数值标签 | ✅ 常驻标签档走 `SnipNumericParam.format`，与读数气泡同一份格式 |
| 4 | 调整瞬间 HUD | 放大镜内坐标与操作提示 | ✅ `SnipNumericController+HUD`：光标旁 1.2s 淡出，带「精调 / 快调」角标 |
| 5 | 拖动中按空格切移动 | 拉框不松手按空格 = 平移选区 | ✅ `SnipSelectionState.enterSpaceMove` / `spaceMove` / `exitSpaceMove` |
| 6 | ⇧ 约束几何 | 矩形→正方、椭圆→圆、线→45° | ✅ `SnipAnnotationConstraint` |
| 7 | 右键 = 收笔，非编辑态才中止 | 编辑态右键结束当前图形 | ✅ `SnipRightClickIntent` |
| 8 | Esc 逐层退出 | 文字编辑中 Esc 只结束输入 | ✅ 已核实：输入框的 `cancelOperation` 只收输入（`SnipTextEditing.cancelTextEditing`），系统层 tap 在编辑态整键放行 |
| 9 | 双击 / 中键复位 | 贴图中键 = 100%+100% | ✅ 双击工具条数值按钮回默认值（贴图中键复位此前已有） |
| 10 | 数值直接打字输入 | 点尺寸数字 → 输入 | ✅ 样式盘末格「输入数值…」+ `SnipNumericInput` 解析（`12pt` / `60%`） |
| 11 | 分形状记忆样式 | 「为不同标注形状分别记忆颜色」 | ❌ 全局一个 `currentStyle` |
| 12 | 一次手势 = 一次撤销 | 拖动/滚轮连续调整合并为一条 | ❌ 撤销栈只记「加了什么」 |
| 13 | 可整体关闭某条通路 | 「禁用鼠标滚轮功能」 | ❌ |
| 14 | 吸附/阈值按 DPI 归一 | `20 × DPI` / `80 × DPI` | ⚠️ 部分写死点数 |
| 15 | 数值预设 + 命名 | 自定义截图对话框 `1280 720 720p` | ❌ |
| 16 | 多笔尖槽位（Pro） | 1–5 个笔尖各自记忆粗细 | ❌ |
| 17 | 语义冲突有仲裁 | 「窗口 + 工具 + 选中 + 控件」四级派发 | ✅ 滚轮走四级派发（⇧ 缩放 / ⌃ 透明度 / 选中改这一条 / 工具改参数 / 空手调放大镜） |
| 18 | 危险操作二次确认 | 关闭多张贴图前确认 | ⚠️ 贴图已有部分 |
| 19 | 可恢复的破坏性操作 | 关闭贴图入恢复池 | ✅ |
| 20 | 单位可切 px / pt | 专业版 px/dip 切换 | ❌ 一律点数 |

## 六之二、落地进度（第 0 + 1 批已完成）

| 能力 | 状态 | 落点 |
|---|---|---|
| 线宽连续（去吸附） | 已落地 | `SnipNumericStepper` 统一步进；`SnipLineWidthStepper.step` 降级为面板快捷项的取值 |
| 调完落偏好 / 改选中图形 | 已落地 | 写入只有 `SnipNumericController.write` 一条路径 → `toolBarDidChangeStyle`（回灌 + `onStylePersist`） |
| 滚轮三档意图 | 已落地 | `SnipNumericIntent`：⌘ ×8、⌥ ×0.5、默认 ×1 |
| 滚轮归一化 | 已落地 | `SnipScrollStepper`：触控板够阈值才走、惯性尾不消费、单次最多 8 步 |
| 数值读数 HUD | 已落地 | `SnipNumericController+HUD` + `SnipNumericHUDView`，1.2s 淡出、贴光标避让 |
| 精确输入 | 已落地 | 样式盘末格「输入数值…」+ `SnipNumericInput` |
| 双击复位 | 已落地 | 工具条数值按钮（线宽 / 字号 / 透明度）双击回默认值 |
| 工具条按钮上滚轮 | 已落地 | `SnipBarNumericInteraction`：线宽按钮 = 线宽/字号、颜色按钮 = 透明度 |
| 透明度 3 档 → 5 档 | 已落地 | `SnipToolBarView.alphas = [1.0, 0.75, 0.5, 0.25, 0.0]`，圆点垫棋盘底 |
| 马赛克粒度 / 模糊强度 | 已落地 | `SnipEffectStyle` 带在每条标注上；设置页两行 + 选中对应工具时滚轮可调 |
| 放大镜倍率 | 已落地 | `SnipMagnifierDrawing.span(for:)`；选区阶段滚轮 2–16× |
| ⇧ + 滚轮缩放选中图形 | 已落地 | `SnipAnnotationScaler`（中心为锚、轨迹类不参与） |
| 拖拽中按空格切移动选区 | 已落地 | `SnipSelectionState.enterSpaceMove` / `spaceMove` / `exitSpaceMove`；空格在拖拽期不再切工具条 |

**仍未做**（第 2/3 批）：光标图案跟笔宽变化、一次手势合并撤销、操作提示浮层、滚轮总开关、按形状记忆样式、多笔尖槽、数值预设命名、px/pt 双单位、选区手柄阈值可配。

## 七、落地批次（每批独立可验收）

**第 0 批 · 地基 —— ✅ 已完成**
- `SnipLineWidthStepper.step` 改为连续步进（去吸附，档位表降级为面板快捷项）；
- 修 `stepLineWidth` 不落偏好、不改选中标注（缺口 6）；
- 落 §5.3～§5.5 的五个纯函数与 HUD 骨架；
- 单测：范围夹取、步长 ×1/×8/×0.5、滚轮余量累加、修饰键唯一语义断言。
- 验收：`swift run TestRunner` 全绿 + 离屏快照对比（工具条、面板、选区外观零变化）。

**第 1 批 · 任意可调 —— ✅ 已完成**
- 线宽 / 字号 / 透明度 接上「滚轮 + ⇧ + ⌥ + 输入框 + 双击复位 + HUD」；
- 透明度 3 格扩到 5 格（0/25/50/75/100%），取色板 alpha 条保留；
- 马赛克粒度、模糊强度、放大镜倍率三个死值接上入口（选中对应工具时滚轮改）。
- 验收：每个参数走一遍四通道，HUD 文案与工具条常显一致；录屏取证。

**第 2 批 · 人性化交互 —— 部分完成（⇧ 缩放 / 空格移动已落地；其余待做）**
- ⇧ + 滚轮缩放选中矩形/椭圆（对齐 Snipaste v2.11）；
- 空格拖拽中切移动选区；
- 一次手势合并撤销；
- 操作提示浮层（首次进标注态 3 条，可关）+ 滚轮总开关；
- 光标图案跟笔宽变化。

**第 3 批 · 可选增强**
- 按形状记忆样式、多笔尖槽、数值预设命名、px/pt 双单位、选区手柄阈值可配。

**明确不做**：滚轮加速曲线（无官方依据、竞品各说各话）；无级小数值显示（`12.37 pt` 对用户无意义）；同一修饰键在标注态与贴图态语义相反。

## 八、三条反例（抄了就翻车）

1. **「滚轮调透明度但不给回显」**：官方 issue #3030 里用户要连点 4 次才能把 alpha 调回 255。只要做透明度，就必须同时有 HUD 或滑块。
2. **「同一个修饰键两义」**：Adobe 社区对 ⇧ 是加速还是精细至今两种说法。我们的 ⌥ / ⇧ 语义必须全局唯一，并在提示浮层写死。
3. **「滚轮同时管两件事且没有开关」**：issue #2607 的用户为关掉滚轮功能找了很久。滚轮一旦承载「数值 + 父/子元素」两种语义，必须先给可见开关。

## 九、取证命令（可复跑）

```bash
# 官方原文（本地全文）
grep -n '滚轮' /tmp/snipaste-docs/*.md
# 本机 Snipaste 静态证据
strings -a /Applications/Snipaste.app/Contents/MacOS/Snipaste | grep -nE 'stepPenWidth|stepAlpha|increaseEffectLevel|effectLevel|disable_mouse_scroll'
# 我们侧现状
grep -rn 'fontSizePresets|SnipLineWidthStepper.widths|static let alphas' NetworkMonitor/Sources
grep -rn 'OSD' NetworkMonitor/Sources --include=*.swift
```

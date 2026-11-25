# 截图标注自定义能力 · 对标 Snipaste

> 触发：用户反馈「截图工具的文字颜色、大小都不支持自定义，也不支持全选 / 复制 / 粘贴这些基础快捷键，线框大小也不能定义」。
> 本文逐项对比 Snipaste（官方 wiki：`内置快捷键.md` / `高级技巧.md` / `专业版.md`）与本次改造后的现状，给出**已补齐**与**仍缺**两张清单，供后续排期。

## 一、用户报的四件事，改前 vs 改后

| 用户报的问题 | 改前 | 改后 |
|---|---|---|
| 文字颜色不能自定义 | 只有 7 个固定色（`SnipToolBarView.colors`），无取色器 | 颜色盘末尾新增「自定义…」格 → 自绘取色板：色相条 + 饱和度/明度方块 + 透明度条 + hex 复制（`SnipColorPickerView.swift`，口径在 `SnipColorPickerModel.swift`） |
| 文字大小不能自定义 | 字号由线宽推导 `max(lineWidth*5,14)`，只能三档 14/20/40（`SnipAnnotation.swift`） | `SnipTextStyle.fontSize` 独立可调：9–160pt，二级面板 6 档 + `0`/`9` 快捷键 + 滚轮，另有加粗与 4 个字体族 |
| 全选 / 复制 / 粘贴不能用 | 主菜单只有一个 App 菜单、没有「编辑」菜单；AppKit 的 field editor 只靠菜单触发这些组合键 → 文字框里 ⌘A/⌘C/⌘V 全部无效 | 主菜单补标准「编辑」菜单（撤销/重做/剪切/复制/粘贴/全选），target 留空走响应链，对所有输入框生效（`AppDelegate.makeEditMenuItem`） |
| 线框大小不能定义 | 线宽固定 3 档 `[2,4,8]` | 线宽 1–40 连续值：设置页 `NSStepper`、样式盘「−/+」两格、`[` / `]` / `1` / `2` 按 1pt 走，滚轮亦可 |

## 二、本轮一并补齐的项

| 能力 | 说明 | 落点 |
|---|---|---|
| 文字透明度持久化 | hex 编码从 `#RRGGBB` 扩到 `#RRGGBBAA`（不透明时仍输出 6 位，老偏好格式不变）；调色板比对改用 `rgbHex` 忽略 alpha | `SnipAnnotationColorHex` / `SnipAnnotationColorNaming` |
| 虚线入口 | 键 `snip.annotationDashed` 一直被覆盖层消费，但设置页从来没有控件 | `SettingsCapturePane+Annotation` |
| 文字内容二次编辑 | 点已有文字 → 预填进输入框改内容；改成空 = 删除该条 | `SnipTextEditing.beginTextEditing(editing:)` |
| 输入框字号跟落字一致 | 此前固定 13pt，写 40pt 大字时预览与结果差一倍 | `SnipTextEditing.textInputFontSize` |
| 选中图元实时改样式 | 选中文字后改字号/颜色会同步到那条标注（此前只影响下一支笔） | `SnipOverlayView.applyStyleToSelectedAnnotation` |
| 单边扩缩选区 | ⌘/⌃ + 方向 = 扩大**对应那条边** 1px，⇧ + 方向 = 缩小那条边；此前是四边同时动 | `SnipSelectionState.expand(edge:by:within:)` / `shrink(edge:…)` |
| 符号键兜底 | CGEvent 兜底路径在部分布局上拿不到 `=` / `-`，按 keyCode 补一层 | `SnipSymbolKeyCharacters` |

## 三、与 Snipaste 相比**仍然缺**的基础项（按建议优先级）

优先级判据：P0 = 用户明确点名或做同类操作会被卡住；P1 = Snipaste 免费版即有、日常高频；P2 = 专业版能力或低频。

| 优先级 | 能力 | Snipaste 口径 | 我们现状 | 主要工作量 |
|---|---|---|---|---|
| **P0** | 标注文字**多行 / 自动换行** | 文字框可换行 | 单行 `CTLine`，多行要改 `CTFramesetter` + 命中测试 | 中（渲染器 + hitTest 重写） |
| **P0** | 已绘图形**拖动移动 / 8 手柄缩放** | 拖动图元、拖角改大小 | 只能选中 + Del 删除 + 改样式 | 中（新编辑状态机） |
| **P0** | 已绘图形**复制/粘贴/⌃拖拽克隆** | ⌘⇧C / ⌘⇧V / ⌃拖拽 | 无 | 中（图元剪贴板） |
| **P0** | ⌘P 打印 | 通用键 ⌘P | 无 `NSPrintOperation` | 小 |
| **P1** | Tab 切换直线/箭头 | 同一工具内 Tab 换形状 | Tab 目前是窗口检测开关；直线与箭头是两个工具 | 小（键位冲突需仲裁） |
| **P1** | 记号笔（半透明刷） | 免费版即有 | 只有画笔 + 模糊 | 小（新增工具 + 混合模式） |
| **P1** | 文字背景填充 / 描边 | 专业版 | 无 | 中 |
| **P1** | 按形状记忆颜色 | 专业版 | 全局一个 `currentStyle` | 小（按 kind 分桶存偏好） |
| **P1** | 实心填充入口 | 免费版即有 | `filled` 字段与渲染都在，**没有 UI** | 小（样式盘加一格） |
| **P1** | 箭头头长 / 序号半径可调 | 专业版可调样式 | 由线宽推导、无 UI | 小 |
| **P1** | 滚轮在选区阶段切嵌套窗口层级 | 同点滚轮切换父子窗口 | 只取最顶层命中窗口 | 中（窗口链构建） |
| **P1** | F5 刷新截图 | 专业版 | 无 | 小（复用重捕获路径） |
| **P2** | 界面元素（AX）检测 | 专业版 | 只到 CGWindow 粒度 | 大（AX 超时保护） |
| **P2** | 圆角矩形 / 双向箭头 / 放大镜标注 | 专业版 | 无 | 中 |
| **P2** | 覆盖层内部键位可自定义 | 高级设置 | 全硬编码 switch | 中（键位表 + 偏好注入） |
| **P2** | 自定义调色板（拖动排序、分享） | 专业版 | 7 色固定 + 单次自定义 | 中 |

> 另有两处**已知缺陷**（不属对标、但同批发现，未在本轮修）：
> 1. 六个可录制热键里，延时截图 / 隐藏贴图 / 打开设置 / 白板四个动作**重启后不生效**（`SnipController.start()` 里注册的是写死组合，只有截图 / 贴图读偏好），且会话内重录制会留下双注册；
> 2. CGEventTap 被系统超时禁用后，回调只 `return event`，注释说的「重新启用」并未调用 `CGEvent.tapEnable`。

## 四、设计取舍记录

1. **取色板为什么自绘**：覆盖层跑在 `screenSaver` 层级，原生 `NSColorPanel` 会被压在下面；原生控件还会抢走键盘焦点（截图态按键必须留在覆盖层）。口径（HSV ↔ RGB、命中换算、面板几何）全部放在 Core 的 `SnipColorPickerGeometry` / `SnipHSVColor`，视图只负责画。
2. **字号为什么不复用线宽当旋钮**：两者是两根不同的旋钮。旧口径下「想把字写大」必须先调粗笔，结果线框跟着变粗。现在 `SnipTextStyle.fontSize` 缺省为 `nil` 时仍回落旧公式，老标注与老偏好零迁移。
3. **线宽为什么保留档位表**：`SnipLineWidthStepper.widths` 降级为「二级面板的快捷项」，连续步进走 `continuousStep`。档位表仍是面板布局的真源，但不再是全部可选值。
4. **文字样式走同一个「线宽」按钮**：选中文字工具时该按钮改为弹「文字样式」盘（字号/加粗/字体）。工具条保持既有 4 工具 + 4 动作的宽度，不新增按钮；图标也换成「A」，避免「画的是字号、看的是粗细条」。
5. **面板内容口径搬到 UI target**：`SnipPanelContent` 从 App 移到 `NetworkMonitorUI`，条目数 / 索引偏移 / 文案才能被 TestRunner 直接断言（新增两格后最容易错位的就是索引）。

## 五、验收证据（可复跑）

```bash
cd NetworkMonitor
swift build --disable-sandbox --build-system native            # 0 error / 0 源码告警
swift run --disable-sandbox --build-system native TestRunner   # 所有测试通过
SKIP_INSTALL=1 ./Scripts/build-app.sh debug
NM_SNIP_OVERLAY_SNAPSHOT_DIR=/tmp/nm-snip-shot dist/一览.app/Contents/MacOS/一览
```

取证图（`/tmp/nm-snip-shot`）：

| 文件 | 核对内容 |
|---|---|
| `overlay-text-panel.png` | 文字工具下「线宽」格变成「A」、弹出文字样式盘（6 档字号 + 加粗 + 4 字体族），黄色文字按 28pt 渲染 |
| `overlay-color-picker.png` | 自绘取色板：饱和度方块 + 色相条 + 透明度条 + hex 文本 |
| `overlay-selected.png` / `overlay-idle.png` / `overlay-small-selection.png` / `overlay-top-label.png` | 既有外观无回归（工具条、选区、放大镜、尺寸标签） |

单测覆盖（`TestRunner/SnipAnnotationCustomizationTests.swift`）：字号与线宽解耦、字号夹取与步进、字体族解析与加粗字形、线宽连续步进与范围、hex alpha 往返、HSV 往返回环、取色板命中与几何顺序、面板条目数与索引偏移。

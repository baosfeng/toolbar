# Snipaste 功能清单（官方文档盘点 · 单文件版）

> 数据源：官方中文文档 <https://docs.snipaste.com/zh-cn/> 对应的 wiki 原始 Markdown（docsify 页面为 HTML 空壳，正文一律从 `https://docs.snipaste.com/wiki/<页面>.md` 抓取）。
> 抓取时间：2026-11-22；抓取方式：`curl -sSL --compressed -x http://127.0.0.1:7890`；原始文件留档 `/tmp/snipaste-docs/`。
> 本文只做外部产品调研，不引用、不对比任何本地项目代码。
> **单一维度说明**：本文不区分任何版本梯队，也不收录授权、定价、设备台数与退款规则。原始文档把功能分散在 `专业版.md` 的对照表与各正文页里，同一能力常被写到两三次；本文已把它们合并成一条，因此部分条目的来源 URL 仍指向该页——那是**出处**，不是分档标注。
> 每条功能一行，行尾附来源标注，格式为「来源：URL」，URL 即该条的出处页面；关键判断附原文短引（≤40 字）。

## 1. 产品定位

- Snipaste 是「简单但强大的贴图工具」，同时提供截屏与标注；贴图＝把剪贴板内容转成图片并作为窗口置顶显示（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 核心闭环只有两步：`F1` 截图 → `F3` 贴到屏幕；官网卖点集中在「自动检测界面元素区域」「像素级鼠标移动与范围控制」「取色器」「历史记录回放」「贴图分组」「自动备份、恢复」（来源：https://zh.snipaste.com/）
- 自述必须常驻后台（原文：「贴图功能需要它常驻后台」），不能退化为纯截图工具（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 贴图的官方衍生用途：临时备忘、拼图、参考图、做教程、录屏水印、简易剪贴板管理、资料整理、画板（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 界面多语言，翻译托管于 `Snipaste/translations`，可补充新语言或改进现有翻译（来源：https://docs.snipaste.com/wiki/帮助翻译.md）
- 帮助入口三处：托盘右键「帮助」子菜单、命令行 `docs`、首选项「热键」页签的「内置快捷键」按钮（来源：https://docs.snipaste.com/wiki/命令行选项.md）

## 2. 截图捕捉

- 开始截屏：全局快捷键 `F1`，或左键单击托盘图标；自由矩形框选，可移动、扩大、缩小选区（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 窗口检测：鼠标悬停自动识别并框选整个窗口（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 界面元素检测：自动识别窗口内控件矩形，用于精确框选按钮、输入框等；`Tab` 在「检测窗口 / 检测界面元素」之间切换（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 父/子元素框选：用滚轮在父元素与子元素之间上溯/下钻（Linux 版不支持）（来源：https://docs.snipaste.com/wiki/专业版.md）
- 快速标注界面元素：选中矩形/椭圆，或记号笔/马赛克/高斯模糊/橡皮擦的矩形画笔后按右键，自动选中光标下的界面元素；需启用「自动检测界面元素」（来源：https://docs.snipaste.com/wiki/高级技巧.md）
- 捕捉鼠标指针图案：`` ` `` 或 `!` 显示/隐藏捕获到的指针；可整体禁用光标捕捉以改善响应速度（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 选区快捷设定：`Ctrl+A` 设为全屏、`R` 设为上一次成功截图区域、`Ctrl+T` 直接把截图贴到屏幕（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 逐像素移动光标：`W` `A` `S` `D`，按住不放会自动加速（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 像素级调整选区：按住左键 + `WASD` 同步移动/放大/缩小（官方标为推荐）；方向键移动、`Ctrl+方向键` 扩边 1px、`Shift+方向键` 缩边 1px（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 拖拽调整选区时切换为移动选区：不松开鼠标，按空格键即进入移动选区模式（来源：https://docs.snipaste.com/wiki/高级技巧.md）
- 放大镜：在合理时机自动出现与隐藏，需要时按 `Alt` 强制唤出；样式可配（网格线 / 屏幕坐标 / 操作提示 / 像素大小 / 放大倍数），并可完全隐藏放大镜（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 取色：放大镜可见时按 `C` 复制该像素颜色值（RGB/Hex），之后可 `F3` 贴出或 `Ctrl+V` 贴到其他程序；`Shift` 切换颜色格式（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 截图历史回放：进入截图后按 `,` 或 `.` 在历史选区之间切换；只有「成功的截图」进历史，最大条数可设置，另有「保存所有的截图记录」与「循环切换」选项（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 白板模式：命令行 `whiteboard` 进入，`Esc` 退出截图被禁用、工具条自动隐藏（空格键唤出）；`--color` 指定填充色、`--active-screen` 仅光标所在屏、`transparent-whiteboard` 不冻结屏幕内容（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 自定义尺寸截图：`snip --custom` 弹出「自定义截图」对话框，可勾选指定左上角坐标、大小（含预设）与延迟（0.0–60.0 秒）（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 选区形态控制：进入截图后可点尺寸图标手动输入区域大小、固定长宽比、切换尺寸单位 px/dip、设圆角矩形与更大圆角半径（来源：https://docs.snipaste.com/wiki/专业版.md）
- 刷新截图：`F5`（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 选区锚点：选框边角显示锚点，选区宽或高小于阈值时自动隐藏（`Snip/anchors_threshold`，默认 80×DPI，设 0 表示始终不隐藏）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 辅助线：按下 `Alt` 额外显示两条中央辅助线；另有「禁用辅助线」选项（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 多屏与活动窗口：支持多屏与高分屏；`snip --active-screen` 把选区设为光标所在屏幕，`snip --active-window` 设为当前活动窗口（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 超级截屏：不占用任何全局快捷键即可截图，例如 `Win` + 鼠标左键拖拽；触发动作可选「截屏并贴图 / 截屏并自动复制 / 无」（来源：https://docs.snipaste.com/wiki/专业版.md）
- 带阴影 / 带边框输出：`--shadow` / `--no-shadow`；阴影颜色与宽度、边框颜色与宽度可指定（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 延时截屏：`--delay TIME`（单位秒，支持小数如 `1.5`），也可在自定义截图对话框设定（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 预设截图区域并命名：自定义截图大小菜单可「添加到预设」（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 取消截图：任意时刻 `Esc` / 点工具条关闭按钮 / 非编辑状态下按右键 / 其他程序窗口被激活（末项可在选项窗口关闭）（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 截图操作提示：进入截图后的操作提示气泡可在首选项中关闭（来源：https://docs.snipaste.com/wiki/更新日志.md）

## 3. 标注与编辑

- 矩形 / 椭圆：按住 `Shift` 约束为正方形 / 圆形；直线 / 箭头：`Tab` 在两者间切换，`Shift` 约束为水平/垂直/45 度（来源：https://docs.snipaste.com/wiki/高级技巧.md）
- 折线：选中折线工具后，拖拽左键画单条直线，多次点按左键画折线（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 画笔（自由绘制）：按住 `Shift` 可中途变换为直线（来源：https://docs.snipaste.com/wiki/高级技巧.md）
- 记号笔：矩形/椭圆高亮填充，独立拥有一个透明度，其他画笔共用一个透明度（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 马赛克与高斯模糊：模糊程度可独立调节（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 橡皮擦：矩形或椭圆区域擦除；可对橡皮擦工具禁用二次编辑（来源：https://docs.snipaste.com/wiki/专业版.md）
- 文字标注：拖动四角调字号、拖顶部圆点旋转、按住 `Shift` 拖四角恢复水平；支持斜体、字号下拉、更小字号（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 文字描边与背景：可指定描边颜色与粗细、可填充背景色（来源：https://docs.snipaste.com/wiki/专业版.md）
- 序号标注：编号图元，支持多组计数标注（来源：https://docs.snipaste.com/wiki/专业版.md）
- 放大镜标注：把局部放大成独立图元（来源：https://docs.snipaste.com/wiki/专业版.md）
- 圆角矩形标注（来源：https://docs.snipaste.com/wiki/专业版.md）
- 箭头体系：双向/反向箭头、更多箭头样式；箭头宽度固定，可按键调整大小（来源：https://docs.snipaste.com/wiki/专业版.md）
- 线型与形状：矩形/椭圆/直线/折线/箭头/画笔支持虚线、点线；记号笔 / 马赛克 / 高斯模糊 / 橡皮擦支持椭圆/圆形（来源：https://docs.snipaste.com/wiki/专业版.md）
- 旋转标注：文字标注一向可旋转，其余除线条类标注外均支持旋转（来源：https://docs.snipaste.com/wiki/专业版.md）
- 二次编辑：选中同类型形状后可改参数，`Del` 删除、`Ctrl+Shift+C/V` 复制粘贴、按住 `Ctrl` 拖拽克隆；已结束的图案也可走「撤销到消失再重做」的间接路径（来源：https://docs.snipaste.com/wiki/专业版.md）
- 自由选中：可任意框选多个已绘制形状（来源：https://docs.snipaste.com/wiki/专业版.md）
- 撤销 / 重做：`Ctrl+Z` 撤销、`Ctrl+Y` 恢复；`Ctrl+Shift+Z` 移除所有标注（不可恢复）；标注的移动与旋转同样可撤销重做（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 画笔粗细：鼠标滚轮、`1` `2`、`[` `]` 三种方式；笔尖体系可保存 1–5 个笔尖尺寸，各笔尖均可滚轮调粗细（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 画笔透明度：点开工具条大颜色按钮改 Alpha 通道（0–255）；也可直接在大颜色按钮上滚动滚轮调节（来源：https://docs.snipaste.com/wiki/高级技巧.md）
- 调色板：拖拽重排颜色、自定义颜色数量、导出到剪贴板 / 从剪贴板导入以分享、为不同标注形状分别记忆颜色（来源：https://docs.snipaste.com/wiki/专业版.md）
- 选中形状的缩放：按住 `Ctrl` 中心点缩放、`Shift` 等比缩放；`Shift+鼠标滚轮` 缩放选中的矩形/椭圆（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 结束当前图案：单击鼠标右键（所有标注通用，文字输入也用此法结束）（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 标注创建后自动选中它（`Annotate/auto_select_on_creation`，默认 true）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 空格键显示/隐藏标注工具条，编辑状态下同样生效；工具条误隐藏时右键菜单可帮助退出标注或重新显示（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 工具条「输出选项」弹出菜单可隐藏（`Interface/hide_output_options`）；可绑定按键到自定义输出选项（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 标注输出动作：`Ctrl+C` 复制图像、`Ctrl+S` 存文件、`Ctrl+Shift+S` 快捷保存、`Shift`+点保存按钮同效、`Ctrl+P` 打印（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 复制含文件：复制图像时同时复制图像内容与图片文件，之后可直接在文件管理器 `Ctrl+V` 存成文件；`Ctrl+Alt+C` 复制图像为文件（来源：https://docs.snipaste.com/wiki/专业版.md）
- 按住 `Ctrl` 再点工具条上的复制/贴图/保存按钮，可获取带阴影图像（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 在贴图上标注：点右键菜单「标注」或在贴图上按一下空格键即可进入编辑（来源：https://docs.snipaste.com/wiki/常见问题.md）

## 4. 贴图（Pin）

- 贴图定义：把系统剪贴板内容转成图片并作为置顶窗口显示，能贴出什么取决于剪贴板内容（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 触发方式：`F3`、中键单击托盘图标、截图时选「贴到屏幕」（`Ctrl+T` / 截屏区域中键单击）（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 可贴内容：图像；颜色（RGB 三整数 0~255 / 三小数 0~1 / `#` 开头 HEX）；文字（纯文本、HTML）；复制的文件路径（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 旋转与镜像：`1` 顺时针 90 度、`2` 逆时针 90 度、`3` 水平翻转、`4` 垂直翻转；`5` 灰度、`6` 反色（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 缩放：滑动滚轮、`+` / `-`、拖动贴图窗口边缘；可选择以鼠标指针为中心缩放、可取消平滑缩放（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 透明度：`Ctrl` + 滑动滚轮，或 `Ctrl` + `+` / `-`；贴图默认透明度可设（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 鼠标穿透：为「鼠标穿透开关」设置全局快捷键后，切换光标所在位置贴图的穿透状态；若无贴图在光标下则取消所有贴图的穿透；开关时显示文本提示（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 重置贴图：中键单击恢复 100% 大小与 100% 不透明（可自定义），对缩略图也起作用（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 缩略图模式：`Shift` + 左键双击（可自定义）；另支持右键框选生成自由尺寸缩略图（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 关闭单张贴图：`Esc` / 左键双击（可自定义）/ `Ctrl+W`；可被贴图键恢复，恢复上限「可被恢复的已关闭贴图数」默认 1 且可设置；首次双击关闭时弹出提示（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 隐藏所有贴图：`Shift+F3` 切换；隐藏不影响已关闭贴图计数，也不会在退出时被销毁（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 销毁贴图：`Shift+Esc` 或右键菜单「销毁」；销毁后不再被贴图键恢复，退出时未被显示的已关闭贴图自动销毁；关闭或销毁多个贴图前有二次确认（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 多选：`Ctrl+A` 全选可见贴图、按住 `Ctrl` 点击多选，之后批量移动 / 调透明度 / 缩放 / 阴影与置顶 / 批量保存；多选时可自动选中当前激活窗口（`Paste/include_active_window_for_multiselection`）（来源：https://docs.snipaste.com/wiki/专业版.md）
- Solo 模式：暂时只显示某个（或选中的多个）贴图，其余隐藏但不丢失（来源：https://docs.snipaste.com/wiki/专业版.md）
- 贴图分组：创建组、切换组（切到下一个 / 指定组 / 上一个激活组）、清空当前组、在托盘菜单对组名右键关闭整组；切换到另一分组时可自动闪烁贴图（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 贴图组管理窗口：集中添加、删除、重命名、排序贴图组（来源：https://docs.snipaste.com/wiki/专业版.md）
- 背景模式：透明 / 伪透明 / 暗色棋盘 / 亮色棋盘；可设默认背景也可单张修改；透明模式下鼠标点不到透明区域，伪透明仍可点击（来源：https://docs.snipaste.com/wiki/专业版.md）
- 置顶开关：可单独设置某张贴图是否置顶（「保持最上」）；当前激活贴图的阴影使用主题色（来源：https://docs.snipaste.com/wiki/专业版.md）
- 虚拟桌面：贴图可固定到指定或所有虚拟桌面，支持 Windows 11 22H2+/23H2（来源：https://docs.snipaste.com/wiki/专业版.md）
- 贴图裁剪：可对贴图（含缩略图）进行裁剪（来源：https://docs.snipaste.com/wiki/专业版.md）
- 贴图尺寸与背景：可输入贴图尺寸 / 缩放比例、自定义贴图背景色；贴图最大尺寸可设（来源：https://docs.snipaste.com/wiki/专业版.md）
- 可编辑的颜色卡片：贴图是颜色卡片时可改其颜色值，并提供各格式色值一键复制（来源：https://docs.snipaste.com/wiki/专业版.md）
- 网页图片：支持 Firefox/Chrome/Edge 右键复制图像后贴图，或直接把图片拖拽到已有贴图；拖拽 http/https 图片链接自动下载，单图上限 `Misc/auto_download_max_image_size_mb`（默认 20MB）（来源：https://docs.snipaste.com/wiki/专业版.md）
- 对齐吸附：按住 `Shift` 拖动贴图可对齐到其他贴图或其他程序窗口，阈值 `Paste/magnetic_attach_threshold`（默认 20×DPI）（来源：https://docs.snipaste.com/wiki/高级技巧.md）
- 边缘缩放可禁用（`Paste/disable_frame_resize`，默认 false）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 贴图内替换与取值：`Ctrl+V` 用剪贴板内容替换该贴图；`Ctrl+Shift+C` 复制由文本转换来的贴图的纯文本；贴图上有唯一文字标注时右键菜单可复制其文字（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 拖放：贴图上的拖放操作可保留原贴图；另可「替换为文件…」「在文件夹中查看」（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 移出屏幕：贴图可移出屏幕边缘；屏幕设置变化导致贴图不可见时不再自动移回，可从托盘菜单「恢复屏幕外的贴图」（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 保存：可批量保存选中的贴图、以原始大小保存已缩放的贴图（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 动画：可读取 apng 格式动画文件并作为贴图播放（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 贴图上的放大镜与取色：与截图时一致，按住 `Alt` 唤出放大镜，`C` 复制颜色值；复制成功时放大镜闪一下作提示（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 右键菜单尺寸行：菜单底部显示当前贴图像素尺寸（如 `152 x 100`），可点开尺寸子菜单（来源：https://zh.snipaste.com/）

## 5. 剪贴板与内容转换

- 贴图本质是剪贴板内容可视化：文字、HTML、图像、颜色值、文件路径都能贴（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 颜色值转贴图：RGB 三整数、RGB 三小数、`#` 开头 HEX 均可识别为颜色卡片；色值格式含 RGB / HSV / HSL / HSI（来源：https://docs.snipaste.com/wiki/基础操作.md）
- HTML 文本贴图保留格式；`Paste/force_html_wrap` 可按「图片最大宽度」强制换行（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 文件路径贴图：文件是图片则贴出图像，再贴一次则把路径当文本贴出；非图片文件贴出路径文本，可在选项中关闭「把文件路径转化成图片」（来源：https://docs.snipaste.com/wiki/基础操作.md）
- 文字转图片：可关闭该功能，并可设置页边距（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 命令行贴出：`paste` / `paste --clipboard` 转剪贴板、`--plain TEXT`、`--html TEXT`、`--files FILE...`（支持「文件夹路径 + 相对文件名」）、`--pos X Y` 指定左上角（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 粘贴为图像 / 纯文本：`paste-as-image` 尝试把剪贴板内容转成图像并发送 `Ctrl-V`；`paste-as-plain-text` 把 HTML 转纯文本再发送（仅 Windows）（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 忽略其他程序模拟的「复制」命令，避免划词/剪贴板工具干扰（v2.10.5 起默认启用）（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 输出图片质量：`-1` 自动 / `0` 最低 / `100` 最高；复制到剪贴板的图像质量文档明确「暂时没有提供设置」（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 保存格式：下拉菜单可选多种图片格式，支持 WebP，并可记住上一次使用的扩展名（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 透明通道处理：保存时自动检测半透明像素，无透明则移除 alpha 通道以减小体积（`Output/auto_alpha_channel_removal`，默认 true）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 元数据：保存时写入 Snipaste 相关元数据（`Misc/software_metadata`，默认 true）；为截图写入元信息以供 iCloud 分类（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 剪贴板格式兼容：可选用 Windows Bitmap 格式写剪贴板（会丢失透明通道，用于兼容 Skype / UWP 应用等）（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 自动备份与恢复：贴图分组与历史可自动备份、恢复（来源：https://zh.snipaste.com/）
- 能力边界：文档未出现「剪贴板历史列表 / 搜索 / 粘贴栈」类功能，贴图分组与截图记录是仅有的两处历史能力（来源：https://docs.snipaste.com/wiki/基础操作.md）

## 6. 快捷键与交互

- 默认全局快捷键：`F1` 截屏、`Ctrl+F1` 截图并自动复制、`Shift+F1` 自定义截图、`F3` 贴图、`Shift+F3` 隐藏/显示所有贴图、`Ctrl+F3` 切换到另一贴图组、`F4` 鼠标穿透开关（来源：https://docs.snipaste.com/wiki/专业版.md）
- 内置快捷键按「只对截图有效 / 只对贴图有效 / 通用」三张表组织；macOS 上把 `Ctrl` 换成 `Cmd`（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 为任意功能绑定全局快捷键：可填写任意命令行作为命令，预设常见命令，左下角问号可查阅命令行文档（来源：https://docs.snipaste.com/wiki/专业版.md）
- 忽略程序列表：每个快捷键可指定忽略程序，按 exe 文件名或路径片段模糊匹配，避免在游戏等场景误触发（来源：https://docs.snipaste.com/wiki/专业版.md）
- 自定义应用内快捷键：首选项「控制」页签下的「应用内快捷键」（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 可自定义项：贴图缩放 / 透明度快捷键、贴图 `Esc` 与 `Shift+Esc` 的行为、缩略图快捷键、截图时回车键的功能、重置贴图操作（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 简单按键作全局快捷键：允许单个字母/数字/标点/方向键/`Esc`/`Enter` 及 `Shift`+字母等（`Hotkey2/allow_simple_hotkeys`，默认 false）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 交换 `WASD` 与方向键功能（`Hotkey2/exchange_wasd_and_arrow_keys`，带修饰键的功能不受影响）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 滚轮语义汇总：调整画笔粗细、缩放贴图、`Ctrl`+滚轮调贴图透明度、大颜色按钮上滚轮调透明度、`Shift`+滚轮缩放选中矩形/椭圆（来源：https://docs.snipaste.com/wiki/内置快捷键.md）
- 托盘图标动作可自定义：左键单击 / 中键单击 / 右键单击分别指定执行的命令（默认 `snip` / `paste` / `show-tray-menu`），「预设」下拉可直接选命令（来源：https://docs.snipaste.com/wiki/专业版.md）
- 键盘双击间隔可配（`Misc/double_tap_interval`，默认 400ms）（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 屏幕触发角：鼠标移到屏幕四角执行指定功能，支持程序黑名单，可全局快捷键禁用/启用；推荐用法是左上/右上角显示/隐藏全部贴图（来源：https://docs.snipaste.com/wiki/专业版.md）
- 快捷键与触发角的命令行开关：`disable-hotkeys` / `enable-hotkeys` / `toggle-hotkeys`、`disable-hot-corners` / `enable-hot-corners` / `toggle-hot-corners`（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 支持含 `PrtSc` 的全局快捷键；被系统或其他程序占用的组合键不可设置，设置失败会提示原因（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 托盘图标可隐藏（`General/hide_tray_icon`）；隐藏后可在贴图上按 `Ctrl+Shift+P`（Windows/Linux）或 `Cmd+,`（macOS）唤出首选项（来源：https://docs.snipaste.com/wiki/高级设置.md）
- 内置快捷键窗口：位于首选项「热键」页签下，列表带「复制」按钮，可直接复制快捷键文本（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 可发现性：几乎每个选项都有悬停提示；选项窗口多处布有提示图标；截图有操作提示气泡；鼠标穿透开关切换时有文本提示（来源：https://docs.snipaste.com/wiki/常见问题.md）

## 7. 配置文件（config.ini）

设置方法：`首选项` - `常规` - `配置文件存储位置` - `打开`，在对应 `[组名]` 下追加选项，退出后保存再启动；`config.ini` 支持软链接，只保留与默认值不同的选项（来源：https://docs.snipaste.com/wiki/高级设置.md）

- 前置说明：文档明写「这些是没有提供用户界面的高级设置，请小心设置」——本节全部键在首选项界面上没有对应控件（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[General] history_dir` —— 历史记录文件夹，支持环境变量与相对/绝对路径，不支持中文路径，不存在时回落到 `./history`（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[General] hide_tray_icon` —— 隐藏托盘图标，true/false（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[General] gpu_acceleration` —— GPU 硬件加速：0 禁用 / 1 启用 / 2 自动（默认 2），影响马赛克、高速模糊、阴影等绘制效率（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[General] process_priority` —— 进程优先级 0 正常 / 1 高于正常 / 2 高 / 3 实时，Windows 独占（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Snip] anchors_threshold` —— 选区锚点自动隐藏阈值（像素），0 表示始终不隐藏，默认 80×DPI（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Snip] exclude_from_detection` —— 把指定程序窗口从窗口检测中排除，逗号分隔，Windows 独占（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Snip] crashes` —— 对指定程序窗口改用另一种界面元素检测算法以规避崩溃，Windows 独占（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Snip] animated_region_transition` —— 检测窗口/界面元素时是否使用过渡动画，默认 true（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Paste] force_html_wrap` —— HTML 转贴图时按「图片最大宽度」强制换行（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Paste] magnetic_attach_threshold` —— 贴图贴边吸附距离阈值（像素），默认 20×DPI（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Paste] disable_frame_resize` —— 禁用贴图边缘缩放，默认 false（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Paste] include_active_window_for_multiselection` —— 多选贴图时是否自动选中当前激活窗口，默认 false（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Hotkey2] exchange_wasd_and_arrow_keys` —— 交换 WASD 与方向键功能，默认 false（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Hotkey2] allow_simple_hotkeys` —— 允许简单按键作为全局快捷键，默认 false（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Annotate] auto_select_on_creation` —— 创建标注后自动选中它，默认 true（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Interface] hide_output_options` —— 隐藏标注工具条上的「输出选项」弹出菜单，默认 false（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Output] auto_alpha_channel_removal` —— 保存时无半透明像素则移除 alpha 通道，默认 true（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Misc] uppercase_hex_color` —— Hex 颜色值使用大写字母（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Misc] auto_download_max_image_size_mb` —— 拖拽网页图片自动下载的最大大小，默认 20.0 MB（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Misc] double_tap_interval` —— 键盘按键双击间隔（毫秒），默认 400（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Misc] software_metadata` —— 保存图片时写入 Snipaste 相关元数据，默认 true（来源：https://docs.snipaste.com/wiki/高级设置.md）
- `[Log]` 四项 —— `file` 日志文件名（默认 splog.txt）、`flush_interval` 刷新间隔秒数（默认 0 自动，日志等级为跟踪/调试时无效）、`rotate` 轮转数量（默认 1，0 为无轮转）、`rotate_size_mb` 轮转大小（默认 2.0 MB）（来源：https://docs.snipaste.com/wiki/高级设置.md）

## 8. 命令行

- 调用形式 `snipaste [OPTIONS]`；除带 `*` 标记的选项（如 `--config`）外，其余选项只在 Snipaste 启动后有效；各平台调用路径写法不同（桌面版 exe / 商店版 `Snipaste` / Mac 的 `Contents/MacOS/Snipaste` / AppImage）（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `snip` —— 开始截屏（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `snip --area X Y WIDTH HEIGHT` —— 开始截屏并把选区左上角设为 (X, Y)、宽高为 WIDTH/HEIGHT（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `snip --size WIDTH HEIGHT [--keep_aspect_ratio]` —— 以光标为中心设固定宽高，可锁定长宽比（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `snip --full` / `snip --last` —— 选区设为全屏 / 上一次成功截屏的区域（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `snip --active-window` / `snip --active-screen` —— 选区设为当前活动窗口 / 光标所在屏幕（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `snip --custom` —— 弹出自定义截屏对话框，可指定位置、大小、延迟时间（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `--delay TIME` —— 延迟 TIME 秒后开始截屏，支持小数如 1.5（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `--shadow` / `--no-shadow` —— 取带阴影 / 不带阴影的截图（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `--hold` —— 结合 `-o xxx` 时等待用户完成标注才退出截图（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `--block [SECONDS]` —— 让调用方等到截图界面退出（或等 SECONDS 秒）后再退出（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o pin` —— 将截图贴到屏幕上（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o clipboard` —— 复制截图到剪贴板（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o ocr_clipboard` —— 提取截图中的文字并复制（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o FILE_NAME` —— 保存到指定文件，支持使用变量（含空格需双引号）（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o quick-save` —— 保存到快捷保存文件夹（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o file-dialog` —— 截图后弹出文件保存对话框（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o printer` —— 把截图发送到打印机（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o no-auto-save` —— 不触发自动保存（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o silent` —— 不弹气泡通知（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o success` —— 不保存到任何地方，仅标记为成功，可进截图记录并触发自动保存（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o exec(COMMAND)` —— 截屏成功后执行指定命令（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `-o` 多输出组合：可用 `;` 组合多个输出方式，顺序预定义 `FILE_NAME → file-dialog → printer → quick-save → clipboard → pin → success → exec(COMMAND)`，与书写顺序无关（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `paste` / `paste --clipboard` —— 把剪贴板内容转成贴图（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `paste --plain TEXT` / `paste --html TEXT` —— 把纯文本 / HTML 文本贴出（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `paste --files FILE1 FILE2 ...` —— 把图像文件贴出，支持「文件夹路径 + 相对文件名」写法（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `--pos X Y` —— 指定贴图左上角的屏幕位置（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `show-images` / `hide-images` / `toggle-images` —— 显示 / 隐藏 / 切换所有贴图（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `create-group [GROUPNAME]` —— 创建指定名称的贴图组，未给名称则弹窗输入（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `switch-groups` / `switch-group [GROUPNAME]` / `switch-group-prev` —— 显示组列表 / 切到指定组（未给名则切下一个）/ 切到上一次激活的组（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `empty-group` —— 清空当前贴图组（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `show-group-manager` —— 打开「管理贴图组」窗口（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `no-click-through` / `toggle-click-through` —— 取消 / 切换贴图的鼠标穿透模式（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `show-tray-menu` —— 在当前鼠标位置显示托盘菜单（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `show-purchase-dialog` —— 弹出购买窗口（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `whiteboard [--color COLOR] [--active-screen]` —— 进入白板模式，可指定填充颜色（颜色名或 `#001122`）并限定仅光标所在屏幕（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `transparent-whiteboard` —— 透明白板模式，屏幕内容不会被冻住（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `external COMMAND` —— 调用外部程序，如 `external notepad c:/123.txt`（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `pick-color` —— 选取并复制屏幕某像素的颜色值（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `barcode-scan` / `barcode-decode FILE` —— 识别屏幕或指定图片上的二维码/条形码并复制结果，失败则清空剪贴板（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `paste-as-image` / `paste-as-plain-text` —— 剪贴板转图像后发 `Ctrl-V` / HTML 转纯文本后发 `Ctrl-V`（仅 Windows）（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 快捷键与触发角开关：`disable-hotkeys` / `enable-hotkeys` / `toggle-hotkeys`、`disable-hot-corners` / `enable-hot-corners` / `toggle-hot-corners`（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 其余单命令：`clear-snip-history` 清空截图记录；`open-preferences` 打开首选项；`docs` 打开帮助窗口；`exit` 退出 Snipaste（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- `--config=/path/to/config.ini` —— 指定配置文件路径，支持绝对/相对路径，属于带 `*` 的启动阶段选项（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 静默组合示例：`snip --last -o clipboard`、`snip --full -o clipboard`、`snip --shadow --active-window -o clipboard` 均为无需交互的后台调用（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- 与其他工具串联示例：`snip -o "d:/temp/source.png";exec(cmd /c tesseract.exe ...)` 把截图交给本地 OCR 后再用记事本显示结果（来源：https://docs.snipaste.com/wiki/命令行选项.md）

## 9. 平台差异与限制

- 发行形态：Windows 桌面版（x64/x86/ARM64/XP）、微软商店版、macOS DMG（亦可 `brew install snipaste --cask`）、Linux AppImage（x86_64）（来源：https://docs.snipaste.com/wiki/下载.md）
- macOS 需「辅助功能」权限才能检测界面元素与用 `WASD` 移动光标（来源：https://docs.snipaste.com/wiki/故障排除.md）
- macOS 10.15 Catalina 起需「屏幕录制」权限，否则截图只显示桌面；已勾选仍异常时需取消再重勾并重启 App（来源：https://docs.snipaste.com/wiki/故障排除.md）
- macOS 界面元素检测默认关闭，需到 `首选项` - `截屏` - `行为` 勾选「自动检测界面元素」并完成授权（来源：https://docs.snipaste.com/wiki/故障排除.md）
- macOS 其他限制：运行中连接/断开外接屏可能导致截图模糊（重启恢复）；取色器色彩空间可设置，默认 sRGB；内置快捷键表中 `Ctrl` 全部换成 `Cmd`（来源：https://docs.snipaste.com/wiki/故障排除.md）
- Linux 限制：不支持父/子元素检测；截屏支持 Wayland；截屏可捕捉光标图案；适配深色模式与 qt6ct（来源：https://docs.snipaste.com/wiki/专业版.md）
- Windows 独占的高级设置：`process_priority`、`exclude_from_detection`、`crashes`（来源：https://docs.snipaste.com/wiki/高级设置.md）
- Windows 独占命令：`paste-as-image`、`paste-as-plain-text`（来源：https://docs.snipaste.com/wiki/命令行选项.md）
- Windows 平台特性：原生分享按钮（Windows 10+）、Windows 11 虚拟桌面、HDR 色彩校正、Windows ARM64 支持（来源：https://docs.snipaste.com/wiki/更新日志.md）
- 商店版启动参数写作 `Snipaste` 而非完整 exe 路径；商店版误勾「以管理员身份」后无法启动，需删除 `config.ini` 中 `as_admin=true`（来源：https://docs.snipaste.com/wiki/故障排除.md）
- Windows 版可能被网课/教程播放软件主动检测进程并杀掉，表现为启动几秒后闪退（来源：https://docs.snipaste.com/wiki/故障排除.md）
- 快捷键不响应：Snipaste 非管理员运行而当前窗口以管理员身份运行时失效（来源：https://docs.snipaste.com/wiki/故障排除.md）
- 无法截取菜单：Windows 下按下 `Alt` 菜单会消失，截图快捷键不要含 Alt，或改用延时截屏（来源：https://docs.snipaste.com/wiki/故障排除.md）
- 配置无法保存：`config.ini` 所在目录无写权限（如 `C:\Program Files`），需换目录或以管理员权限运行；不可写入时会弹通知提示（来源：https://docs.snipaste.com/wiki/故障排除.md）
- 浏览器界面元素检测需开无障碍：Chrome/Edge 访问 `chrome://accessibility` 勾选相关项或加 `--force-renderer-accessibility`；Firefox 需放开无障碍服务、`accessibility.force_disabled=0`（来源：https://docs.snipaste.com/wiki/故障排除.md）
- 贴图无法拖出屏幕上边界：需在系统性能设置中勾选「拖动时显示窗口内容」（来源：https://docs.snipaste.com/wiki/故障排除.md）
- 功能缺口（文档自述）：滚动截图、GIF 录制未提供（FAQ 指向 issue #282 跟踪），Mac/Linux 版能力同在此处跟踪（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 剪贴板中的图像质量不可设置；输出图片质量用 `-1` 自动 / `0` 最低 / `100` 最高（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 必须常驻后台（原文：「贴图功能需要它常驻后台」）；取消贴图平滑缩放可改善文字在高分屏放大后的显示（来源：https://docs.snipaste.com/wiki/常见问题.md）
- 多屏不同 DPI 下标注工具栏等界面保持统一视觉大小；屏幕 DPI 变更会动态适配并更新托盘图标（来源：https://docs.snipaste.com/wiki/更新日志.md）

## 10. 版本演进（只留功能里程碑）

仅摘功能节点，不含修复类条目。

- v2.11.3：支持自定义部分应用内快捷键（首选项 - 控制 - 应用内快捷键）；文字识别新增腾讯与 OCR.space 接口（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.11：支持文字识别（OCR）；新增命令行 `--hold` 与 `--block [SECONDS]`；截图支持更大圆角半径；可自定义贴图选区缩略图快捷键；支持 Windows ARM64 与 HDR 色彩校正（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.10.x：`snip --active-screen`（v2.10.7）、macOS 取色器色彩空间（v2.10.6）、取色器显示 HSV 与绑定按键到自定义输出（v2.10.4）、离线激活与 `Interface/hide_output_options`（v2.10.3）、`Snip/animated_region_transition`（v2.10.2）（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.9.x：贴图支持 Windows 11 23H2 虚拟桌面、`-o silent`（v2.9.1）；Linux 截屏支持 Wayland 与捕捉光标图案（v2.9）（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.8.x：圆角矩形截图、多组计数标注、`--keep_aspect_ratio`、WebP 保存、箭头开关按钮（v2.8.6）；`Ctrl+Alt+C` 复制图像为文件、`barcode-decode`、预设截图区域（v2.8.5）；`F5` 刷新截图（v2.8.2）；二维码/条形码识别、自由选中、虚拟桌面、macOS 多屏（v2.8）（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.6：放大镜标注、马克笔支持椭圆形状、更多箭头样式、截图大小预设、Windows 10 原生分享、主题色跟随系统、macOS M1（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.5.x：自定义调色板颜色数量、双向/反向箭头、虚线与点线、带边框与带阴影输出、文字背景色、批量保存贴图（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.4：序号标注、圆角矩形标注、文字描边、文字背景填充、`Ctrl+A` 全选贴图、文字字号下拉（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.3.x：贴图反色、以原始大小保存已缩放贴图、透明白板可开关穿透、`Paste/disable_frame_resize`（v2.3.x）；标注中心点/等比缩放、多输出组合、保存时隐藏窗口、触发角黑名单、`Ctrl+W` 关闭贴图、apng 动画（v2.3）（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.2.x：多选贴图全操作与批量缩放、固定长宽比截图、贴图固定到虚拟桌面、`create-group`（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.1：旋转矩形/椭圆标注、自定义贴图尺寸与背景色、`Ctrl` 拖拽复制标注、滚动进入元素框选、网页图片自动下载、`external` 支持环境变量、文字斜体（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v2.0：延迟截图升级为自定义截图对话框（可指定位置或尺寸）；贴图有唯一文字标注时可复制其文字（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.16：自定义贴图缩放/透明度快捷键、完全禁用光标捕捉、截图按 `V` 复制图片尺寸、贴图右键 33.3% 缩放、`Ctrl+Insert` 复制（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.15：商店版新增命令行调用；配置存储路径可在选项窗口设置；新增截图输出方式相关命令行参数（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.14：`config.ini` 支持软链接；截图按 `Alt` 显示两条中央辅助线（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.13：新增全局快捷键「截图并自动复制」、命令行 `--at` 指定贴图位置、单张贴图鼠标穿透、HSV/HSL/HSI 范围改为 0–100（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.12：支持将单个贴图设为鼠标穿透；贴图窗口支持 `Ctrl+V`；存储路径支持环境变量（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.10.x：颜色卡片增加 HSV 与 HSI；折线、画笔、马赛克、橡皮擦可整体拖动；首次支持命令行选项；全部标注形状支持 `Shift` 约束；托盘菜单新增「帮助」（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.8.x：`PrtSc` 参与全局快捷键、内置快捷键列表带「复制」按钮、可设置记号笔颜色透明度（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.7：贴图默认透明度、进入截屏默认显示全屏十字线、箭头宽度固定（来源：https://docs.snipaste.com/wiki/更新日志.md）
- v1.3 / v1.0：`Shift` + 方向键缩小截图区域；2016.07.28 首次发布（来源：https://docs.snipaste.com/wiki/更新日志.md）

## 11. 页面覆盖表

**口径说明（可机器复核）**：下表「来源标注次数」= 正文（§1–§10，不含本章与附录）中出现 `（来源：<该页 URL>）` 的次数，一条功能若合并了多页信息就只保留最先命中的那一页作为出处，因此该数字**必然小于**该页原文能拆出的原始条目数。复核命令：

```bash
awk '/^## 11\./{exit} {print}' Snipaste功能清单.md | grep -o '（来源：[^）]*）' | sort | uniq -c | sort -rn
```

「原始条目数」列是首次盘点从该页拆出的条目数（含后续被合并掉的重复项），仅作抓取饱和度的参照，不再与正文条目对应。

| # | 源 URL | 抓取结果 | 原始条目数 | **来源标注次数** | 主要落点章节 |
| --- | --- | --- | --- | --- | --- |
| 1 | https://docs.snipaste.com/_sidebar.md | 成功（200 / 562B） | 12 页清单 | 0 | 页面清单与饱和检查，无功能条目 |
| 2 | https://docs.snipaste.com/zh-cn/_sidebar.md | 成功（200 / 631B） | 12 页清单 | 0 | 锁定中文站 12 个正文页，与英文站同构 |
| 3 | https://docs.snipaste.com/wiki/命令行选项.md | 成功（200 / 10118B） | 62 | **57** | §8（46 条）、§2、§4、§5、§6 |
| 4 | https://docs.snipaste.com/wiki/更新日志.md | 成功（200 / 78929B / 1687 行） | 56 | **41** | §10（21 条）、§2、§3、§5、§9 |
| 5 | https://docs.snipaste.com/wiki/高级设置.md | 成功（200 / 6590B） | 40 | **36** | §7（23 条）、§2、§3、§4、§6 |
| 6 | https://docs.snipaste.com/wiki/专业版.md | 成功（200 / 13194B） | 46 | **31** | §2、§3、§4、§6、§9（授权与分档内容整体不入表） |
| 7 | https://docs.snipaste.com/wiki/基础操作.md | 成功（200 / 6643B） | 27 | **26** | §1、§2、§3、§4、§5、§6 |
| 8 | https://docs.snipaste.com/wiki/内置快捷键.md | 成功（200 / 2283B） | 15 | **13** | §2、§3、§4、§6（三张快捷键表合并去重） |
| 9 | https://docs.snipaste.com/wiki/故障排除.md | 成功（200 / 8976B） | 11 | **11** | §9 平台差异与限制（Windows / macOS 逐条） |
| 10 | https://docs.snipaste.com/wiki/常见问题.md | 成功（200 / 4371B） | 9 | **10** | §1、§3、§4、§5、§9（一条 FAQ 可支撑多节，故标注次数略高于原始条目） |
| 11 | https://docs.snipaste.com/wiki/高级技巧.md | 成功（200 / 1239B） | 6 | **6** | §2 快速标注界面元素 + 空格移动选区、§3 透明度与 Shift 变形、§4 贴图吸附 |
| 12 | https://zh.snipaste.com/（官网首页） | 成功（30KB HTML） | — | **3** | §1 卖点、§4 右键菜单尺寸行、§5 自动备份恢复 |
| 13 | https://docs.snipaste.com/wiki/帮助翻译.md | 成功（200 / 261B） | 1 | **1** | §1 多语言 |
| 14 | https://docs.snipaste.com/wiki/下载.md | 成功（200 / 683B） | 1 | **1** | §1 发行形态、§9 平台差异 |
| 15 | https://docs.snipaste.com/wiki/激活指引.md | 成功（200 / 390B） | 1（跳转入口） | 0 | 授权流程，按「不分档」要求不入表 |
| 16 | https://docs.snipaste.com/wiki/激活指引-‐-桌面版.md | 成功（200 / 1934B，sidebar 别名补充） | 3 | 0 | 同上 |
| 17 | https://docs.snipaste.com/wiki/激活指引-‐-微软商店版.md | 成功（200 / 1009B） | 2 | 0 | 同上 |
| 18 | https://docs.snipaste.com/wiki/Mac-公测版.md | **抓取失败：HTTP 404**（中文 sidebar 无此条目，英文站 Beta-for-Mac.md 同为 404） | 0 | 0 | —（不可用，未纳入统计） |
| 19 | https://docs.snipaste.com/wiki/Advanced-Configs.md（英文站） | 成功（200 / 7375B） | 0（交叉核对用） | 0 | §7：配置键与中文页完全一致，无增量，只用于确认键名 |

**统计**：19 行 = 成功 18 行 + 失败 1 行；**来源标注次数合计 236**，与复算命令输出一致。成功行中：中文 sidebar 正文页 12 个、官网首页 1 个、sidebar 别名子页 2 个、导航清单 2 个（无功能条目）、英文站交叉核对页 1 个（配置键无增量）。

**缺口说明**：
- `Mac-公测版.md` 在中文与英文站均 404，文档侧未提供 macOS 公测版的独立说明；macOS 能力只从 `故障排除.md`、`内置快捷键.md`、`更新日志.md` 中提取。
- 英文站其余页面（Getting-Started / Key-Bindings / FAQ / Advanced-Tips / Command-Line-Options / Troubleshooting）已抓对照，命令行命令集合与中文站完全一致，未发现中文站缺失的功能条目。
- 授权、定价、设备台数与退款规则属于商业条款而非产品功能，按「单文件、不分档」要求整体不收录。

## 附录：抓取与校验方式

- 全部抓取先落 `/tmp/snipaste-docs/`，再统一整理，避免边抓边写漏页。
- `web_fetch` 对本站 `.md` 返回 `unsupported content type "application/octet-stream"`，改用 `curl -sSL --compressed -x http://127.0.0.1:7890`。
- 逐页验收：HTTP 200 且正文为 Markdown（非 HTML 骨架），最小正文页 `帮助翻译.md` 261B、`激活指引.md` 390B 均在数百字符量级且内容完整。
- 中文文件名的 URL 编码问题用 `python3 -c "urllib.parse.quote"` 处理。

---

盘点说明：全部结论来自上述官方文档原文；文档未提及的能力（如剪贴板历史列表、粘贴栈、滚动截图、GIF 录制）一律标注「文档未明确」或不列入；本文不涉及任何本地实现对照。

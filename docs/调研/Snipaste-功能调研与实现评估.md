# Snipaste 功能调研与实现工时评估

> 目的：为 toolbar（Swift 6.3 + AppKit 菜单栏 App，macOS 14+）评估「重做一遍 Snipaste」的功能范围与工期，输出可勾选的功能清单与分档方案。调研时间 2026-10，来源见文末。
>
> 口径说明：**人日** = 1 名熟练 macOS 工程师的有效工程日，含自测与调试，**不含视觉设计打磨**、不含多语言与上架审核。单人 + AI 辅助的实际日历时间约按 **1.5–1.8 倍加速**折算。

## 一、速览结论

1. Snipaste 只有三大块：**Snip（截图）· Annotation（标注）· Paste（贴图）**。用户说的「固定」= Paste 的 pin to screen：把截图或剪贴板内容变成**置顶浮窗**，可缩放、调透明度、旋转镜像、点击穿透、成组管理。这是它真正的护城河，也是本项目必须做的那一块。
2. 四档工期（完整重做口径）：

| 档位 | 内容 | 人日 | 单人 + AI 日历 |
|---|---|---|---|
| **A 最小可用（含固定）** | 截图选区 + 基础标注 + 贴图置顶浮窗 | 50–60 | 7–9 周 |
| **A− 只做截图 + 固定** | 跳过标注，热键截图 → 贴到屏幕 | 30–35 | 4–5 周 |
| **B 对齐免费版** | A + 放大镜/取色/历史/延时/白板/各类内容转贴图/偏好完善 | 92–105 | 3–4 个月 |
| **C 对齐专业版全量** | B + 元素检测/二次编辑/多选分组/OCR/CLI/触发角 | 135–155 | 5–6.5 个月 |
| 团队 3 人并行（C 档） | 拆分截图 / 标注 / 贴图三条线 | — | 10–13 周（含集成期） |

3. **真正的不确定性不在画图，在 macOS 系统层**：屏幕录制权限（TCC）、截图指示器、界面元素检测（Accessibility）、全屏 App 覆盖。本机（macOS 27.0.1）已实测：ScreenCaptureKit 全屏截图 **67 ms**、AX 元素定位 **82 ms**，两条链路都通（见 §5.1），风险落在权限摩擦与观感，而非可行性。
4. 现有 toolbar 已有可复用基建，约值 **8–10 人日**：Carbon 全局热键 + 录制控件、设置窗（delegate + 持久化）模式、SQLite schema、DEBUG 离屏快照取证、`build-app.sh` 打包链。
5. 风险最高的不是功能量，而是**细节一致性**：Snipaste 单是「贴图」就有恢复/销毁、点击穿透、背景模式、solo、分组 5 套语义互相咬合；标注的二次编辑与撤销重做也强耦合。C 档里约 40% 的工时花在这类「看起来不像功能」的边界上。

## 二、功能全清单（可勾选）

标记：**免费** = Snipaste 免费版即有；**Pro** = 专业版独占。复杂度：低 / 中 / 高 / 极高。

### 2.1 截图 Snip

| 编号 | 功能 | 版本 | 复杂度 | 人日 |
|---|---|---|---|---|
| S1 | 全屏捕获：多显示器、Retina 缩放、屏幕录制权限 | 免费 | 高 | 3 |
| S2 | 选区覆盖层：每屏一个 overlay 窗口、层级、跨 Space、防闪烁 | 免费 | 高 | 3 |
| S3 | 选区交互：拖拽新建、8 向手柄 resize、整体移动、重选 | 免费 | 高 | 4 |
| S4 | 像素级微调：WASD / 方向键 / Ctrl 扩大 / Shift 缩小 | 免费 | 中 | 1.5 |
| S5 | 全屏选区（⌘A）、上次区域（R）、历史回放（`,` `.`） | 免费 | 中 | 2 |
| S6 | 窗口检测：鼠标下窗口高亮框选、排除自身窗口与桌面 | 免费 | 高 | 3 |
| S7 | 保存链路：复制到剪贴板 / 另存为 / 快速保存 / 自动保存目录 | 免费 | 中 | 2.5 |
| S8 | 放大镜：像素采样、网格、坐标与尺寸、取色预览、Alt 唤起 | 免费 | 高 | 3 |
| S9 | 取色：RGB / HEX / HSV 切换、像素取色复制、贴成色卡 | 免费 | 中 | 1.5 |
| S10 | 延时截屏（倒计时） | 免费 | 低 | 1 |
| S11 | 自定义尺寸输入 + 保持长宽比锁定 | 免费 | 中 | 2 |
| S12 | 白板模式（纯色白板 + 透明白板） | 免费 / Pro | 中 | 2 |
| S13 | 捕捉鼠标光标图案（` 键切换） | 免费 | 低 | 1 |
| S14 | 界面元素检测 + 滚轮切换父/子元素 | Pro | 极高 | 6 |
| S15 | 超级截屏（免热键 Win/Cmd + 拖拽即截） | Pro | 高 | 3 |
| S16 | 刷新截图 F5、活动窗口截屏、圆角矩形截图 | Pro | 中 | 3 |

### 2.2 标注 Annotation

| 编号 | 功能 | 版本 | 复杂度 | 人日 |
|---|---|---|---|---|
| A1 | 图元模型 + 渲染管线 + 画布重绘（矢量存储，可导出位图） | 免费 | 高 | 4 |
| A2 | 撤销 / 重做 / 清除全部（⌘Z / ⌘Y / ⌘⇧Z） | 免费 | 中 | 1.5 |
| A3 | 矩形 / 椭圆 / 圆角矩形 + 填充 + 透明度 + 虚线（Pro） | 免费 | 高 | 4 |
| A4 | 直线 / 折线 / 箭头（Tab 切换、样式、双向与反向 Pro） | 免费 | 高 | 3.5 |
| A5 | 画笔 / 记号笔（笔尖 1–5、平滑、滚轮调粗细） | 免费 | 中 | 2.5 |
| A6 | 马赛克 / 模糊（矩形与椭圆两种形状，像素/GPU 处理） | 免费 | 很高 | 4 |
| A7 | 文字标注：输入、缩放、旋转、背景填充、描边、Shift 回正 | 免费 | 极高 | 5 |
| A8 | 橡皮擦（矢量删除与像素擦） | 免费 | 中 | 2 |
| A9 | 工具条：工具切换、颜色板、线宽、空格显隐、右键完成当前图形 | 免费 | 高 | 3 |
| A10 | 调色板定制：拖动排序、滚轮调透明度、分形状记忆颜色 | Pro | 中 | 2 |
| A11 | 二次编辑：选中已有图形、拖动/缩放/旋转、删除、复制粘贴、Ctrl 拖拽克隆 | Pro | 极高 | 5 |
| A12 | 序号标注（自动递增、点击放置、可改起点） | Pro | 中 | 1.5 |
| A13 | 放大镜标注（圆内放大局部，可调倍数） | Pro | 高 | 2 |

### 2.3 贴图 Paste（= 固定到屏幕，用户指定必须有）

| 编号 | 功能 | 版本 | 复杂度 | 人日 |
|---|---|---|---|---|
| P1 | 贴图窗口基类：无边框、置顶层级、跨 Space、全屏 App 之上、阴影与圆角 | 免费 | 高 | 3 |
| P2 | 拖动 + 屏幕边缘吸附 + 滚轮缩放 + 边框拖拽改尺寸 | 免费 | 高 | 3.5 |
| P3 | 透明度调节（Ctrl + 滚轮 / 快捷键） | 免费 | 低 | 1 |
| P4 | 旋转 90°（1/2）、水平与垂直镜像（3/4）、中键还原 100% | 免费 | 中 | 1.5 |
| P5 | 关闭（Esc/双击）、销毁（⇧Esc）、重贴恢复语义（恢复计数上限） | 免费 | 高 | 2 |
| P6 | 隐藏全部贴图（⇧F3）与再显示 | 免费 | 低 | 0.5 |
| P7 | 右键菜单：复制、另存、旋转、透明度、置顶开关、销毁 | 免费 | 中 | 1 |
| P8 | 固定尺寸快速缩略图（⇧ 双击） | 免费 | 中 | 1.5 |
| P9 | 颜色卡片（颜色值贴成色块窗口） | 免费 | 低 | 1 |
| P10 | 置顶开关（可取消置顶） | Pro | 低 | 0.5 |
| P11 | 点击穿透（ignoresMouseEvents 切换） | Pro | 中 | 1 |
| P12 | 背景模式：透明 / 伪透明 / 暗色棋盘 / 亮色棋盘 | Pro | 高 | 1.5 |
| P13 | 自由裁剪（缩略图上框选裁剪） | Pro | 高 | 1.5 |
| P14 | 多选（⌘ 点选，批量移动 / 透明度 / 关闭） | Pro | 高 | 1.5 |
| P15 | 贴图组：分组、重命名、排序、组管理面板 | Pro | 高 | 1.5 |
| P16 | Solo 模式（只显示当前贴图，其余暂时隐藏） | Pro | 中 | 1 |
| P17 | 灰度（5）/ 反色（6）切换 | Pro | 低 | 1 |
| P18 | 输入尺寸或缩放比例 | Pro | 低 | 1 |
| P19 | 可编辑颜色卡片（改颜色值） | Pro | 低 | 0.5 |
| P20 | 网页图片粘贴 / 拖拽到贴图（需联网渲染） | Pro | 中 | 2 |

### 2.4 内容源：把剪贴板变贴图

| 编号 | 功能 | 版本 | 复杂度 | 人日 |
|---|---|---|---|---|
| C1 | 剪贴板图片 → 贴图 | 免费 | 低 | 1 |
| C2 | 文件路径 → 贴图（图片文件显示图像，非图片显示图标与文件名） | 免费 | 中 | 2 |
| C3 | 纯文本 → 贴图（自动换行、最大宽度、字号、复制回纯文本） | 免费 | 中 | 2 |
| C4 | HTML 富文本 → 贴图（样式渲染、强制换行） | 免费 | 高 | 3.5 |
| C5 | 颜色值（RGB/HEX）→ 色卡贴图 | 免费 | 低 | 1 |

### 2.5 系统集成与周边

| 编号 | 功能 | 版本 | 复杂度 | 人日 |
|---|---|---|---|---|
| G1 | 偏好设置窗（截屏 / 贴图 / 标注 / 控制 / 外观 五页 + 持久化） | 免费 | 高 | 5 |
| G2 | 命令行选项（snip / paste / --full / --last / --area / -o clipboard 等） | 免费 / Pro | 中 | 2.5 |
| G3 | 显示器增删、分辨率变化、跨 Space 的贴图存活处理 | 免费 | 中 | 2.5 |
| G4 | OCR 文字识别（Vision）与文字提取面板 | Pro | 中 | 3 |
| G5 | 二维码 / 条形码识别 | Pro | 低 | 1 |
| G6 | 任意命令绑全局热键 + 忽略程序列表（模糊匹配） | Pro | 中 | 3 |
| G7 | 屏幕触发角（四角动作） | Pro | 低 | 1.5 |
| G8 | 托盘图标鼠标动作自定义（左/中/右键） | Pro | 低 | 1 |
| G9 | 与现有剪贴板历史打通（在历史卡片上直接「贴到屏幕」） | 本项目特色 | 低 | 1 |

### 2.6 工程与交付（不可省）

| 编号 | 内容 | 人日 |
|---|---|---|
| E1 | 权限引导：屏幕录制 + 辅助功能，检测、跳转系统设置、重启提示 | 2 |
| E2 | 测试：单元（图元模型、坐标换算、裁剪）+ 冒烟（多屏 / Retina / 全屏 App）+ 回归清单 | 6 |
| E3 | 打包签名 / 公证 / 版本号与更新说明 | 2.5 |
| E4 | 文档 + 验收清单 + 已知限制 | 2 |

## 三、分档汇总

| 档位 | 包含编号 | 人日 |
|---|---|---|
| **A 最小可用（含固定）** | S1–S5、S7、A1–A5、A7、A9、P1–P7、C1、E1–E2（精简） | 50–60 |
| **A− 只做截图 + 固定** | S1–S5、S7、P1–P7、C1、E1 | 30–35 |
| **B 对齐免费版** | A 档 + S6、S8–S13、A6、A8、P8–P9、C2–C5、G1、G3、E3–E4 | 92–105 |
| **C 对齐专业版全量** | B 档 + S14–S16、A10–A13、P10–P20、G2（全量）、G4–G8 | 135–155 |

> 校验：A 档约 57 人日 ≈ 单人全职 2.5–3 个月，AI 辅助 7–9 周；这是「能用」的门槛，也是我建议的第一交付。若只要「截图 → 固定」，A− 档 30–35 人日即可。
> **若把最低系统版本定为 macOS 26**（可用 `SCScreenshotManager.captureScreenshot(rect:)`，天然 Retina、67 ms 出图），A 档可再省 2–3 人日；若坚持兼容 macOS 14/15，截图层需三套 API 分支，A 档取区间上限。
> B 档之后，每加一项 Pro 功能的边际成本都在涨：A11 二次编辑（5）、S14 元素检测（6）、P12 背景模式（1.5）+ P14/P15 多选分组（3）是四个「看起来小、其实大」的坑。

### 建议排期（A 档，每 2 周一个可运行产物）

| 周次 | 交付物（可跑可验） |
|---|---|
| W1 | 技术闭环：热键 → 全屏截图 → 覆盖层选区 → 复制到剪贴板 |
| W2–W3 | 多屏 / Retina / 放大镜 / 窗口检测；标注图元模型 + 矩形 / 箭头 / 画笔 |
| W4–W5 | 文字标注 / 马赛克 / 撤销重做 / 工具条 |
| W6–W7 | **贴图固定**：置顶浮窗、拖动缩放、透明度、旋转镜像、关闭与重贴恢复、右键菜单 |
| W8 | 设置页、权限引导、打包、回归清单 |

> 顺序原则：**先让「截图 → 固定」这条最短链路能跑**，标注是叠加在它上面的第二层；不要先做标注引擎再回头做贴图，那样最难验证的窗口行为会被推迟到最后。

## 四、复用现有 toolbar 的资产

| 现有资产 | 位置 | 可复用度 | 节省 |
|---|---|---|---|
| Carbon 全局热键 + 录制控件 + 冲突检测 | `Sources/NetworkMonitor/Clipboard/GlobalHotKey.swift`、`HotKeyRecorderView.swift` | 高（直接扩成多命令注册表） | 2–3 人日 |
| 设置窗模式（delegate 回调 + 持久化 + 权限状态） | `ClipboardSettingsWindow.swift` | 高（复制骨架加页签） | 2–3 人日 |
| SQLite + Repository 分层 | `DatabaseManager+*.swift` | 中（贴图组/截图历史可落库） | 1.5 人日 |
| DEBUG 离屏快照取证 | `Debug/MenuPanelSnapshot.swift` | 高（贴图与标注面板的取证可复用同一套路） | 1–1.5 人日 |
| 打包脚本 + 单文件 500 行门禁 | `Scripts/build-app.sh`、`check-file-size.sh` | 直接用（注意标注引擎必须拆多文件） | 0.5 人日 |

## 五、本机实测与技术风险

### 5.1 本机实测（macOS 27.0.1 / SDK 27.0，2026-10-24）

| 验证项 | 结果 | 结论 |
|---|---|---|
| 屏幕录制授权（终端） | `CGPreflightScreenCaptureAccess() == true` | 开发期可直接跑；打成 .app 后是另一个 TCC 条目，需重新授权 |
| 辅助功能授权 | `AXIsProcessTrusted() == true` | 同上，剪贴板自动粘贴已在用同一权限 |
| `CGDisplayCreateImage` | SDK 标注 `SCREEN_CAPTURE_OBSOLETE(10.6, 14.4, 15.0)` | **macOS 15 起已废弃不可用**，不能作为兜底路线 |
| `captureImage(contentFilter:configuration:)`（macOS 14.0+） | 成功，1512×982（1x），首次约 235 ms | 可用，但需自己按 scaleFactor 出 2x 图 |
| `CGWindowListCreateImage` | SDK 同标 `obsoleted=15.0`；macOS 27 beta 起对 Metal 窗口返回纯色暗帧 | 窗口「框选」只读 bounds 不受影响；窗口截图必须走 SCK |
| `captureScreenshot(rect:configuration:)`（macOS 26+） | 成功，3024×1964（2x），67 ms | **建议主路线**：天然 Retina、可指定 `showsCursor`、可直接落盘 |
| `AXUIElementCopyElementAtPosition` | 命中前台 App 的 `AXScrollArea`，82.5 ms | 元素检测（S14）可行，需缓存 + 超时保护 |

### 5.2 关键风险

1. **最低系统版本决定截图层工时**：`SCScreenshotManager.captureImage(contentFilter:configuration:)` 是 **macOS 14.0+**，按矩形抓全屏的 `captureImage(in:)` 是 15.2+，26+ 才有 `captureScreenshot(rect:configuration:)`。兼容 14 的代价只是手算 scaleFactor 与多屏拼接（+2–3 人日）；建议仍把最低版本定 macOS 26（新 API 天然 Retina、可控制光标与阴影、可直接落盘），`Package.swift` 的 `.v14` 一并调整。
2. **截图指示器是确定存在的产品代价**：单帧截图也会闪一次紫色捕获标识（会话结束即消失，观感是「闪一下」）；频繁截图会累计并触发 macOS 15 的「已访问你的屏幕和系统音频 N 次」通知，Apple DTS 明确目前无法关闭；持续 SCStream 更是常亮。→ 用「按需捕获 + 立刻释放」把暴露面压到最小，并在 UI 说明里提前讲清。
3. **TCC 开发期必然反复授权**：ad-hoc 签名没有稳定 designated requirement，DTS 明确每次覆盖安装都会重新要屏幕录制权限。`build-app.sh` 有 `SIGN_IDENTITY` 分支但在无证书时 fallback 到 `-`（ad-hoc），调试期应切到固定自签身份；bundle id 也必须固定（改 id 等于换新 App，旧授权不继承）。授权后需重启 App 才生效。
4. **界面元素检测（S14）按「不可靠外挂」设计**：AX 调用是跨进程 XPC，Electron / 多标签浏览器这类巨树会挂住（社区做法：2000 节点上限 + 30s 超时）。必须 `AXUIElementSetMessagingTimeout`（system-wide 0.1–0.3s）+ 后台队列 + 60–100ms 节流；失败码 -25208（未实现）/ -25204（目标无响应）/ -25211（未授权）一律降级为「窗口级框选」，绝不允许阻塞截图主流程。
5. **贴图压全屏是四件套，缺一不可**：`NSApp.setActivationPolicy(.accessory)` + `NSPanel` 带 `.nonactivatingPanel`（普通 NSWindow 会激活本 App、把别人的全屏 App 踢出 Space）+ `level = .screenSaver`（`.floating` / `.statusBar` 都在全屏内容之下）+ `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]`。DTS 在 macOS 26 对 Safari / QuickTime / YouTube 全屏实测通过；配好这套不需要监听 `activeSpaceDidChange` 手动 `orderFrontRegardless()`。已知限制：系统 UI（控制中心、锁屏/屏保，层级 > 1000）仍在贴图之上。
6. **多屏 + Retina 坐标**：point / pixel / 各屏缩放比三套坐标系，是 bug 高发区；一开始统一换算工具并配单元测试。
7. **色彩管理**：实测 `sdrImage.colorSpace.name` 为 nil，保存 PNG/JPEG 时要做 sRGB 归一并与原图比对，否则会出现「截图偏色」。

**建议开工前 1–2 天的验证原型**（做完再承诺工期）：① 热键 → 全屏截图 → 覆盖层选区 → 复制；② 选区图贴成置顶浮窗并拖动缩放；③ AX 元素检测在 Finder / Chrome / Xcode 三个 App 的命中率。

## 六、主要来源

- Snipaste 官方文档：基础操作 <https://docs.snipaste.com/zh-cn/getting-started>
- Snipaste 快捷键表：<https://docs.snipaste.com/zh-cn/key-bindings>
- Snipaste 专业版功能对比：<https://docs.snipaste.com/zh-cn/pro>
- Snipaste 高级配置（无 UI 选项全量）：<https://docs.snipaste.com/zh-cn/advanced-configs>
- Snipaste 命令行选项：<https://docs.snipaste.com/zh-cn/command-line-options>
- Snipaste 更新日志（功能演进与坑位）：<https://docs.snipaste.com/zh-cn/changelog>

### macOS 技术事实来源

- ScreenCaptureKit 文档与「Capturing screen content in macOS」：<https://developer.apple.com/documentation/screencapturekit> · <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>
- 单帧截图的授权与指示器行为（DTS 讨论）：<https://developer.apple.com/forums/thread/732962> · <https://developer.apple.com/forums/thread/784467>
- 弃用 API 的编译/弹窗后果：<https://bugs.webkit.org/show_bug.cgi?id=277564> · <https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes>
- CGWindowListCreateImage 对 Metal 窗口返回暗帧：<https://github.com/viatearz/MaaTools/pull/1>
- AX 元素定位接口与超时坑：<https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition> · <https://github.com/feedback-assistant/reports/issues/368>
- 贴图浮窗跨全屏的 DTS 配方：<https://developer.apple.com/forums/thread/826308> · <https://developer.apple.com/forums/thread/800091>
- TCC 与代码签名身份：<https://developer.apple.com/forums/thread/795739> · <https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements>

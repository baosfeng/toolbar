# 剪贴板对标 OneClip 第二批增量设计规格

> **何时阅读：** 改剪贴板图片格式兼容、缩略图加载、卡片右键菜单与删除确认，或准备派发剪贴板相关任务前。
> 状态：已定稿（口径冻结）｜基线：main @ 5657384｜日期：2026-11-13
> 相关：[第二批调研证据](剪贴板对标-OneClip-第二批调研证据.md) · [第一批增量设计规格](剪贴板对标-OneClip-增量设计规格.md) · [剪贴板对标 OneClip 调研结论](../调研/剪贴板对标-OneClip-调研结论.md)
> 约束：单文件 ≤500 行 / 15 KiB（15360 字节）；注释必须中文；日志统一走 `LoggingService`

## 1. 背景与范围

第一批增量（图片磁盘回收 / 动态轮询 / 文件分类图标）已合并发版。第二批把两份逐条取证（功能面 + 性能面）里**经核实为 OneClip 真实存在、且我们确实缺失**的项，收敛为 3 项；OneClip 侧带调用点核查的缺陷清单见证据文档第 4 节，不作为对标目标。

范围：**只做 3 项**，全部不动数据库 schema、不动面板版式骨架（卡片 176×198、工具条 32pt、提示行 24pt 三处尺寸不变）。

## 2. 三项增量

### 2.1 增量 A：图片格式兼容（P0，实质缺陷）

**问题（可复现）**：采集侧只认 `.png` 优先、`.tiff` 兜底（`PasteboardWatcher.swift:302-306`）。从「预览 / 照片 / 浏览器 / 微信」复制 HEIC / WebP / GIF / JPEG 图片时，pasteboard 上没有 png 也没有 tiff，整条复制**静默漏采**（日志只有「剪贴板无可用内容」）。OneClip 走格式探测表 + 自定义类型扫描（`ClipboardManager.swift:829-840, 954-969`，有活调用点），因此它能采到。

**设计**：

1. Core 新增 `ClipboardImageFormat`（纯函数，不依赖 AppKit）：
   - 显式白名单类型名（按优先级降序）：`public.png` / `public.tiff` / `public.jpeg` / `public.heic` / `public.heif` / `org.webmproject.webp` / `com.compuserve.gif` / `com.microsoft.bmp`。
   - `orderedCandidates(from typeNames: [String]) -> [String]`：先按白名单顺序输出命中的类型名（去重、大小写不敏感、容忍前后空白），再追加**非白名单但 `UTType` conforms(to: .image)** 的类型名（兜底未来格式），最后才判定无候选。
   - 判据是**正向白名单 + 统一类型系统兜底**，不用黑名单排除法。
2. `PasteboardWatcher.imageRepresentation(of:)` 改为：按 `orderedCandidates` 顺序取第一个 `data(forType:)` 非空的表示；原有「PNG 优先、TIFF 兜底」语义降级为该白名单的前两项，行为兼容。
3. 真实类型校验仍由现有 `ClipboardImageDecoder.typeIdentifier(of: data)` / `fileExtension(of: data)` 完成（落盘扩展名取自字节真实类型），像素守卫 `ClipboardImagePolicy.rejection` 前置不变。
4. 回写补齐多表示：`PasteboardWriter` 图片分支在同一个 `NSPasteboardItem` 上同时写入 **PNG + TIFF**（JPEG 仅在原图为 JPEG 或 PNG/TIFF 编码失败时写入），对标 `ClipboardManager.swift:2138-2149`（TIFF+PNG+JPEG 并存），解决只认 TIFF 的老 App 粘不上图的问题。
   - 新增 `ClipboardImageDecoder.tiffData(from: CGImage)`；JPEG 编码复用同一 ImageIO 目的地（quality 0.9）。
   - 三种表示的字节全部来自同一次 `guardedCGImage` 解码，**不重复解码**。
5. 失败语义：任一编码失败只 `logger.warning` 并继续写其余表示；三种都失败才返回 `false`（走既有「仅复制 / 失败」降级）。

### 2.2 增量 B：缩略图后台解码（P1，对标唯一明显弱项）

**对标依据**：OneClip 的图片流水线是它做得最好的一段——`Semaphore(3)` 并发上限、QoS 匹配防优先级倒置、活跃加载去重（`ClipboardManager.swift:3405-3468`）。我们的缩略图解码在 `draw(_:)` 内**主线程同步**进行（`ClipboardCardView+Resources.swift:66-72` ← `ClipboardCardView.swift:195`），首屏 8–12 张图连续解码会掉帧（ImageIO 降采样单张 320pt 仍需毫秒级 CPU）。

**设计**：

1. Core 新增纯状态机 `ClipboardThumbnailLoadGate`（无 Dispatch / 无 AppKit 依赖，可直接断言）：
   - `maxConcurrent`（默认 3）；`beginLoad(hash:) -> Bool`（未在途且并发未满则登记并返回 true，否则 false）；`finishLoad(hash:)`（清理在途并归还并发额度，重复调用幂等）；`activeCount` / `inFlightCount`；`reset()`。
2. App 层新增 `ClipboardThumbnailLoader`：`request(contentHash:imagePath:completion:)`
   - 缓存命中（`ClipboardCardView.thumbnailCache`）直接主线程回调，不占闸门；
   - 未命中且闸门通过 → 后台 `DispatchQueue(qos: .utility)` 解码（可用 `Task.detached`），完成后回主线程写缓存、调 completion、广播 `AppEvents.clipboardThumbnailReady`；
   - 闸门未通过（并发已满或在途）→ 不入队、不回调（由后续重绘/通知再次触发）。
3. 卡片取图改为「同步查缓存，未命中返回 nil 并异步请求」：首帧画占位符号，解码完成后由通知触发重绘。
   - `ClipboardCardView+Resources.thumbnail(for:)` 保持同步签名（返回 `NSImage?`），未命中时调 `ClipboardThumbnailLoader.request` 并返回 nil。
   - 重绘触发点：`ClipboardCardFlowView` 订阅 `AppEvents.clipboardThumbnailReady`，对该哈希命中的可见卡片置 `needsDisplay = true`（不重建视图、不改选中态）。
4. 预取：面板 `show()` 后对前 12 条图片条目请求缩略图（只走同一条 loader 路径，不新增解码实现）。
5. 停止语义：`ClipboardThumbnailLoader.cancelAll()` 在面板 `hide` 时调用（清在途登记；已入队任务允许跑完并忽略回调）。缓存与磁盘文件不删。
6. 内存护栏不变：缓存仍 64MB / 256 条双限，只缓存缩略图，原图永不进缓存。

### 2.3 增量 C：面板交互补齐（P2，识别度与防误删）

**对标依据**：OneClip 卡片右键菜单 5 项（复制 / 直接粘贴 / 收藏切换 / 搜索 / 删除，`ClipboardItemRowView.swift:67-106`），我们只有 1 项「贴到屏幕」（`ClipboardCardView.swift:97-107`）；OneClip 单条删除走二次确认（`ClipboardItemRowView.swift:122-129` + `ContentView.swift:499-516`），我们 `⌫` 直接删（`ClipboardPanelController.swift:275-280`）；OneClip 有分类计数与「共 N 项」（`ContentView.swift:302, 827-859`），我们无任何计数。

**设计**：

1. 卡片右键菜单补齐为 5 项（顺序固定）：`复制` / `粘贴为纯文本` / `收藏`（已收藏显示「取消收藏」）/ `贴到屏幕`（现有，位置调到第 4）/ `删除…`。
   - 菜单项全部走既有控制器动作，不新增第二套粘贴实现（`copyOnly` / `paste(item, asPlainText:)` / `togglePin` / `onRequestPin` / 删除）。
   - 收藏项显示勾选态（`state = .on`）；每项设置 `setAccessibilityLabel` 语义 ▸ 原生 NSMenu 已可读，标题即读名，无需额外实现。
2. 单条删除二次确认（**面板内两段确认，不弹独立窗口**，避免抢焦点）：
   - Core 新增纯状态机 `ClipboardDeleteConfirm`：`requestDelete(id:now:) -> Bool`（首次返回 true 表示「需确认」并记录待确认 id 与时间戳；同一 id 在窗口内再次请求返回 false 表示「可执行」并清理状态；不同 id 重新进入确认；超过 `window`（默认 2.0s）自动失效）。
   - 面板接法：首次 `⌫` 时在提示行显示「再按一次 ⌫ 删除该条」且不删；再次 `⌫` 命中同一选中条目则执行删除并清除提示。
   - `⌘⇧⌫` 清空保留同样语义：首次提示「再按一次 ⌘⇧⌫ 清空历史（收藏项保留）」。
   - 菜单「删除…」直接进入确认流程（等同首次 `⌫`）。
3. 底部件数统计：提示行左侧已有栈进度标签，在其左侧新增常驻计数文本「N 条 · 收藏 M」（N = 当前匹配项数，M = 匹配项中收藏数）。
   - 面板宽度不足时优先压缩提示行文案，计数不换行、不截断成半个；无障碍可读名「共 N 条，其中收藏 M 条」。
4. 无障碍：新增可交互项（菜单项、计数文本）都提供稳定可读名；删除确认提示进提示行（已有 `showHint` 通道，读屏可播报）。

## 3. 明确不做（登记 backlog）

| 项 | 理由 |
|---|---|
| 9 类内容类型（video/audio/document/code/archive/executable 独立 kind） | 需扩 `ClipboardItemKind` + 数据库迁移 + 卡片分派与过滤段扩容，属骨架级改动；现有 `ClipboardFileClassifier` 已在展示层给出七族分类 |
| 面板读库改后台/分页 | OneClip 反而无分页；我们主线程 `fetchAllClipboardItems` 是风险点但改动牵动搜索与方向键走满全量，单独排期 |
| HTML 富文本识别与 Paste as 子菜单 | 需 BLOB 存储与回写链，OneClip 也只抽纯文本 |
| 磁盘容量上限（500MB 类） | OneClip 侧 `cleanupLargeStorage` 无调用点，等于未实现；我们的条数+天数+单图上限已间接封顶 |
| 剪贴板新内容系统通知 / 预览尺寸 / 行号设置 / 首次引导页 / 悬停展开全文 | 价值低且与现有面板形态冲突 |
| 内存压力响应（清缩略图缓存） | 缓存 64MB/256 条双限已控住成本，优先级低于本批三项 |

## 4. 验收标准（派发前冻结）

**门禁**

| 组 | 命令 | 期望 |
|---|---|---|
| G-1 | `swift build --disable-sandbox --build-system native` | exit 0 |
| G-2 | `swift run --disable-sandbox --build-system native TestRunner` | 末行「🎉 所有测试通过！」 |
| G-3 | `swift build -c release --disable-sandbox --build-system native` | exit 0（防 DEBUG 块泄漏） |
| G-4 | `bash NetworkMonitor/Scripts/check-file-size.sh`（仓库根） | exit 0 |

**行为断言（TestRunner 新增用例）**

- A 组（图片格式）：白名单每类各 ≥1 样本命中且顺序正确（png 先于 tiff 先于 jpeg 先于 heic…）；大小写与前后空白归一；白名单外但 conforms(to: .image) 的类型被兜底采纳；纯文本类型列表返回空候选；空数组返回空候选；`tiffData` 与 `jpegData` 对同一 CGImage 编码成功且可被 `pixelSize` 读回原尺寸。
- B 组（缩略图闸门）：`maxConcurrent=3` 时第 4 个 `beginLoad` 返回 false；同一 hash 重复 `beginLoad` 返回 false；`finishLoad` 后额度归还且重复 finish 幂等；`reset` 清空在途与计数。
- C 组（删除确认）：首次请求返回「需确认」；2s 窗口内同 id 二次请求返回「可执行」；超窗后重新进入确认；不同 id 打断确认；`⌘⇧⌫` 清空与单条确认互不串味（各自独立状态）；清理后再次请求回到确认态。

**验收方式**：三项合并后由 lead 一次性跑四道门禁 + 人工核对菜单与控制台证据，不逐项拆多轮。

## 5. 工程化要求

- 纯函数优先：格式判定、闸门、确认状态机全部下沉 `NetworkMonitorCore`，AppKit 依赖只留 App 层。
- 可观测：解码失败、编码失败、确认超时只走 `LoggingService`（debug / warning），路径先过 `LogRedaction`。
- 容错：一次图片采集失败不得影响后续采集；异步回调一律主线程，禁止跨线程碰 `NSImage` / `Timer`。
- 单文件 ≤ 500 行 / 15360 字节；单函数 ≤ 70 行。
- 范围固定：数据库 schema、卡片尺寸、工具条与提示行高度、工具栏控件集合四处保持不变。

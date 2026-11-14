# 一览（NetworkMonitor / macMonitor）— macOS 菜单栏监控

## 项目简介
- **版本:** 1.24.0
- **语言:** Swift 工具链 6.4 / `swift-tools-version` 6.3（本机实测 6.4，CI 与发版跑 6.3；包清单暂不抬到 6.4）
- **类型:** 业务应用
- **技术栈:** Swift 6（严格并发）, Swift PM, AppKit, macOS 14+, arm64 + x86_64

→ [项目上下文（术语表）](CONTEXT.md)
→ [文档索引](docs/索引.md) ← 文档导航入口

> ⚠️ **操作前必读规范：**
>
> 以下规范定义了本项目必须遵守的开发规则。在执行相关操作之前，**必须先完整读取对应的规范**，确认操作符合要求，否则将导致合规检查失败。
>
> | 当你需要... | 必须先阅读 |
> |------------|-----------|
> | 修改/新增代码文件 | → **[编码规范 skill](.agents/skills/toolbar-coding-standards/SKILL.md)**（架构原则、命名、异常、版本号、代码查询、测试/提交纪律）；UI 类需求先用 `open-design` 原型 skill 出原型再实现 |
> | 创建/修改/删除文档 | → **[文档规范](docs/开发指南/文档规范.md)** |
> | 提交代码到 Git | → **[提交规范](docs/开发指南/提交规范.md)** |
> | 构建项目、运行测试或打包 .app | → **[构建与测试](docs/开发指南/构建与测试.md)** |
> | 排查已知编译错误或运行时问题 | → **[踩坑记录](docs/踩坑/)** |

## 功能模块
| 模块 | 说明 |
|------|------|
| 网络速度监控 | 实时网速监控（getifaddrs 差分）+ 进程网速（nettop）+ 每日流量追踪（TrafficTracker） |
| 计费额度查询 | 菜单面板「额度」tab 六个 provider：Ollama（/api/balance + /api/usage）、Open Design（编码计划 credits 窗口，只查额度——用量汇总接口已下线）、OpenCode Go（5 小时/每周/每月三窗口已用→剩余）、Claude / Codex / Cursor（会话·每日·每周·每月窗口）；**同一 provider 可配多个实例**：`BillingInstance`（默认实例 id = kindID，命名实例 id = `kindID::slug`）——凭据键 / 启用键 / 提醒状态键一律按实例 id 隔离，默认实例沿用旧键故升级零迁移，设置页可增删改；只展示「已启用且已配置」的实例，全部未配置走空态；BillingProvider 协议 + 注册表 + `BillingProviderInstance` 装饰器（provider 实现无需感知实例），新增 provider 仅需实现协议并注册；**三类额度通知**：阈值跌破（5…1%）/ 窗口重置（`BillingQuotaWindow.cycleID` 切周期）/ 余额回升（默认 +10pt、冷却 1 小时）→ 一一映射为「通知与音效」事件表的三行（`NotificationEvent.forBillingKind`）；开关分两层：通用页「额度偏低提醒」+ Provider 页「窗口重置通知 / 额度回升通知 / 回升阈值」决定**是否产生**，事件行决定**是否推送 + 声音 + 提醒方式**；锁屏 / 休眠暂停后台刷新，面板 Hero 右侧与页脚状态带显示暂停态 |
| 统一设置窗口 | 侧栏**九分类**（`SettingsSection` 顺序即展示顺序）：**通用 / 外观 / 额度 Provider / 剪贴板 / 截图与贴图 / 局域网互传 / 通知与音效 / 系统 / 关于**。通用（开机自启动 / 额度偏低提醒 / 数值单位 + 面板分页可见性与排序 + 菜单栏 **17 项指标**/密度/布局/单位/刷新周期，写偏好即发 AppEvents 热生效）、外观（主题 / 玻璃 / 渲染三档，见「外观与渲染」行）、额度 Provider（启用开关＝下线、行内凭据编辑、**实例增删改**、窗口重置与额度回升开关 + 回升阈值、凭据以 AES-GCM 密文本地存储）、剪贴板、截图与贴图（六个动作的快捷键录制 + JPEG 输出与质量，录完立即重新注册并落盘）、局域网互传、通知与音效（七行事件表，见「通知与音效」行）、系统、关于；**自定义排序**统一走 `SettingsOrderStore`（菜单栏指标 / 面板分页 / 工具条组三处，行尾上移下移 + 恢复默认，顺序按稳定 id 存、缺键回落 `defaultOrder` 故老用户外观不变）；旧三个独立设置窗口已下线；本轮处置 5 个死开关：`load` / `weekTraffic` 接上真实数据，`peakUp` / `peakDown` / `billingRemaining` 移除 |
| 截图与贴图 | ⌃⇧S 截图 → 覆盖层选区（窗口检测 / 放大镜 / 取色 / 历史选区）+ 标注（矩形/椭圆/直线/折线/箭头/画笔/马赛克/模糊/文字/**序号**，撤销重做）+ 动作工具（橡皮擦、**识别文字 OCR**：⌘O 或工具条二级面板触发，识别结果可复制或直接贴图）+ 复制 ⌘C / 另存 ⌘S / 快速保存 ⌘⇧S / 贴图 ⌘T，保存格式 PNG / **JPEG**（质量 0.3–1.0 默认 0.9，设置页可调）；一级工具条默认只摆 4 个高频工具 + 当前色 + 当前线宽 + 4 个动作按钮，其余工具与全部颜色/线宽带收进「更多」二级面板（贴工具条弹出，点面板外即收起）；**文字提示三档**（仅图标 40pt / 悬停气泡 40pt 默认 / 常驻标签 50pt，二级面板同档）+ **设置页可自定义**（位置 自动·下·上、四组显隐、组顺序、常驻工具、动作按钮显隐，写偏好即下次截图生效）；贴图窗支持拖动 / 滚轮缩放 / 透明度 / 旋转镜像 / 隐藏全部 |
| 剪贴板历史 | 全局快捷键面板、模糊搜索、Paste Stack 顺序粘贴、图片原图落盘与删后回收（删除 / 清空 / 超限清理 / 启动孤儿清扫四处）、采集按活跃度动态轮询 0.5·2·5s + pasteboard 通知提前唤醒、文件条目按七类扩展名分族（混合落 other）取图标与无障碍名 + 按族聚合摘要（同族合并、按条目边界截断，原文路径仍在正文）；图片按八类白名单（png/tiff/jpeg/heic/webp/gif/bmp + 类型系统兜底）采集与 PNG+TIFF 多表示回写、缩略图后台解码（并发 3 + 在途去重 + 失败冷却 30s、最多 3 次）、卡片 hover 与悬停 0.45s 全文浮层（不拦鼠标，超长内容由卡片流转发滚轮）、首启引导与「?」十二键位帮助浮层、右键菜单五项与删除二次确认、底部件数统计；卡片与面板展开/收起动效走 MotionKit（跟随「减弱动态效果」）、面板两级材质（.hudWindow 底 + .underWindowBackground 内衬，圆角 12 内缩 1pt）、音效默认关触觉默认开、设置页存储卡（占用 / 目录 / 清空） |
| 局域网文件互传 | UDP 发现 + HTTP 传输 + 扫码接收 + PIN 配对，支持断点续传 |
| Token 用量监控 | 菜单面板「Token」tab：DSH 会话事件流（zstd）增量索引，今日 / 近 7 天 / 近 30 天同源口径分 **4 屏**（概览 = Hero + 四族卡 + 缓存命中条 + 近 14 天 + 今日vs昨日；用量 = 主图 160pt（左侧刻度 + 网格）+ 天趋势 120pt；缓存 = 大环 + 四行拆分 + 走势（空缺断开）+ 对照 + 统计口径；排行 = 项目/模型维度段 + 占比条 + Top 8 两行式行），四屏 pane 高度恒 458pt（popover 520），每屏内容 + 页脚（状态带 / 缓存口径说明），区块归属由 TokenScreen 契约唯一确定；保留 3 个面板内覆盖式二级页（单桶 / 按小时三段 / 天趋势）；同会话多版本文件按内容键去重；分布行 / 占比条 / 图例悬停给 provider 全名（296pt 宽放不下 provider 前缀） |
| 面板视觉语言 | 六个 tab 共用一套版式骨架（页头 22pt → 内容 → 页脚状态带 20pt）与唯一令牌源 `PaneCardStyle`（颜色 / 玻璃强度 / 阴影**整体转发 `ThemeStyle`**：颜色取自语义角色 `ThemeRole`，换主题只改角色色值、调用点不动）：分区标题 11pt 粗体、行名 / 行值 10.5pt、行高 28pt、卡片圆角 9pt + 内边距 7/4、带底取 `ThemeRole.bandFill`（主题化前是固定 0xEEEFF2）；页头 `PaneHeaderRowView`、页脚 `PaneStateBandView`（共用 `PaneBandChrome` 外壳）只在 `MenuPanel/` 定义一次，页面不各画一遍。**几何值不随主题 / 档位变化**（卡 9pt、行高 28pt、面板 pane 458pt），变的是角色色值、材质与刷新节拍 |
| 外观与渲染 | 设置页「外观」分类 + 面板全局：**三套主题**（Apple 默认 / 冷调石墨 / 暖调米白，每套浅深各一，`ThemeCatalog`；系统页指标族色 CPU 蓝 / GPU 靛 / 内存青绿 / 压力橙 / 磁盘石墨仍归 `SystemPaletteTokens`，是数据语义不随主题漂移）；**玻璃拟态**（面板 macOS 26+ 走 `NSGlassEffectView(.regular)`，< 26 回落 `NSVisualEffectView(.hudWindow)`，底下垫主题基色层；卡片不套玻璃——一屏十几张卡各起一个合成层不划算；弹窗在 27+ 用 `effectIsInteractive` 随动）；**渲染三档**（标准 / 极致 / 省电 = tick 1.0 / 0.5 / 2.0s、中频 5 / 2 / 15s、动效与玻璃开关、图表降采样，`RenderTierProfile` 一档一喂、不做隐式推导），档位只改刷新节奏与精度、不改任何数据口径 |
| 通知与音效 | 设置页「通知与音效」分类：**七行事件表**（额度提醒 / 额度重置 / 额度回升 / 截图完成 / 剪贴板动作 / 传输完成 / 面板展开收起，`NotificationEvent`），每行四列 = 开关 + 提示音 + 提醒方式（横幅+声音 / 仅横幅 / 仅通知中心，`NotificationPresentation`）+ 触控板手感（关 / 轻 / 标准 / 有力，`NotificationHaptic`）；事件开关默认「提醒类开、操作反馈类关」，关掉即不推送也不出声；系统通知统一出口 `NotificationServicing`（App 层 `NotificationCenterService` 封装 UNUserNotificationCenter，Core 不依赖 UserNotifications）；提示音 = 系统音效库（只读 `/System/Library/Sounds`，不打包音频资源）+ 自定义音效（导入统一转 AIFF 16-bit PCM），发送前同步一份到 `~/Library/Sounds`（系统通知只认 bundle 与该目录、不认子目录）并按前缀有界清理孤儿；**能力边界**：横幅样式与是否出横幅由系统决定，应用只能组合横幅 / 声音 / 通知中心；触觉是 3 种系统图案 4 档，没有数值强度 |
| 系统监控 | 菜单面板「系统」tab：版2 紧凑首屏（四联 + CPU 蓝 / GPU 靛 / 内存 青绿 / 压力 橙 / 磁盘 石墨五张语义分族卡 + 20pt 四段状态带），五卡整卡可点进**面板内覆盖式二级详情页**（CPU 每核热力 / GPU 显存 / 内存四段与堆叠 / 磁盘读写与 IOPS / 压力 Top-10 且 CPU 榜·内存榜可切）；网络页另有一条 20pt Wi-Fi 链路条（RSSI/信道/速率/档位点，与状态带同源）。免 root 采样（host_processor_info / host_statistics64 / IOAccelerator / IOBlockStorageDriver / IOHID / IOReport / libproc / IOPS / CoreWLAN），不可得项降级为「—」 |
| 品牌与图标 | 对外显示名统一走 `AppIdentity.displayName`＝「一览」（菜单栏 / 关于页 / 通知 / 权限列表）；bundle id、`.app` 目录名、可执行名仍是 `NetworkMonitor`（换路径会让 TCC 权限与登录项重新授权，刻意不改）；图标为同心环，`Scripts/generate-icon.swift` 可脚本重生成 `AppIcon.icns` |
| 构建与发布 | 编译告警基线 **0 条**（唯一剩余告警是 `--build-system native` 被上游标记 deprecated 的环境限制，非代码问题）；CI 用 composite action + Swift 构建缓存跑构建 / 测试 / 门禁，发版矩阵 arm64 + x86_64；Release notes 由 `Scripts/generate-release-notes.sh` 按提交逐条明细生成（不再是一句「例行更新」） |

## 开发指南
→ [编码规范 skill](.agents/skills/toolbar-coding-standards/SKILL.md)（规范权威来源，**规范更新一律写入 skill，不另建独立规范文档**）
→ UI/原型类工作用 `open-design` 原型 skill 产出原型，定稿后再实现
→ [构建与测试](docs/开发指南/构建与测试.md)
→ [提交规范](docs/开发指南/提交规范.md)
→ [文档规范](docs/开发指南/文档规范.md)

## 踩坑记录
→ [踩坑记录](docs/踩坑/)
# 局域网文件互传 Mac 端实现记录

> 状态：已交付（M1–M4，待 Android 真机联调）｜日期：2026-10-18｜负责：mac-transfer-dev
> 唯一协议真相：[局域网文件互传-设计规格](局域网文件互传-设计规格.md)（含 2026-10-18 的 `sessionId` / `pairingKey` 补充）

## 1. 任务契约

- **范围**：`toolbar` 仓库的 `NetworkMonitor` 菜单栏 App，新增「传送」页；Android 端在 `android-monitor` 仓库由另一 agent 并行实现，本仓库不触碰。
- **分层**：`NetworkMonitorCore/Transfer/{Discovery,Protocol,Transport,Service}` + `NetworkMonitor/Transfer/{面板,控制器,通知,配对,动效}`。
- **硬约束**：零第三方依赖（`Network.framework` + `URLSession` + `CryptoKit` + BSD socket）；单文件 ≤500 行 / 15 KiB；注释中文；禁止 `print`（走 `LoggingService`）；协议字段不增删；发现层 53318、传输 53319（顺延至 53328）。
- **验收**：`swift build --build-system native` 通过；`TestRunner` 全绿且覆盖发现消息编解码、状态机非法迁移、文件名去重、offset 校验；`build-app.sh` 产出 .app；`curl` 校验 `/info` 与 `/offer` 结构。

## 2. 已确认事实（本轮踩实，续接先看这里）

1. **本机无 Xcode**：构建、测试、打包一律加 `--build-system native`，裸 `swift run --disable-sandbox TestRunner` 会 `SessionFailedError`（与 `docs/踩坑/构建/swift-build-会话初始化失败.md` 一致）。
2. **配对 key 通道**：按更新后的设计文档走 `POST /offer` 响应的 `data.pairingKey`；`X-Pair-Key` 响应头仅作旧实现兼容，发送端优先读 `data.pairingKey`。
3. **会话复用**：重提 PIN 时发送端带 `sessionId`；接收端先按 `sessionId` 查找待确认会话，未命中再按 `senderDeviceId + files 的 sha256 集合` 复用（重命名不影响匹配）。
4. **中断上传与重试语义（2026-10-18 修订）**：body 提前结束时返回 `4003`、**保留 `.part`**、会话保持传输态（不转 failed）。发送端重试前带 `sessionId` 重新 `POST /offer`，接收端对**已批准 / 传输中**会话返回 `approved + accepted[].offset`（服务端已收字节），客户端从该偏移续传——**不能用 `offset=0` 覆盖**，两端接收端都对 `offset` 严格校验（Mac `validateOffset`、Android `TransferEngine`）。跨会话续传同样由 `accepted[].offset`（`.part` 大小）承载。
5. **未知路由**：HTTP 404 + 业务码 `4000`（错误码表无专用 404 码），不做码表扩展。
6. **收件目录**：`~/Downloads/局域网互传/`；文件名在 `offer` 阶段一次去重定名，落盘时若目标被占则重新去重。
7. **超时**：确认超时 30s（`offerStatus` 到点返回 `expired` 并转 failed）；单文件上传失败重试 3 次（1s/2s/4s）。
8. **动效**：状态 0.12s、展开 0.34s、弹层 0.22s / 关闭 0.15s、逐项 24ms，跟随系统「减弱动态效果」直接落终态。
9. **音效**：`NSSound(named:)` 系统音，默认只开完成（接收 `Glass` / 发送 `Tink`），失败 `Basso`、新设备 `Pop`、配对码 `Morse` 默认关；同事件 500ms 去重。

## 3. 改动清单

### Core 新增（`Sources/NetworkMonitorCore/Transfer/`）

| 文件 | 行数 | 职责 |
|---|---|---|
| `Domain/TransferModels.swift` | 186 | `RemoteDevice` / `TransferFile` / `TransferSession` / `TransferState` / 存活判定 |
| `Domain/TransferError.swift` | 83 | 域异常 + 协议错误码映射（4001–4007） |
| `Discovery/DiscoveryMessage.swift` | ~240 | 三种发现消息编解码、版本兼容（v=1）、协议常量 |
| `Discovery/DeviceRegistry.swift` | ~190 | 设备表、在线优先排序、15s 离线 / 60s 移除 |
| `Discovery/UdpDiscoveryService.swift` | 326 | 组播 + 广播 + `/24` 单播兜底、5s 心跳、`discover` 单播应答（2s 冷却） |
| `Discovery/SubnetScan.swift` | 51 | `/24` 地址生成与 128 并发切批（纯函数） |
| `Protocol/TransferProtocol.swift` | ~380 | 路由常量、`{code,message,data}` 信封、`/offer` 等模型、HTTP 抽象、Range 解析 |
| `Protocol/TransferRouter.swift` | ~137 | 五条路由分发，配对 key 响应头下发 |
| `Transport/HttpRequestParser.swift` | 135 | 请求行 / 头部 / 查询参数 / `Content-Length` / Range |
| `Transport/HttpResponseWriter.swift` | 53 | 响应编码（每连接一请求，`Connection: close`） |
| `Transport/HttpServer.swift` | 261 | `NWListener` 生命周期、端口顺延、每连接一请求 |
| `Transport/HttpBodyReader.swift` | 148 | 拉模式流式请求体（64 KiB 背压） |
| `Transport/FileStreamWriter.swift` | ~170 | `.part` 流式落盘 + 续传摘要 + 磁盘预检 |
| `Transport/FileStreamReader.swift` | 85 | 分块读取、sha256、MIME 推断 |
| `Service/TransferSessionMachine.swift` | 85 | 状态机穷举表 + 会话推进器 |
| `Service/TransferService.swift` | 381 | 服务主体：生命周期、路由实现、会话表、观察者 |
| `Service/TransferService+Offer.swift` | 138 | 接收端 offer 分支、PIN 配对、会话构造/复用 |
| `Service/TransferService+Receive.swift` | ~210 | 流式接收、offset/token 校验、sha256 校验、改名、状态推进 |
| `Service/TransferService+Send.swift` | 318 | 发送端清单、offer、PIN 提交、逐文件上传与重试、进度 |
| `Service/TransferService+Resume.swift` | 58 | 断网重试前向接收端确认已收字节（`refreshResumeOffset(s)`） |
| `Service/TransferHTTPClient.swift` | 239 | `URLSession` 五路由封装、上传进度、续传切片 |
| `Service/PairingStore.swift` | 114 | 按 `deviceId` 持久化 `pairingKey`、PIN 生成与校验 |
| `Service/FileNameResolver.swift` | 88 | 文件名清洗与 ` (1)`/` (2)` 去重、offset 校验（`UploadPlanner`） |

### App 新增（`Sources/NetworkMonitor/Transfer/`）

| 文件 | 行数 | 职责 |
|---|---|---|
| `TransferPaneView.swift` | 228 | 设备列表、拖拽区、任务进度、键盘可达 |
| `TransferRows.swift` | 188 | 设备行与任务行（进度插值、完成对勾、失败抖动） |
| `TransferController.swift` | ~300 | 面板与 Service 接线、PIN 弹窗调度、通知触发 |
| `TransferPairingSheet.swift` | ~230 | PIN 展示 / 输入弹窗（独立 NSPanel） |
| `TransferNotification.swift` | ~145 | 系统通知 + 系统音效 + 去重 |
| `TransferMotion.swift` | ~175 | 动效常量与动画实现、减弱动效兜底 |

### 既有文件改动

- `MenuPanel/MenuTabBarView.swift`：`MenuPanelTab` 加 `.transfer`（「传送」/ `paperplane`）。
- `MenuPanel/MenuPanelView.swift`：接入 `transferPane`，四页互斥显示与键盘切换。
- `MenuPanel/MenuPanelController.swift`：构造注入 `TransferController` 并 `attach`。
- `MenuBarManager.swift`：透传 `transferController`。
- `AppCoordinator.swift`：`makeTransferController()` 组合根装配（设备表 + 身份 + 收件目录 + 启动）。
- `MenuPanelComponents.swift`：`MenuPanelRow` 按下 0.96 缩放。
- `Debug/MenuPanelSnapshot.swift`：快照枚举补 `.transfer`。
- `Scripts/build-app.sh`：Info.plist 增加 `NSLocalNetworkUsageDescription`。
- `Sources/TestRunner/main.swift` + `TransferTests.swift`：新增互传测试组（约 200 行断言）。

## 4. 验收证据（2026-10-18）

**1）构建**

```bash
cd NetworkMonitor && swift build --build-system native
# Build complete!  EXIT=0（无新增 error/warning）
```

**2）测试**

```bash
cd NetworkMonitor && swift run --disable-sandbox --build-system native TestRunner
# … Testing TransferSessionMachine 迁移...（64 种状态对穷举，48 种非法）
# … Testing PairingStore 配对记忆...
# … Testing offer 清单签名...
# … Testing 错误码与响应信封...
# 🎉 所有测试通过！  EXIT=0
```

覆盖：发现消息编解码（10 个字段逐条）/ 版本兼容 / 离线判定边界（14.9/15/59.9/60s）/ `/24` 地址生成 / 设备表 / HTTP 解析与响应编码 / 文件名去重 / offset 校验（含重试偏移优先取服务端值）/ 流式落盘 + 续传摘要 / 状态机非法迁移 / 配对记忆 / 错误码 / 信封结构。

**断网重试续传（集成，真实 HTTP + 落盘）**：

```bash
# 输出节选
🧪 Testing 断网重试续传（集成，真实 HTTP + 落盘）...
✅ Optional(0)  — 首次 offer 续传起点为 0
✅ 4003  — 不完整上传返回 4003
✅ 5  — 服务端保留 5 字节 .part
✅ 5  — 重试前确认服务端已收 5 字节
✅ true  — 第二次请求的 offset > 0（5）
✅ 11  — 续传后接收完整
✅ b94d27b9…cde9  — 服务端摘要与源文件一致
✅ b94d27b9…cde9  — 落盘文件 sha256 与源文件一致
✅ false  — 完成后 .part 已清理
# EXIT=0，全量 536 条断言通过
```

**3）打包**

```bash
cd NetworkMonitor && ./Scripts/build-app.sh
# 🎉 部署完成！  .app 位置：/Applications/NetworkMonitor.app（3.6M）  EXIT=0
```

**4）接口（对运行中的 .app 实测）**

```bash
curl -s http://127.0.0.1:53319/api/v1/info
# {"code":0,"data":{"alias":"bsfeng 的 Mac","appVersion":"1.0.0","caps":["send","recv"],
#  "deviceId":"mac-0d51","deviceType":"mac","port":53319,"proto":"http"},"message":"ok"}

curl -s -X POST http://127.0.0.1:53319/api/v1/offer -H 'Content-Type: application/json' -d '{…}'
# {"code":0,"data":{"accepted":[],"sessionId":"3d1d…","state":"pending","token":"bd3b…"},"message":"ok"}

# 带 PIN + sessionId 重提（PIN 从 App 日志读出）
# {"code":0,"data":{"accepted":[{"fileId":"f1","offset":0}],"pairingKey":"9e10…（64 hex）",
#  "sessionId":"7d95…","state":"approved","token":"cb04…"},"message":"ok"}

# PUT /upload（16 字节文件）
# {"code":0,"data":{"fileId":"f1","received":11,"sha256":"ff2e…"}}  → 落盘 ~/Downloads/局域网互传/fast.txt 校验一致

# 已配对带 X-Pair-Key 重提：state=approved 且不返回 pairingKey
# 错误 token → 4001；错误 offset → 4003（期望 0，收到 5）；未知路由 → HTTP 404 + code 4000
# 中断上传（只发 5/11 字节）→ 4003 且 .part 保留 5 字节；offset=5 续传 → 成功且 sha256 一致
# POST /cancel → data {} 且 .part 被删除
```

## 5. 已知限制与未做项

- **未与 Android 真机联调**：本机无 Android 设备，协议层仅用 `curl` 自测；Android 侧落地后需复核 `pairingKey` 持久化、`sessionId` 复用与 offset 续传。
- **组播本地网络权限**：首启弹窗被拒时组播不可用，仅剩广播与 `/24` 单播兜底；面板在服务启动失败时给中文诊断，不静默空列表。
- **PIN 无错误次数限制**：错误 PIN 只返回 4000 并保留会话，未做爆破限制（局域网场景可接受，后续可加）。
- **通知授权**：未签名 `.app` 上 `UNUserNotificationCenter` 授权可能失败，已降级为日志，不影响音效。
- **动效未逐帧取证**：按系统时长与曲线实现并遵循「减弱动态效果」，未做像素级截图比对。

## 6. 修订记录

| 日期 | 问题 | 修复 |
|---|---|---|
| 2026-10-18 | lead 验收发现：发送端重试写死 `offset = 0`，接收端严格校验会连续 4003 → 任务失败，违反协议 §6 | 重试前带 `sessionId` 重新 `POST /offer` 取 `accepted[].offset` 续传（`TransferService+Resume.swift`）；接收端允许已批准 / 传输中会话按 `sessionId` 复用并返回续传偏移；补纯函数 `UploadPlanner.retryOffset` 与集成测试（中断→4003→确认 5 字节→续传→sha256 一致） |

## 7. 后续建议

1. Android 联调优先验证：`POST /offer` 三状态、`data.pairingKey`、`sessionId` 复用、`/upload` offset 续传、`/cancel` 清理。
2. 设置页开放音效开关（当前默认完成音开、其余关）与配对管理入口（`PairingStore.remove` 已就绪）。
3. 传输历史持久化（当前会话表在内存，App 退出即清空）。

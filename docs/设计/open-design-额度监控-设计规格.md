# Open Design 额度监控设计规格

> **何时阅读：** 维护额度页（`BillingPane`）或新增第三方计费 provider 前。

## 背景与目标

额度页原有 provider 只有 Ollama。本次新增 **Open Design**（`open-design.ai`）额度监控，复用既有 `BillingProvider` 注册表与额度页 UI，不改面板结构。

目标：在菜单面板「额度」tab 里看到 Open Design 的 5 小时 / 每周编码计划额度与当前范围用量。

## 接口事实（2026-10 实测）

宿主 `https://amr-api.open-design.ai`，全部需要浏览器登录态 Cookie，**没有 API Key 体系**。

| 用途 | 请求 | 说明 |
|------|------|------|
| 发现工作区 | `GET /api/v1/workspaces` | `items[0].workspaceId`，个人 workspace 通常只有一个 |
| 额度窗口 | `GET /api/v1/workspaces/{id}/billing/coding-plan-usage` | 返回 `windows[]`：`usedCredits` / `limitCredits` / `remainingCredits` / `durationSeconds` / `resetsAt` |
| 用量汇总 | `GET /api/v1/workspaces/{id}/billing/usage?from&to&limit` | 顶层 `summary`（token 全范围汇总）、`totalCount`（请求数）、`filterOptions.runtimes`（模型列表）；`entries` 为明细分页，一页上限 100 |

关键结论：

- **鉴权只认 Cookie**：`Cookie: __Secure-better-auth.session_token=<token>`；`Authorization: Bearer` 一律 401。
- **`summary` 与 `totalCount` 是全范围聚合**（与 `limit` 无关），因此用量汇总**不需要翻页**。实测 30 天区间 `totalCount` 可达 1.6 万条，靠 cursor 翻页不可接受。
- **没有服务端分桶接口**（`granularity` / `group_by` / `aggregate` 等参数均被忽略，仍返回明细）。按小时/天画柱状图需要每个桶一次请求，24 小时就是 25 次，不可取。
- **按模型拆分**：`filterOptions.runtimes` 给出模型名，逐个 `?runtime=<name>` 查询读 `summary` 即可，模型数通常 1–2 个。
- **花费不可用**：`chargeCredits` 全为 0（编码计划按 credits 配额计量），`listChargedUsd` 只是标价。用量不做金额换算，避免展示虚高花费。

## 设计决定

### 1. 凭据只有一段：session token

用户从浏览器复制 `__Secure-better-auth.session_token` 的值粘贴进额度页凭据框，provider 内部：

1. 容错解析（允许整条 Cookie 串、`name=value`、纯值三种形态）；
2. 先 `GET /workspaces` 拿 `workspaceId`（内存缓存，失败不缓存）；
3. 再查额度与用量。

不引入「workspaceId + token」双输入框：个人账号只有一个 workspace，多输入框只增加配置成本。

### 2. 额度映射到百分比限额

`coding-plan-usage` 没有金额概念，窗口即「已用 / 限额 credits」。映射为 `BillingPercentLimit`：

| 字段 | 取值 |
|------|------|
| `id` | `policyId`（稳定，避免窗口顺序变化导致提醒状态错位） |
| `title` | `durationSeconds` 命名：18000 → `5 小时`，604800 → `每周`，其余按小时/天推导 |
| `remainingFraction` | `remainingCredits / limitCredits`（钳制 0…1） |
| `usedAmount` / `limitAmount` / `unitLabel` | 新增结构化字段，`unitLabel = "credits"`，UI 显示 `已用 76,412 / 150,000` |
| `resetsAt` | 窗口 `resetsAt` |

`BillingBalance.included` 与 `purchasedUSD` 均为 nil → UI 走既有「遗留计划」分支（标题「剩余额度」、隐藏金额 hero、只渲染限额行），无需新分支。

阈值提醒（5%/4%/3%/2%/1%）沿用 `BillingAlertEvaluator`：每个窗口按 `policyId` 独立记录，周期按 `resetsAt` 判定。窗口切换（5 小时重置）后 `resetsAt` 变化即视为新周期，可再次提醒。

### 3. 用量：汇总 + 按模型，不画柱状图

协议新增 `supportsTimeSeries`（默认 `true`，Open Design 为 `false`）。为 `false` 时：

- 指标两行照常显示（请求数 / 输入·缓存·输出 token）；
- **柱状图与时间轴整块隐藏**，不用「明细首 100 条」拼一张严重低估的图；
- 按模型 Top3 照常显示，模型行的金额列在 `usageUSD == nil` 时显示该模型 token 合计。

请求数预算：一次范围刷新 = 1 次汇总 + N 次模型查询（N = `filterOptions.runtimes` 数量，上限 5）。`BillingMonitor` 的 60 秒节流对两家 provider 共用。

### 4. 文案与错误

- `credentialHint = "Open Design session token"`
- 协议新增 `credentialPageURL: URL?`（默认 nil），配置态链接文案与跳转目标按 provider 生成；Open Design → `https://open-design.ai/`
- 401 → `BillingError.unauthorized`，用户文案统一为「凭据无效或已过期，请重新填写」（对 API Key 与 Cookie 都成立）
- 403 `workspace_member_required` → `.forbidden("无权访问该工作区，请确认账号仍在成员列表中")`

## 落点

| 文件 | 变更 |
|------|------|
| `Sources/NetworkMonitorCore/Billing/BillingModels.swift` | `BillingPercentLimit` 增 `usedAmount` / `limitAmount` / `unitLabel` 与 `usageText` |
| `Sources/NetworkMonitorCore/Billing/BillingProvider.swift` | 协议增 `supportsTimeSeries` / `credentialPageURL`（带默认实现）；`unauthorized` 文案通用化 |
| `Sources/NetworkMonitorCore/Billing/OpenDesignBillingProvider.swift` | 新增 provider（发现 / 额度 / 用量） |
| `Sources/NetworkMonitorCore/Billing/BillingFormat.swift` | 新增 credits 千分位格式化 |
| `Sources/NetworkMonitor/MenuPanel/BillingPaneBalance.swift` | 限额行显示 `已用 X / Y` |
| `Sources/NetworkMonitor/MenuPanel/BillingPaneSections.swift` | 柱状图按 `supportsTimeSeries` 隐藏；模型行金额缺省时显示 token |
| `Sources/NetworkMonitor/MenuPanel/BillingPaneView.swift`、`BillingPaneStates.swift` | 凭据链接与说明文案按 provider 生成 |
| `Sources/NetworkMonitor/AppCoordinator.swift` | 注册 `OpenDesignBillingProvider` |
| `Sources/TestRunner/BillingTests.swift` | 新增 Open Design 解码 / 聚合 / 错误映射测试 |

## 验收

- `swift build --disable-sandbox --build-system native` 通过；
- `swift run --disable-sandbox --build-system native TestRunner` 输出「🎉 所有测试通过！」；
- 快照模式产出 open-design 态截图（浅色 / 深色），限额行带 `已用 / 限额`、无柱状图、模型行显示 token；
- 真实 token 手工验证：额度两窗口与网页一致，24 小时用量 token 与 `/billing/usage` 的 `summary` 一致。

## 已知限制

- 只支持个人 workspace 的第一个（`items[0]`），团队 workspace 需后续显式选择；
- session token 随浏览器登出失效，失效后需重新复制（错误条会提示）；
- provider 不缓存用量结果，切换范围会重新请求；模型数多时请求数线性增长（上限 5 个模型）。

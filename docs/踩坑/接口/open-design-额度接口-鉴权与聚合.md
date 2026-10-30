# Open Design 额度接口只认 Cookie 且用量需读顶层聚合

> **何时阅读：** 调试 Open Design 计费 provider，或新增类似「只有浏览器登录态、无 API Key」的 provider 时。

## 现象

1. 用 `Authorization: Bearer <token>` 请求 `coding-plan-usage` 一律 401，但同一 token 放 `Cookie: __Secure-better-auth.session_token=<token>` 里就 200。
2. `GET /billing/usage` 想按时间范围取明细时，`granularity` / `group_by` / `aggregate` / `bucket` 等参数全部被忽略，仍返回明细数组。
3. 30 天区间 `totalCount` 达 1.6 万条，`limit` 上限 100，翻页要 160+ 次请求；且 `cursor` 必须 URL 编码，否则报 `invalid_workspace_usage_cursor`。
4. 用量面板切到「7 天 / 30 天」报 400 `invalid_workspace_usage_time_range`，24 小时档正常。

## 原因

- Open Design（`amr-api.open-design.ai`）的计费接口挂在 Better Auth 会话上，不是 API Key 体系，因此只接受 Cookie 头。
- 用量接口没有服务端分桶实现，`entries` 是原始明细；但顶层 `summary`（token 四项）与 `totalCount`（请求数）**已经是全范围聚合**，与 `limit` 无关。
- `/billing/usage` 的 `from` / `to` 有硬窗口限制（2026-10 实测）：只接受**最近 7 天**——跨度超过 7 天、或起点早于 7 天前，一律 400 `invalid_workspace_usage_time_range`；终点晚于当前时刻同样 400（`now + 60s` 就报错，`now + 1s` 容差放行）。
- 自然日口径算出的终点是「明天 0 点」，正好踩中「终点在未来」这条规则，因此 7 天 / 30 天档必失败；24 小时档终点是已过去的整点，所以正常。

## 做法

- 凭据只收 session token，`makeRequest` 里固定写 `Cookie` 头；`normalizedToken` 容忍三种粘贴形态：纯 token、`name=value`、整条 Cookie 串（含 `Cookie:` 前缀）。
- 用量汇总**只读顶层 `summary` / `totalCount` / `filterOptions.runtimes`**，`limit` 传 `1` 即可，绝不翻页。
- 按模型明细：对 `filterOptions.runtimes` 逐个发 `?runtime=<name>` 再读 `summary`（模型数上限 5）。
- provider 声明 `supportsTimeSeries = false`，UI 隐藏柱状图——用「明细首 100 条」拼图会严重低估用量。
- 查询窗口终点一律夹到 `now`、起点不早于 7 天前（`BillingRange.queryWindow`）；24 小时档用 `Calendar.dateInterval(of: .hour, for:)` 取小时起点做锚点，不要用 `date(bySetting: .minute, value: 0, of:)`——后者取的是**严格之后**的匹配，端点会落到未来整点。
- 30 天窗口服务端无数据可取，provider 声明 `supportedUsageRanges = [.last24Hours, .last7Days]`，UI 只渲染这两档；状态管理器切范围时也按该能力位拦截，避免发出必然 400 的请求。

## 反例

- 按 `granularity=day` 循环逐桶请求：24 小时就要 25 次请求，触发限流（实测无头请求下会间歇性超时）。
- 用 `listChargedUsd` 当花费展示：编码计划按 credits 配额计量，`chargeCredits` 恒为 0，该字段只是标价，展示会虚高百倍。
- 直接把自然日窗口（`start = 6 天前 0 点`、`end = 明天 0 点`）塞进 `from` / `to`：终点在未来，必然 400；把 30 天窗口原样发出同样 400，分页或改 `granularity` 都无效。

# Open Design 额度接口只认 Cookie 且用量需读顶层聚合

> **何时阅读：** 调试 Open Design 计费 provider，或新增类似「只有浏览器登录态、无 API Key」的 provider 时。

## 现象

1. 用 `Authorization: Bearer <token>` 请求 `coding-plan-usage` 一律 401，但同一 token 放 `Cookie: __Secure-better-auth.session_token=<token>` 里就 200。
2. `GET /billing/usage` 想按时间范围取明细时，`granularity` / `group_by` / `aggregate` / `bucket` 等参数全部被忽略，仍返回明细数组。
3. 30 天区间 `totalCount` 达 1.6 万条，`limit` 上限 100，翻页要 160+ 次请求；且 `cursor` 必须 URL 编码，否则报 `invalid_workspace_usage_cursor`。

## 原因

- Open Design（`amr-api.open-design.ai`）的计费接口挂在 Better Auth 会话上，不是 API Key 体系，因此只接受 Cookie 头。
- 用量接口没有服务端分桶实现，`entries` 是原始明细；但顶层 `summary`（token 四项）与 `totalCount`（请求数）**已经是全范围聚合**，与 `limit` 无关。

## 做法

- 凭据只收 session token，`makeRequest` 里固定写 `Cookie` 头；`normalizedToken` 容忍三种粘贴形态：纯 token、`name=value`、整条 Cookie 串（含 `Cookie:` 前缀）。
- 用量汇总**只读顶层 `summary` / `totalCount` / `filterOptions.runtimes`**，`limit` 传 `1` 即可，绝不翻页。
- 按模型明细：对 `filterOptions.runtimes` 逐个发 `?runtime=<name>` 再读 `summary`（模型数上限 5）。
- provider 声明 `supportsTimeSeries = false`，UI 隐藏柱状图——用「明细首 100 条」拼图会严重低估用量。

## 反例

- 按 `granularity=day` 循环逐桶请求：24 小时就要 25 次请求，触发限流（实测无头请求下会间歇性超时）。
- 用 `listChargedUsd` 当花费展示：编码计划按 credits 配额计量，`chargeCredits` 恒为 0，该字段只是标价，展示会虚高百倍。

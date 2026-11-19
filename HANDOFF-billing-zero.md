# 交接：额度「静默 0」→ 显式不可得（分支 fix/billing-silent-zero）

## 任务契约
把「分母非正 / 字段缺失 / 状态未知时静默返回 0」改成显式「不可得」，并让「成功 + 数值」日志在生产级别可见。
不重构整个额度模块；不加 target / 依赖；单文件 ≤500 行；未 commit。

## 已确认事实（不需要重查）
- 生产 logger `OSLogLogger.minLevel = .info`（NetworkMonitorCore/Infrastructure/Logging/Loggers.swift:27），
  旧「刷新成功」是 `logger.debug`（BillingMonitor+Apply.swift:55）→ 现场永远看不到成功线。
- 失败路径不写数值，界面本来就是「—」+ 错误条；「有窗口 + 0% + 无错误条」只能来自映射层静默 0。

## 改动清单
| 文件 | 改动 |
|---|---|
| Core/Billing/BillingProviderSupport.swift | `remainingFraction(used:limit:)` / `(usedPercent:)` 返回 `Double?`，分母非正或非有限 → nil |
| Core/Billing/BillingModels.swift | `BillingPercentLimit.remainingFraction` / `BillingIncludedBalance.remainingFraction` 改可选；新增 `isUnavailable` / `unavailableNote` |
| Core/Billing/OpenDesignBillingDecoding.swift | limitCredits 缺失/为 0 → nil；新增纯函数 `remainingFraction(remaining:limit:)` |
| Core/Billing/OpenDesignBillingDTOs.swift | 三个 credits 字段改可选（缺上限只坏一个窗口，不让整份响应失败） |
| Core/Billing/BillingFormat.swift | `formatPercent(_:)` / `formatPercentCompact(_:)` 可选重载 + `billingUnavailablePlaceholder = "—"`；`BillingLogLine` 三态日志纯函数 |
| Core/Billing/BillingAlerts.swift | 不可得窗口不参与提醒评估（否则被当「已用尽」误报） |
| Core/Infrastructure/Logging/Loggers.swift | ConsoleLogger：info→stdout、warning/error→stderr、debug 丢弃；info 有字符预算（默认 40 万，可 0 关），锁保护 |
| NetworkMonitor/Billing/BillingMonitor+Apply.swift | 成功日志提到 info（`BillingLogLine.refreshLines`），不可得项单独一条 |
| NetworkMonitor/MenuPanel/DrawnBillingCell.swift | 不可得 → 数值位「—」、不画填充条、角标位写「数据不可得」 |
| NetworkMonitor/MenuPanel/BillingProviderBlockView.swift、BillingPaneView.swift | 不可得窗口不进「最低剩余」/ Hero 比较 |
| NetworkMonitorUI/BillingCellLayout.swift | Level 增 `.unavailable` |
| TestRunner/BillingUnavailableValueTests.swift（新） | 换算 / 模型 / 展示 / provider / 日志口径 5 组回归 |
| TestRunner/{BillingTests,OpenDesignBillingTests,BillingProviderDecodingTests,TestSuites+Billing} | 既有断言改到新口径 + 登记新套件 |

## 判断结论（两处保留）
- **OpencodeGo rate-limited → 0**：保留。`status == "rate-limited"` 是服务端显式状态，旧字段形态退化时 `percent == 100` 也构成显式 0%；配「已限流」角标，语义正确。
- **Codex `limit_reached` → 0**：保留。`limit_reached` = 服务端明确说「已用尽」；样本里同时 `used_percent: 100`，属双证。

## 验收（全部已跑过）
```
swift build --disable-sandbox --build-system native      → exit 0
swift run ... TestRunner                                 → 🎉 所有测试通过！
check-file-size.sh / check-file-families.sh / check-arch-guards.sh → exit 0
```

## 遗留 / 未做
- 未 commit、未打包、未在真机 .app 上验证（本机运行的是 1.29.0 旧构建）。
- 三态日志在真机的 `log show` 实跑未做（需新构建部署后刷新一次额度页）。

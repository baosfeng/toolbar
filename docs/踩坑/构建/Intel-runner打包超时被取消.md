# Intel runner 打包超时被取消（x86_64 runner 排队 45 分钟）

> **何时阅读：** 发版 Release 里 `Package x86_64` 挂在 in_progress 很久、最后变成
> `cancelled`，而 arm64 早就 success；或想判断「这次发版到底是代码坏了还是机器慢」。

## 现象

`v1.32.0` 第三次 Release（run `45833709759`，tag 指向 `704446c`）：

| job | 结论 | 起始 → 结束 | 耗时 |
|-----|------|-------------|------|
| Package arm64 | success | 13:54:36 → 13:58:03 | 3 分 27 秒 |
| Package x86_64 | **cancelled** | 13:54:39 → **14:39:39** | 45 分 00 秒 |
| Universal + per-arch dmgs | skipped | 14:39:40 | — |
| Publish release | skipped | 14:39:40 | — |

同一个 job 在重跑后 **8 分钟**就跑完并 success，构建步骤本身只用了 452 秒 ——
说明**不是代码或脚本卡死**，而是这一次 Intel runner 上「构建 + 上传」被拖到了 job 超时。

## 根因判据（怎么区分「代码坏了」与「机器慢」）

1. **看 job 的步骤表**：`cancelled` 的 x86_64 job 里，前四步（Set up job / Checkout /
   Setup build / Cache SwiftPM）都 success，`Build, sign and package` 停在 `None`（没结论）。
   这样的形状是「跑到一半被掐」，不是「某一步报错退出」——报错退出会给该步 `failure`。
2. **看 arm64**：同一份提交、同一个 `build-app.sh`，arm64 是 success 且用证书签了名
   （`Authority=NetworkMonitor Local Signing`）。代码路径已被另一半矩阵验证通过。
3. **看总时长**：`timeout-minutes: 40` 是 `release.yml` package job 的上限，
   45 分钟是 GitHub 在超时后把 job 判 `cancelled` 的口径。
4. **取不到日志是正常现象**：`cancelled` 的 job 往往没有上传日志归档，`ghops actions logs`
   会报 `BlobNotFound`。这时不要据此判断「日志被删了」或「权限不对」——
   用 `--jobs` 拿 job 清单 + 公开 API `/actions/runs/<id>/jobs` 的 `steps` 时间戳取证即可。

## 处置

失败的是「某几个 job」而不是整条 workflow 时，**重跑失败 job** 即可，不必重新打 tag：

```bash
TOKEN=$(cat ~/.dsh/secrets/github-token)
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/repos/baosfeng/toolbar/actions/runs/<run-id>/rerun-failed-jobs
```

- `rerun-failed-jobs` 只重跑 `cancelled` / `failure` 的 job，已 success 的 job 不重跑
  （arm64 的产物继续被 `universal` job 使用，不会重新构建一遍）；
- 重跑会产生新的 `run_attempt`，**run id 不变**，所以 `release.sh` 那套「按 tag 找 run」
  的轮询逻辑照常能跟到底；
- 重跑后 `universal` / `publish` 两个被 skip 的 job 会正常跑起来（本例实测：重跑后
  x86_64 8 分钟 success，随后 universal 30 秒、publish 数秒完成，五个资产齐全）。

## 教训

发布红在 package 阶段时，**先看另一半矩阵**：一半绿一半 `cancelled`，优先判为 runner 侧
（排队 / 磁盘 I/O / 网络上传），而不是先改代码。
不要把 `cancelled` 当成「代码失败」：`cancelled` 与 `failure` 的处置不同，
前者重跑即可，后者要修。取不到日志也不等于没有证据：job 清单 + steps 时间戳
足以区分「跑挂了」与「被掐断」。

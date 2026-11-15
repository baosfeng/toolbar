# 发布说明在 GitHub 上「点不动」还挂了个假贡献者

> **现象**：v1.27.0 的 Release 正文里，「完整变更」那唯一一个链接打开是 404；逐条提交只有
> 反引号包着的短 hash，一行都点不进去；右侧 Contributors 里还多出一个从没参与过的「sendable」。

三个症状，三个互不相干的成因，都是发布之后才被看见。

## ① compare 链接指向 404：拼 URL 时拿的是 origin

脚本原本按「先 `GITHUB_REPOSITORY`，没有就 `remote.origin.url`」取仓库。本仓
`origin` 是 codeup（`git@codeup.aliyun.com:bsfeng/toolbar.git`），GitHub 上是另一个 remote
（`github → baosfeng/toolbar`）——本地跑脚本时拼出来的是 `github.com/bsfeng/toolbar/...`，
在 GitHub 上 404。

CI 里没暴露：Actions 自带 `GITHUB_REPOSITORY=baosfeng/toolbar`，所以 CI 日志里的链接是对的。
**「本机跑一次看着没问题、CI 跑出来也对」不等于发布正文对**——v1.27.0 的正文是人工手改过的
版本，只留了已发布正文里那一条 404 链接，掩盖了 CI 输出其实是对的这件事。

修法：`repo_slug` 先扫所有 remote 找 `github.com` 后缀的那个，找不到才退回 origin。

## ② 短 hash 不是链接

`entry="${desc}（\`${hash}\`）"` 只把 hash 包成行内代码——好看、可复制，但点不动。
改成 `[\`${hash}\`](https://github.com/<repo>/commit/${hash})`：行内代码的字形不变，
点开就是那次提交。`$`{repo}` 拿不到时（无 git 环境的兜底路径）退回纯文本。

## ③ 假贡献者：提交标题里的 `@Sendable` 被当成用户提及

GitHub 把正文里的 `@xxx` 渲染成用户 / 组织链接（`user-mention`），Release 页面据此把被 @ 的
账号挂进 Contributors。一条提交标题写着「新增踩坑「@Sendable 闭包标志位用锁盒承载」」，
于是页脚出现了 `@sendable`（某个真实存在的组织）。

同类的还有 `#123` 会变成 issue 引用——本仓没有这类写法，但机制一样。

修法：写进正文前把 `@xxx` 包成行内代码（`\`@Sendable\``），GitHub 就不会解析。
正则要带左边界，否则邮箱 `a@b.com` 会被包成 `a\`@b.com\``：

```bash
sed -E 's/(^|[^A-Za-z0-9_.-])@([A-Za-z0-9_-][A-Za-z0-9_.-]*)/\1`@\2`/g'
```

GitHub 的 `POST /markdown` 是验证渲染结果的快路子：

```bash
ghops api POST /markdown --confirm \
  --body '{"text":"新增「@Sendable 闭包」","mode":"gfm"}'
# 输出里有 user-mention 就是被解析了；包成行内代码后它变成 <code>@Sendable</code>
```

## 回归

`bash NetworkMonitor/Scripts/test-release-notes.sh`：跑真实 tag 区间，断言 compare 链接
指向 GitHub 仓库而不是 codeup owner、每条 hash 都可点、正文没有裸 `@`、邮箱里的 `@` 不被误伤。
CI 与 `Scripts/release.sh` 都先过它——发布后再手改正文是最贵的修法。

## 改已发布的 Release

正文可以用 API 直接改，不用删了重发：

```bash
python3 - <<'PY'
import json
body = open('/tmp/rel-body-fixed.md', encoding='utf-8').read()
open('/tmp/payload.json','w',encoding='utf-8').write(json.dumps({'body': body}))
PY
ghops api PATCH /repos/<owner>/<repo>/releases/<id> --body "$(cat /tmp/payload.json)" --confirm
```

`<id>` 从 `ghops --json release view <owner>/<repo> <tag>` 里取 `id`（不是 tag）。

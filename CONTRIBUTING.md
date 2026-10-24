# 贡献指南

感谢你愿意改进 NetworkMonitor。为了让改动顺利合入，请先阅读下面几条。

## 环境要求

- macOS 14+（Apple Silicon）
- Swift 6.3 工具链（Xcode 26+ 自带）
- 只装 Command Line Tools 的机器，构建命令需追加 `--build-system native`，详见[踩坑记录](docs/踩坑/构建/swift-build-会话初始化失败.md)

## 开发流程

```bash
cd NetworkMonitor
swift run --disable-sandbox TestRunner   # 全部测试通过
swift build --disable-sandbox            # 无 error
```

也可以直接跑 CI 里的同一套检查：

```bash
bash NetworkMonitor/Scripts/check-file-size.sh
```

## 提交前自查

- [ ] 测试全部通过（`🎉 所有测试通过！`）
- [ ] 编译无 error、无新增 warning
- [ ] 单文件不超过 500 行 / 15360 字节（大文件门禁）
- [ ] 提交信息为 `<type>: <中文描述>`，一次提交只做一件事
- [ ] 涉及行为变更时同步更新 `docs/` 下的文档

## 代码与文档规范

- 编码规范：[.agents/skills/toolbar-coding-standards/SKILL.md](.agents/skills/toolbar-coding-standards/SKILL.md)
- 提交规范：[docs/开发指南/提交规范.md](docs/开发指南/提交规范.md)
- 文档规范：[docs/开发指南/文档规范.md](docs/开发指南/文档规范.md)
- 文档导航：[docs/索引.md](docs/索引.md)

## 提交 PR

1. 从 `main` 拉出特性分支
2. 完成改动与测试
3. 提交 PR，描述清楚「改了什么 / 为什么 / 怎么验证」
4. 等 CI 变绿后再合并

## 发布流程

1. 更新版本号：`NetworkMonitor/Scripts/build-app.sh` 里的 `CFBundleShortVersionString`，以及 `AGENTS.md` 的版本行
2. 提交并推送 `main`，等 CI 绿
3. 打 tag 并推送：`git tag -a v1.3.2 -m "NetworkMonitor 1.3.2" && git push origin v1.3.2`
4. Release 工作流自动构建、ad-hoc 签名并上传 `NetworkMonitor.app.zip`

## 报告问题

- Bug 与功能建议走 [Issues](https://github.com/baosfeng/toolbar/issues)
- 安全漏洞请按 [SECURITY.md](SECURITY.md) 私下联系，不要开公开 issue

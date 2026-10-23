# NetworkMonitor / macMonitor — macOS 菜单栏监控

## 项目简介
- **版本:** 1.2.0
- **语言:** Swift 6.3
- **类型:** 业务应用
- **技术栈:** Swift 6.3, Swift PM, AppKit, macOS 14+, ARM64

→ [项目上下文（术语表）](CONTEXT.md)
→ [文档索引](docs/索引.md) ← 文档导航入口

> ⚠️ **操作前必读规范：**
>
> 以下规范定义了本项目必须遵守的开发规则。在执行相关操作之前，**必须先完整读取对应的规范**，确认操作符合要求，否则将导致合规检查失败。
>
> | 当你需要... | 必须先阅读 |
> |------------|-----------|
> | 修改/新增代码文件 | → **[编码规范 skill](.reasonix/skills/toolbar-coding-standards/SKILL.md)**（架构原则、命名、异常、版本号、代码查询、测试/提交纪律）+ **[UI 规范 skill](.reasonix/skills/toolbar-ui-standards/SKILL.md)**（改 UI 时） |
> | 创建/修改/删除文档 | → **[文档规范](docs/开发指南/文档规范.md)** |
> | 提交代码到 Git | → **[提交规范](docs/开发指南/提交规范.md)** |
> | 构建项目、运行测试或打包 .app | → **[构建与测试](docs/开发指南/构建与测试.md)** |
> | 排查已知编译错误或运行时问题 | → **[踩坑记录](docs/踩坑/)** |

## 功能模块
| 模块 | 说明 |
|------|------|
| 网络速度监控 | 实时网速监控（getifaddrs 差分）+ 进程网速（nettop）+ 每日流量追踪（TrafficTracker） |
| Reasonix Hook 事件监听与 Token 监控 | UDS 接收 AI 助手事件 → HookEventDispatcher 分发 → SQLite 落库；stats JSONL 导入 + Token 统计 + AI 分析 + 系统通知 |
| 计费额度查询 | 菜单面板「额度」tab：Ollama（/api/balance + /api/usage）、Open Design（编码计划 credits 窗口 + 工作区用量）；BillingProvider 协议 + 注册表，新增 provider 仅需实现协议并注册 |

## 开发指南
→ [编码规范 skill](.reasonix/skills/toolbar-coding-standards/SKILL.md)（规范权威来源，**规范更新一律写入 skill，不另建独立规范文档**）
→ [UI 规范 skill](.reasonix/skills/toolbar-ui-standards/SKILL.md)
→ [构建与测试](docs/开发指南/构建与测试.md)
→ [提交规范](docs/开发指南/提交规范.md)
→ [文档规范](docs/开发指南/文档规范.md)

## 踩坑记录
→ [踩坑记录](docs/踩坑/)

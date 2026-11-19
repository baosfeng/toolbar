# 脚手架生成器（Scaffold）

「新增一类东西」的**样板代码生成 + 人工步骤清单**。四个高频扩展点各一个脚本：

| 脚本 | 生成 | 人工步骤 |
|---|---|---|
| `new-panel-tab.sh <id> <中文名>` | `MenuPanel/<Pascal>PaneView.swift`（页头 / 内容 / 状态带骨架） | 9 处（枚举 / stableIDs / 懒装配 / 回调 / 首屏 / 快照 / 测试 / 登记 / 文档） |
| `new-settings-pane.sh <id> <中文名>` | `Settings/Settings<Pascal>Pane.swift`（page 栈 + 卡片骨架） | 6 处（SettingsSection 四 switch / SectionID / 侧栏分组 / 工厂 / 测试 / 文档） |
| `new-billing-provider.sh <kindID> <显示名>` | `Billing/Providers/<Pascal>BillingProvider.swift`（协议实现 + 8 类错误映射） | 5 处（组合根登记 / 窗口种类 / 测试 / 文档 / 自检） |
| `new-notification-event.sh <rawValue> <中文名>` | `TestRunner/NotificationEvent<Pascal>Tests.swift`（事件表守卫） | 7 处（枚举 / 5 个 switch / cue / 偏好键 / 设置页挂卡 / 测试 / 登记） |

完整清单（含「必须补的测试」「必须更新的文档」）见 [扩展点清单](../../../docs/开发指南/扩展点清单.md)。

## 用法

```bash
cd <repo>

# 1) 先看要生成什么、要手工改哪几处（不落盘）
bash NetworkMonitor/Scripts/scaffold/new-panel-tab.sh weather 天气 --dry-run

# 2) 确认后落盘（默认落源码目录；路径与项目现有目录一致）
bash NetworkMonitor/Scripts/scaffold/new-panel-tab.sh weather 天气

# 3) 自测用别往仓库里写
bash NetworkMonitor/Scripts/scaffold/new-panel-tab.sh weather 天气 --out /tmp/scaffold-check
```

公共选项（四个脚本一致）：

| 选项 | 作用 |
|---|---|
| `--dry-run` | 只打印将写入的文件与全部人工步骤 |
| `--out <目录>` | 换落点；自测一律落 `/tmp`，别在仓库里留垃圾 |
| `--force` | 目标已存在时覆盖（默认拒绝，避免手滑盖掉别人的文件） |

参数校验：id 必须小写字母开头、只含 `[a-z0-9-]`；通知事件的 rawValue 用 camelCase（它直接进偏好键 `notify.<rawValue>.*`）。非法入参 exit 2，不做任何写入。

## 为什么只生成、不自动改既有文件

一句话：**自动改既有文件 = 撞别人分支**。

1. **插入点全是别人正在改的热点文件**。面板分页要改 `MenuTabBarView.swift` / `PanelTabCatalog.swift` / `MenuPanelView+Panes.swift` / `MenuPanelController.swift`；设置分类要改 `SettingsSection.swift` 的四个 switch 与 `AppCoordinator+Settings.swift`。这些文件在本仓的并行开发里被多路共用，脚本用 sed 精准插行听起来可行，实际上：
   - 行号会漂移，`sed -i '20a\…'` 插错位置后**编译仍然通过**，只是行为不对；
   - 插入失败不会有人发现（脚本报错被 `|| true` 吞掉的先例见 `docs/踩坑/构建/打包脚本按名字杀进程连坐.md`）；
   - 用户 review 一个「生成器改了我 6 个核心文件」的 diff，比 review 一个新增文件难得多。
2. **生成的文件是隔离的**，删掉就干净；改既有文件的失败要人肉回滚。
3. **人工步骤本身有信息量**。「加 case 时同一文件 4 个 switch 必须一起补」「新分页会撞 `PanelTabCatalogTests` 的硬编码计数」这类约束，写在打印清单里，比藏在 sed 表达式里更容易被读到。

所以脚本做到「生成物一定能编译，剩下的接线由人做」，并且**把该改的 file:line 打印出来**——照着清单改，比全仓考古快，也比自动改安全。

## 生成物能编译，但功能还没接上

这是设计如此，不是缺陷：

- 新面板分页：文件编译通过，但没进 `MenuPanelTab` 与 `stableIDs` 前，分页条上不会出现它。
- 新设置分页：`super.init` 用 `SettingsSection(rawValue: "<id>") ?? .general` 做了两阶段接入——加 case 之前它能编译（页头临时显示「通用」），加完 case 把那一行改成 `.yourID` 即可。
- 新额度 provider：类编译通过，但没进 `AppCoordinator.swift` 的 `billingKinds` 前，额度页不会出现它。
- 新通知事件：守卫套件**加 case 之前是红的**（提示「尚未登记」），加完即转绿——这是引导，不是故障。

## 自测（改完脚本后必跑）

```bash
# 语法
for f in NetworkMonitor/Scripts/scaffold/*.sh; do bash -n "$f"; done

# 四个都生成到 /tmp 并逐个编译（脚本产物必须能进构建）
for gen in "new-panel-tab.sh weather 天气" "new-settings-pane.sh disk-health 磁盘健康" \
           "new-billing-provider.sh acme Acme" "new-notification-event.sh diskHealth 磁盘健康"; do
    bash NetworkMonitor/Scripts/scaffold/$gen --out /tmp/scaffold-check || exit 1
done
# 把生成物临时拷进源码树 → swift build → 再删掉（见 .arch-audit/engineering.md §3 的验证口径）
```

实测（本轮）：四个脚本各生成一次，产物拷进源码树后 `swift build --disable-sandbox --build-system native` → `Build complete!`，删掉产物后仓库恢复干净。

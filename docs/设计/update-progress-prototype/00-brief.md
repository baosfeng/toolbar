# 00 需求澄清 —— 检查更新 / 下载安装（更新卡原型）

platform: desktop            # macOS 原生 App（AppKit 设置窗口），非网页
canvas: 760x540              # SettingsSkeletonMetrics.windowWidth/Height（侧栏 168 + 内容区 592）
frames: [macbook]            # 桌面原生窗口，不加浏览器框
style: toolbar-settings      # 项目自有：ThemeCatalog 语义角色 + 设置页定稿度量
responsive: no               # 固定 760×540；内容区纵向滚动
breakpoints: []
min_supported: 760
dark_mode: required          # ThemeCatalog 浅深各一，深色一等公民（light-dark 承担）
locale: zh-CN
deliverable: interactive-prototype
first_screen: 关于页「更新」卡整卡可见：版本信息 + 四段进度 + 操作 + 新版本说明
fixed_constraints: 窗口 760×540 / 侧栏 168pt / 卡圆角 9pt / 卡内边距 10·6 / 行高 32pt / 卡头 11.5 粗 / 页头 17 粗 / 状态胶囊 20pt·圆角 6pt
notes: 用户原话「如果我是在检测更新那边检测更新了，完全看不到我的下载进度和显示的更新的信息」；两版只差进度展示形态（A 单条阶段条 / B 阶段清单），其余完全一致

## 已拍板（用户原话）

- 下载进度必须可见：字节级百分比 + 已下载/总大小 + 速度 + 剩余时间，进度要有动画感，不能是死数字。
- 更新信息必须完整：新版本号、发布日期、包大小、本机架构、SHA-256 校验状态、下载来源；说明区要能看清单块。
- 阶段要可读：下载 → 校验 → 安装（备份 + 换包）→ 重启，四段要能看出「现在在哪一段、还剩几段」；失败段单独可辨并保留已下载内容。
- 天花板是设置页里的一张卡，不是全屏下载器；密度高但要克制（Xcode / Sparkle 的分寸）。

## leader 推断（待用户确认，不写进契约）

- 「检查更新」与「安装」两张卡合并为一张「更新」卡 —— 用户看不出进度是因为进度在另一张卡、还要往下滚。
- 页头常驻：滚动时「关于」标题 + 状态胶囊不滚走，任何滚动位置都能看到当前阶段。
- 开始下载时内容区自动滚到更新卡（用 scrollTo，不用会被 OD 预览打断的 scrollIntoView）。
- 应用卡保持在更新卡之上（真实结构不动），原型默认定位到更新区，另给「回到顶部」。

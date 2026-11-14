# 踩坑记录

> ⚠️ **何时阅读：** 当你在开发、构建或运行过程中遇到异常时，请在对应功能域中查找是否有类似问题的记录和解决方案。

## 功能域

踩坑按功能域组织，清单与 [文档索引](../索引.md) 的「踩坑记录」段落保持一致。

### swift-并发

- [Swift 6 @unchecked Sendable 标记需求](swift-并发/unchecked-sendable.md)
- [@MainActor 类适配协议需要 @preconcurrency](swift-并发/preconcurrency-mainactor.md)
- [@Sendable 闭包标志位用锁盒承载](swift-并发/@Sendable闭包标志位用锁盒.md) — `@Sendable` 闭包里的可变标志位改用 `OSAllocatedUnfairLock` 锁盒；隔离诊断优先 `nonisolated` / `MainActor.assumeIsolated`，后者是运行时断言，只用于有 AppKit 文档依据的主线程回调
- [os_log_with_type 宏在 Swift 中不可用](swift-并发/os_log_swift_api.md)

### 接口

- [Open Design 额度接口鉴权与聚合](接口/open-design-额度接口-鉴权与聚合.md) — 只认 Cookie 不认 Bearer；用量窗口只有最近 7 天（超窗/终点在未来都报 invalid_workspace_usage_time_range）；汇总读顶层 summary/totalCount，翻页与逐桶请求都不可行

### 构建

- [swift build 会话初始化失败（本机无 Xcode）](构建/swift-build-会话初始化失败.md) — 本机无 Xcode 时默认后端初始化失败，构建需加 `--build-system native`
- [bash 变量后紧跟中文标点导致 unbound variable](构建/bash-变量后紧跟中文标点.md) — `set -u` 下变量后接全角标点会报 unbound variable，并造成隐蔽假绿
- [release 构建暴露 DEBUG 块方法](构建/release构建暴露DEBUG块方法.md) — debug 绿 release 红：生产方法被写进 `#if DEBUG`，发版打包才暴露
- [生产日志不可观测](构建/生产日志不可观测.md) — LaunchServices 启动的 .app 丢弃 stdout，默认 ConsoleLogger 导致生产零日志；需在组合根注入 OSLogLogger
- [菜单项清理误删无关条目](构建/菜单项清理误删无关条目.md) — 按「tag >= 阈值」无界扫描清理菜单项会误删其他模块的高位 tag 入口；须改用有界区间 [base, base+span)
- [Swift 扩展不能有存储属性](构建/Swift扩展不能有存储属性.md) — 按门禁拆文件时，存储属性与 override 方法必须留在主类，跨文件成员需放宽为 internal
- [快照取证需打包成 app](构建/快照取证需打包成app.md) — 裸二进制跑 `NM_SNAPSHOT_DIR` 必崩 `bundleProxyForCurrentProcess is nil`，须 `SKIP_INSTALL=1 ./Scripts/build-app.sh debug` 后跑包内可执行文件

### 运行时

- [监控数据长时间运行后失效](运行时/监控数据长时间运行后失效.md) — 额度页整页空白 = 暂停态短路（无对外连接）；今日流量恒 0 = 累计回退后基准失配
- [像素取色偏移](运行时/像素取色偏移.md) — 重绘取色三连坑：色彩空间转换、字节序、行序；马赛克缩小时插值选错会退化成纯黑/纯白
- [设置窗弱引用即释放](运行时/设置窗弱引用即释放.md) — `weak` 捕获局部变量、无强引用持有者时窗口创建即销毁，表现是「show() 无任何反应」
- [nettop 进程流量漏记](运行时/nettop-进程流量漏记.md) — 重复传 `-m` 只保留最后一个（实际退化为仅 UDP），TCP 进程全部缺席；用 `-J bytes_in,bytes_out` 固定列数
- [进程 CPU 百分比时基换算](运行时/进程CPU百分比时基换算.md) — `pti_total_user/system` 单位是 mach ticks 不是纳秒，timebase=125/3 时按 ns 换算会小 41.67 倍（3 线程自旋误算 7.2% vs 正确 298.0%）
- [IOReport 读取崩溃](运行时/IOReport读取崩溃.md) — 三处 SIGSEGV 用法（nil callback 建 dict、unsafeBitCast 取通道元素、按 ChannelGetFormat 分派）与唯一稳定写法
- [截图覆盖层拿不到键盘与首帧绘制](运行时/截图覆盖层拿不到键盘与首帧绘制.md) — 菜单栏 App 抢不到系统前台 → Esc / 回车时灵时不灵；首帧无 NSGraphicsContext 直接 return 导致永久留白；抓屏期间重复按热键叠层
- [截图覆盖层把整个键盘扣住](运行时/截图覆盖层把整个键盘扣住.md) — CGEventTap「装着就吞一切」使 ⌘Tab / ⌘Q / ⌘空格 失效、文字标注打不进字；拦截须走白名单 + 编辑态放行 + ⌘ 组合优先
- [截图工具条按钮被前序分支挡住](运行时/截图工具条按钮被前序分支挡住.md) — 裸字母键位分支先吃掉 ⌘S / ⌘A；工具条宽度与布局两份累加式导致右侧多 17pt 空白；保存链路没走合成导致标注丢失
- [截图坐标偏移与闪屏](运行时/截图坐标偏移与闪屏.md) — `CGDisplayPixelsWide` 在 macOS 27 的 2x 屏返回点数，缩放比退化成 1 使选区偏到左上；抢前台先于抓屏会闪一下，并把自家 popover 截成背景
- [截图窗口识别粒度](运行时/截图窗口识别粒度.md) — 只取 layer 0 会漏掉菜单栏 / 程序坞 / 状态栏项，排除自家进程会漏掉自家 popover；改层级白名单 + 自家进程按覆盖层分级 + 程序坞贴边带
- [设置项写了不生效](运行时/设置项写了不生效.md) — 存储实例不同源 / 只在 init 读一次 / 偏好没有消费方 / 用 `code > 0` 判存在性（A 键 keyCode 就是 0）四类同源故障
- [抓屏路径崩溃](运行时/抓屏路径崩溃.md) — `captureImage(in:)` 桥接到 Swift 是非可选 `CGImage`，锁屏等场景系统返回 nil 会直接断言崩溃且崩在系统回调线程；保留抓屏路径的唯一标准是 Swift 签名可选
- [忽略鼠标事件的浮层自己收不到滚轮](运行时/忽略鼠标事件的浮层自己收不到滚轮.md) — `ignoresMouseEvents = true` 的浮层收不到任何鼠标事件，内部滚动条拖不动也滚不动；滚轮改由父视图转发，返回值决定是否消费
- [离屏快照里投影要靠像素差自证](运行时/离屏快照里投影要靠像素差自证.md) — 投影看不见有三种成因（裸图层无填充内容 / 宿主 `masksToBounds` 裁切 / 单图暗像素阈值假阴性）；判据是「有阴影 vs 无阴影」两图逐像素做差
- [毛玻璃材质离屏不可辨](运行时/毛玻璃材质离屏不可辨.md) — `NSVisualEffectView` 的模糊由窗口服务器合成，`cacheDisplay` 只给近似底色（浅 255→228）；判据是结构自证（材质 / 圆角 / 内缩 / 层级 / hitTest）+ 真机确认

---

> 踩坑按功能域组织，遇到问题时先搜索对应域下的条目文件。

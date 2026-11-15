import Foundation
import NetworkMonitorCore

// MARK: - 内建音选择与落盘测试

/// 覆盖两件事：
/// 1. NotificationSoundSelection 的存储值契约（builtin / default / system:X / custom:y / silent）
///    与解析回落口径——老串语义不变，未知串一律回落内建；
/// 2. CueSoundFileStore 的落盘幂等（第二次不重写、sidecar 版本失配才重建、孤儿清扫有界）。
func runCueSoundStoreTests() {
    print("\n🧪 Testing 内建音选择（存储值 / 回落口径）...")
    testSoundSelectionStorage()

    print("\n🧪 Testing 内建音落盘（幂等 / 版本失配重建 / 孤儿清扫）...")
    testCueSoundFileStore()
}

// MARK: - 选择

func testSoundSelectionStorage() {
    // 每一种选择的存储值往返
    let all: [NotificationSoundSelection] = [
        .builtIn, .systemDefault, .systemSound("Glass"), .customFile("我的叮.aiff"), .silent,
    ]
    for selection in all {
        assertEqual(NotificationSoundSelection(storageValue: selection.storageValue), selection,
                    "存储值往返：\(selection.storageValue)")
    }
    assertEqual(NotificationSoundSelection.builtIn.storageValue, "builtin", "内建音存 builtin")
    assertEqual(NotificationSoundSelection(storageValue: "builtin"), .builtIn, "builtin → 内建音")

    // 老配置语义不变：default 仍然是「跟随系统」，不是内建
    assertEqual(NotificationSoundSelection(storageValue: "default"), .systemDefault,
                "老值 default 语义不变（跟随系统）")
    assertEqual(NotificationSoundSelection(storageValue: "system:Glass"), .systemSound("Glass"),
                "老值 system:Glass 语义不变")
    assertEqual(NotificationSoundSelection(storageValue: "custom:x.aiff"), .customFile("x.aiff"),
                "老值 custom:x.aiff 语义不变")
    assertEqual(NotificationSoundSelection(storageValue: "silent"), .silent, "老值 silent 语义不变")

    // 未知串一律回落内建（默认档）
    assertEqual(NotificationSoundSelection(storageValue: "脏数据"), .builtIn, "脏数据回落内建音")
    assertEqual(NotificationSoundSelection(storageValue: ""), .builtIn, "空串回落内建音")
    assertEqual(NotificationSoundSelection(storageValue: "system:"), .builtIn, "空系统音名回落内建音")
    assertEqual(NotificationSoundSelection(storageValue: "custom:"), .builtIn, "空自定义名回落内建音")
    assertEqual(NotificationSoundSelection(storageValue: " builtin "), .builtIn, "两端空白被裁掉")

    // 下拉文案：内建排第一，文案「内建（咔哒）」
    assertEqual(NotificationSoundSelection.builtIn.menuTitle, "内建（咔哒）", "内建音下拉文案")
    assertEqual(NotificationSoundSelection.systemDefault.menuTitle, "跟随系统", "跟随系统文案不变")
    assertEqual(NotificationSoundSelection.silent.menuTitle, "静音", "静音文案不变")
    assertEqual(NotificationSoundSelection.systemSound("Glass").menuTitle,
                SystemSoundCatalog.menuTitle(for: "Glass"), "系统音沿用系统音效库文案")
    assertEqual(NotificationSoundSelection.customFile("我的叮.aiff").menuTitle,
                "自定义 · 我的叮", "自定义音去扩展名显示")

    // 事件默认档 = 内建音，且解析出来是合成目标而不是系统音
    for event in NotificationEvent.allCases {
        assertEqual(event.defaultSound, .builtIn, "事件 \(event.rawValue) 默认内建音")
        assertEqual(NotificationSoundResolver.cueSound(selection: .builtIn, cue: event.previewCue),
                    .builtIn(event.previewCue),
                    "内建档解析成合成音：\(event.rawValue)")
    }
    // 内建音在系统通知侧的命名：按 cue 一份，带上事件自己的 cue
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .builtIn,
                                                           presentation: .bannerAndSound,
                                                           installedName: { _ in "NetworkMonitor-builtin-cue-error.aiff" }),
                .named("NetworkMonitor-builtin-cue-error.aiff"), "内建档通知挂生成文件")
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .builtIn,
                                                           presentation: .bannerOnly,
                                                           installedName: { _ in "x.aiff" }),
                .silent, "内建档 + 仅横幅 → 通知静音")

    // 通知副本命名：按 cue 一份，且能从文件名反查回 cue（有界清理的判据就在这里）
    for cue in NotificationCue.allCases {
        let name = CueSoundInstallName.fileName(for: cue)
        assertEqual(name, "NetworkMonitor-builtin-cue-\(cue.rawValue).aiff", "副本命名：\(cue.rawValue)")
        assertEqual(CueSoundInstallName.cue(forFileName: name), cue, "副本名反查 cue：\(cue.rawValue)")
    }
    assertEqual(CueSoundInstallName.cue(forFileName: "NetworkMonitor-sys-Glass.aiff"), nil,
                "别的族的副本不认作内建音")
    assertEqual(CueSoundInstallName.cue(forFileName: "NetworkMonitor-builtin-cue-unknown.aiff"), nil,
                "未知 cue 名不认")
    assertEqual(CueSoundInstallName.cue(forFileName: "别人的音效.aiff"), nil, "非本模块文件不认")
}

// MARK: - 落盘

func testCueSoundFileStore() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nm-cue-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = CueSoundFileStore(directory: root)

    // 首次生成：文件出现且内容等于合成器输出
    let url = store.ensure(cue: .copy)
    assertNotNil(url, "首次 ensure 写出文件")
    guard let url else { return }
    assertEqual(FileManager.default.fileExists(atPath: url.path), true, "文件已落盘")
    assertEqual(try? Data(contentsOf: url), CueSoundSynth.aiffData(for: .copy),
                "落盘内容与合成器输出逐字节相同")
    assertEqual(url.lastPathComponent, "cue-copy.aiff", "文件名 cue-<cue>.aiff")

    // 幂等：第二次不重写——用 inode / 修改时间判「没被动过」
    let before = attributes(url)
    let again = store.ensure(cue: .copy)
    assertEqual(again?.path, url.path, "第二次返回同一个路径")
    let after = attributes(url)
    assertEqual(after?.inode, before?.inode, "第二次没有替换文件（inode 不变）")
    assertEqual(after?.modifiedAt, before?.modifiedAt, "第二次没有重写（修改时间不变）")

    // 版本失配（模拟配方升级）：sidecar 记旧版本 → 必须重建
    try? Data(#"{"copy":"0"}"#.utf8)
        .write(to: root.appendingPathComponent("cue-manifest.json"), options: .atomic)
    let rebuilt = store.ensure(cue: .copy)
    assertNotNil(rebuilt, "版本失配后重建成功")
    assertEqual(try? Data(contentsOf: url), CueSoundSynth.aiffData(for: .copy),
                "重建后内容仍是当前配方")

    // sidecar 损坏 → 当作空表，重写一次但内容不变（不崩、不静默失败）
    try? Data("not json".utf8)
        .write(to: root.appendingPathComponent("cue-manifest.json"), options: .atomic)
    assertNotNil(store.ensure(cue: .copy), "sidecar 损坏后仍能重建")

    // 文件被删掉（用户在 Finder 里清过目录）：ensure 自动补回
    try? FileManager.default.removeItem(at: url)
    assertNotNil(store.ensure(cue: .copy), "文件缺失时自动补回")

    // 全量预热 + 目录统计（copy 上一步已就位，所以只有十份是本次写的）
    let written = store.ensureAll()
    assertEqual(written.count, NotificationCue.allCases.count - 1, "预热补齐其余十个 cue")
    assertEqual(store.ensureAll(), [], "再预热一遍一个都不写（幂等）")
    assertEqual(store.files().count, NotificationCue.allCases.count, "目录里恰好十一份")
    assertEqual(store.totalBytes() > 0, true, "目录占用来算得出来")

    // 孤儿清扫：只删本目录内「不是当前 cue 名」的 aiff，别人的文件不动
    let orphan = root.appendingPathComponent("cue-removed.aiff")
    try? Data([0x00]).write(to: orphan)
    let foreign = root.appendingPathComponent("notes.txt")
    try? Data([0x00]).write(to: foreign)
    store.sweepOrphans()
    assertEqual(FileManager.default.fileExists(atPath: orphan.path), false, "孤儿 aiff 被清掉")
    assertEqual(FileManager.default.fileExists(atPath: foreign.path), true, "非 aiff 文件不动")
    assertEqual(store.files().count, NotificationCue.allCases.count, "清扫后仍是十一份")

    // 目录不存在时也能自己建出来（首次启动的常见路径）
    let fresh = CueSoundFileStore(directory: root.appendingPathComponent("nested/deep"))
    assertNotNil(fresh.ensure(cue: .pin), "目录不存在时自建并写出")
}

/// 取文件的 inode 与修改时间（判「有没有被动过」）
private func attributes(_ url: URL) -> (inode: UInt64?, modifiedAt: Date?)? {
    guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey,
                                                          .contentModificationDateKey]) else {
        return nil
    }
    let identifier = values.fileResourceIdentifier as? UInt64
    return (identifier, values.contentModificationDate)
}

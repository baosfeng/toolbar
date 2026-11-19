import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板分页 / 设置分类的组装式装配（Descriptor + Registry）

/// 注册表自洽判据的四类边界 —— 重复 id / 缺项 / 顺序 / 目录外 id
///
/// 为什么要逐条钉：注册表是「加一个分页只改注册表」的唯一依据，判据一旦漏一类，
/// 装配错误就会静默变成「分段条少一段 / 快照图互相覆盖 / 数字键切错页」，
/// 而这些都不会有编译错误。
func runPaneModuleRegistryTests() {
    print("\n🧪 Testing 面板分页描述符与注册表（正常 / 重复 / 缺项 / 顺序）...")

    // MARK: 正常路径：目录全量装配即自洽

    let catalog = PaneModuleCatalog.descriptors
    assertEqual(PaneModuleCatalog.validate(catalog), [], "描述符目录本身自洽")
    assertEqual(PaneModuleCatalog.orderedIDs, PanelTabCatalog.stableIDs,
                "描述符顺序 = 分页目录顺序")

    let registry = PaneDescriptorRegistry.registeringCatalog()
    assertEqual(registry.validate(), [], "目录装配的注册表自洽")
    assertEqual(registry.all.count, catalog.count, "装配后条目数不变")
    assertEqual(registry.all, catalog.sorted(by: PaneModuleCatalog.sortByIndex),
                "注册表按 sortIndex 排序（与目录声明序一致）")

    // MARK: 等价性：五个分页的 id / 标题 / 图标 / 快照后缀 / 取证标识逐项固定

    let expected: [(id: String, raw: Int, title: String, symbol: String, suffix: String)] = [
        ("network", 0, "网络", "network", "network"),
        ("transfer", 2, "传送", "paperplane", "transfer"),
        ("credits", 3, "额度", "creditcard", "credits"),
        ("token", 4, "Token", "chart.bar.xaxis", "token"),
        ("system", 5, "系统", "gauge.with.dots.needle.67percent", "system"),
    ]
    for (index, item) in expected.enumerated() {
        guard let descriptor = PaneModuleCatalog.descriptor(forID: item.id) else {
            assertEqual("缺描述符", item.id, "分页描述符必须存在")
            continue
        }
        assertEqual(descriptor.rawValue, item.raw, "\(item.id) 的历史编号")
        assertEqual(descriptor.title, item.title, "\(item.id) 的分段条文案")
        assertEqual(descriptor.symbolName, item.symbol, "\(item.id) 的分段条图标")
        assertEqual(descriptor.snapshotSuffix, item.suffix, "\(item.id) 的快照后缀")
        assertEqual(descriptor.evidenceKey, item.suffix, "\(item.id) 的取证标识")
        assertEqual(descriptor.sortIndex, index, "\(item.id) 的声明序")
    }

    // 反查入口：按 id / 历史编号 / 取证标识都能命中同一条
    assertEqual(PaneModuleCatalog.descriptor(forRawValue: 3)?.id, "credits",
                "按历史编号 3 查到额度页（编号冻结不前移）")
    assertEqual(PaneModuleCatalog.descriptor(forEvidenceKey: "credits")?.id, "credits",
                "按取证标识查到额度页（曾经漏登记的分页）")
    assertEqual(PaneModuleCatalog.descriptor(forRawValue: 1), nil,
                "已下线的 1 号没有描述符")
    assertEqual(PaneModuleCatalog.descriptor(forID: "clipboard"), nil,
                "已下线的剪贴板没有描述符")

    // MARK: 边界一：重复 id

    var duplicated = catalog
    if let first = catalog.first {
        duplicated.append(PaneModuleDescriptor(id: first.id,
                                               rawValue: 99,
                                               title: "重复",
                                               symbolName: "circle",
                                               snapshotSuffix: "dup",
                                               evidenceKey: "dup",
                                               sortIndex: 99))
    }
    assertContains(PaneModuleCatalog.validate(duplicated).map(\.description).joined(separator: "|"),
                   "分页 id 重复", "重复注册同一 id 被识别")

    // MARK: 边界二：缺项 / 目录外的 id

    let missing = Array(catalog.dropFirst())
    assertContains(PaneModuleCatalog.validate(missing).map(\.description).joined(separator: "|"),
                   "分页未注册", "少注册一个分页被识别")

    let extra = catalog + [PaneModuleDescriptor(id: "ghost",
                                                rawValue: 98,
                                                title: "幽灵",
                                                symbolName: "circle",
                                                snapshotSuffix: "ghost",
                                                evidenceKey: "ghost",
                                                sortIndex: 98)]
    assertContains(PaneModuleCatalog.validate(extra).map(\.description).joined(separator: "|"),
                   "分页 id 不在目录里", "注册了目录外的 id 被识别")

    // MARK: 边界三：顺序

    // 声明序是唯一真源：把前两条的 sortIndex 互换，登记表排出来的顺序就与目录不同
    var reordered = catalog
    if catalog.count >= 2 {
        reordered[0] = withSortIndex(catalog[0], catalog[1].sortIndex)
        reordered[1] = withSortIndex(catalog[1], catalog[0].sortIndex)
    }
    assertContains(PaneModuleCatalog.validate(reordered).map(\.description).joined(separator: "|"),
                   "分页顺序与目录不一致", "声明序被改写被识别")

    // MARK: 边界四：后缀 / 取证标识撞车（会互相覆盖快照图）

    var sameSuffix = catalog
    if sameSuffix.count >= 2 {
        let second = sameSuffix[1]
        sameSuffix[1] = PaneModuleDescriptor(id: second.id,
                                             rawValue: second.rawValue,
                                             title: second.title,
                                             symbolName: second.symbolName,
                                             snapshotSuffix: sameSuffix[0].snapshotSuffix,
                                             evidenceKey: second.evidenceKey,
                                             sortIndex: second.sortIndex)
    }
    assertContains(PaneModuleCatalog.validate(sameSuffix).map(\.description).joined(separator: "|"),
                   "快照后缀重复", "快照后缀撞车被识别")

    // MARK: 注册表语义：同 id 覆盖 + 空表

    var mutable = PaneDescriptorRegistry()
    guard let network = PaneModuleCatalog.descriptor(forID: "network") else {
        assertEqual("缺描述符", "network", "网络页描述符必须存在")
        return
    }
    assertEqual(mutable.register(network), true, "首次注册返回「新增」")
    assertEqual(mutable.register(network), false, "同 id 再注册返回「覆盖」")
    assertEqual(mutable.all.count, 1, "覆盖不产生第二条")
    assertEqual(PaneDescriptorRegistry().all.isEmpty, true, "空注册表无条目")
    assertEqual(PaneDescriptorRegistry().validate().count > 0, true,
                "空注册表校验失败（全部缺项）")
    assertEqual(PaneModuleDescriptor.placeholder(rawValue: 42).id, "unregistered-42",
                "未登记分页的兜底描述符带编号，不冒充已有分页")
}

/// 设置分类注册表自洽 —— 与分页同构的判据（重复 / 缺项 / 顺序 / 分组归属）
func runSettingsSectionRegistryTests() {
    print("\n🧪 Testing 设置分类描述符与注册表（正常 / 重复 / 缺项 / 顺序 / 分组）...")

    let catalog = SettingsSectionCatalog.descriptors
    assertEqual(SettingsSectionCatalog.validate(catalog), [], "分类描述符目录本身自洽")

    let registry = SettingsDescriptorRegistry.registeringCatalog()
    assertEqual(registry.validate(), [], "目录装配的分类注册表自洽")
    assertEqual(registry.all.map { $0.id.rawValue }, SettingsSectionID.allCases.map { $0.rawValue },
                "注册表顺序 = 分类枚举顺序")
    assertEqual(registry.all.map { $0.id.rawValue }, SettingsSidebarLayout.allItems.map { $0.rawValue },
                "注册表顺序 = 侧栏展示顺序")

    // 每一条描述符都要有非空文案 / 图标 / 副标题 / 后缀（漏填会静默少一段）
    for descriptor in registry.all {
        assertEqual(descriptor.title.isEmpty, false, "\(descriptor.id.rawValue) 有标题")
        assertEqual(descriptor.symbolName.isEmpty, false, "\(descriptor.id.rawValue) 有图标")
        assertEqual(descriptor.subtitle.isEmpty, false, "\(descriptor.id.rawValue) 有副标题")
        assertEqual(descriptor.fileSuffix.isEmpty, false, "\(descriptor.id.rawValue) 有快照后缀")
    }

    // 等价性：改造前四个穷尽 switch 的取值逐项不变（挑两个高频页固定住）
    assertEqual(SettingsSectionCatalog.descriptor(for: .providers)?.title, "额度 Provider",
                "额度页标题与改造前一致")
    assertEqual(SettingsSectionCatalog.descriptor(for: .token)?.symbolName, "chart.bar.doc.horizontal",
                "Token 页图标与改造前一致")
    assertEqual(SettingsSectionCatalog.descriptor(for: .capture)?.fileSuffix, "capture",
                "截图页快照后缀与改造前一致")

    // MARK: 边界一：重复 id / 缺项 / 顺序

    var duplicated = catalog
    if let first = catalog.first {
        duplicated.append(SettingsSectionDescriptor(id: first.id,
                                                    title: "重复",
                                                    symbolName: "circle",
                                                    subtitle: "重复",
                                                    fileSuffix: "dup",
                                                    group: .feature))
    }
    assertContains(SettingsSectionCatalog.validate(duplicated).map(\.description).joined(separator: "|"),
                   "设置分类 id 重复", "重复注册同一分类被识别")

    let missing = Array(catalog.dropLast())
    assertContains(SettingsSectionCatalog.validate(missing).map(\.description).joined(separator: "|"),
                   "设置分类未注册", "少注册一个分类被识别")

    var reordered = catalog
    if catalog.count >= 2 { reordered.swapAt(0, 1) }
    assertContains(SettingsSectionCatalog.validate(reordered).map(\.description).joined(separator: "|"),
                   "设置分类顺序与目录不一致", "分类顺序被打乱被识别")

    // MARK: 边界二：分组归属与侧栏表不一致

    var wrongGroup = catalog
    if let index = wrongGroup.firstIndex(where: { $0.id == .about }) {
        let about = wrongGroup[index]
        wrongGroup[index] = SettingsSectionDescriptor(id: about.id,
                                                      title: about.title,
                                                      symbolName: about.symbolName,
                                                      subtitle: about.subtitle,
                                                      fileSuffix: about.fileSuffix,
                                                      group: .general)
    }
    assertContains(SettingsSectionCatalog.validate(wrongGroup).map(\.description).joined(separator: "|"),
                   "侧栏分组不一致", "分组归属与侧栏表不符被识别")

    // MARK: 注册表语义

    var mutable = SettingsDescriptorRegistry()
    guard let general = SettingsSectionCatalog.descriptor(for: .general) else {
        assertEqual("缺描述符", "general", "通用页描述符必须存在")
        return
    }
    assertEqual(mutable.register(general), true, "首次注册返回「新增」")
    assertEqual(mutable.register(general), false, "同 id 再注册返回「覆盖」")
    assertEqual(mutable.all.count, 1, "覆盖不产生第二条")
    assertEqual(SettingsDescriptorRegistry().validate().count > 0, true,
                "空注册表校验失败（全部缺项）")
    assertEqual(SettingsSectionDescriptor.placeholder(id: .about).title, "about",
                "未登记分类的兜底描述只显示 id，不冒充已有文案")
}

/// 复制一份描述符并改写声明序（边界用例构造用）
private func withSortIndex(_ descriptor: PaneModuleDescriptor,
                           _ sortIndex: Int) -> PaneModuleDescriptor {
    PaneModuleDescriptor(id: descriptor.id,
                         rawValue: descriptor.rawValue,
                         title: descriptor.title,
                         symbolName: descriptor.symbolName,
                         snapshotSuffix: descriptor.snapshotSuffix,
                         evidenceKey: descriptor.evidenceKey,
                         sortIndex: sortIndex)
}

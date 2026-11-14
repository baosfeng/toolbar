import Foundation
import NetworkMonitorCore

// MARK: - 额度 provider 多实例

/// 覆盖：实例标识规则 / 实例增删改 / 持久化 / 装饰器转发 / 注册表多实例
/// （「老配置零迁移」单独在 BillingInstanceMigrationTests.swift）
func runBillingInstanceTests() {
    print("\n🧪 Testing BillingInstanceID...")
    testInstanceIdentity()

    print("\n🧪 Testing BillingInstanceStore（纯变更 + 持久化）...")
    testInstanceMutationAndStore()

    print("\n🧪 Testing BillingProviderInstance（装饰器）...")
    testProviderInstanceDecorator()

    print("\n🧪 Testing 多实例注册表...")
    testRegistryMultiInstance()

    runBillingInstanceMigrationTests()

    print("✅ Billing 多实例 works")
}

// MARK: - 标识规则

private func testInstanceIdentity() {
    assertEqual(BillingInstanceID.make(kindID: "cursor", slug: nil), "cursor", "默认实例标识 = kindID")
    assertEqual(BillingInstanceID.make(kindID: "cursor", slug: "work"), "cursor::work",
                "命名实例标识 = kindID + 分隔符 + 后缀")
    assertEqual(BillingInstanceID.kind(of: "cursor::work"), "cursor", "解析出 kind")
    assertEqual(BillingInstanceID.kind(of: "cursor"), "cursor", "默认实例解析出 kind")
    assertEqual(BillingInstanceID.slug(of: "cursor::work") ?? "", "work", "解析出后缀")
    assertEqual(BillingInstanceID.slug(of: "cursor") == nil, true, "默认实例无后缀")
    assertEqual(BillingInstanceID.isDefault("cursor"), true, "默认实例判定")
    assertEqual(BillingInstanceID.isDefault("cursor::work"), false, "命名实例判定")

    assertEqual(BillingInstanceID.isValidSlug("work"), true, "小写字母合法")
    assertEqual(BillingInstanceID.isValidSlug("work-2"), true, "字母数字连符合法")
    assertEqual(BillingInstanceID.isValidSlug("Work"), false, "大写不合法")
    assertEqual(BillingInstanceID.isValidSlug("-work"), false, "连字符不能开头")
    assertEqual(BillingInstanceID.isValidSlug("工作"), false, "中文不合法")
    assertEqual(BillingInstanceID.isValidSlug(""), false, "空后缀不合法")
    assertEqual(BillingInstanceID.isValidSlug(String(repeating: "a", count: BillingInstanceID.maxSlugLength)),
                true, "上限长度合法")
    assertEqual(BillingInstanceID.isValidSlug(String(repeating: "a", count: BillingInstanceID.maxSlugLength + 1)),
                false, "超长不合法")

    assertEqual(BillingInstanceID.environmentKey(kindID: "opencode-go", slug: nil),
                "BILLING_OPENCODE_GO_API_KEY", "默认实例沿用旧环境变量键")
    assertEqual(BillingInstanceID.environmentKey(kindID: "cursor", slug: "work"),
                "BILLING_CURSOR_WORK_API_KEY", "命名实例环境变量键带后缀")

    let defaultInstance = BillingInstanceID.defaultInstance(kindID: "ollama", title: "Ollama")
    assertEqual(defaultInstance.id, "ollama", "默认实例 id")
    assertEqual(defaultInstance.isDefault, true, "默认实例标记")
    assertEqual(defaultInstance.slug == nil, true, "默认实例无 slug")

    let named = BillingInstanceID.namedInstance(kindID: "cursor", slug: "work", title: "")
    assertEqual(named?.id ?? "", "cursor::work", "命名实例 id")
    assertEqual(named?.title ?? "", "cursor（work）", "未给标题时按 kind + 后缀生成")
    assertEqual(named?.isDefault ?? true, false, "命名实例不是默认实例")
    assertEqual(BillingInstanceID.namedInstance(kindID: "cursor", slug: "BAD", title: "x") == nil, true,
                "非法后缀构造失败")

    let renamed = defaultInstance.renamed("Ollama 工作号")
    assertEqual(renamed.id, "ollama", "改名不动 id（凭据键不受影响）")
    assertEqual(renamed.title, "Ollama 工作号", "标题已更新")
}

// MARK: - 变更与持久化

private func testInstanceMutationAndStore() {
    let kinds = [BillingInstanceKindSeed(kindID: "cursor", title: "Cursor"),
                 BillingInstanceKindSeed(kindID: "codex", title: "Codex")]

    let filled = BillingInstanceMutation.filled([], kinds: kinds)
    assertEqual(filled.map(\.id), ["cursor", "codex"], "空列表补齐默认实例且保持 kind 顺序")
    assertEqual(BillingInstanceMutation.filled(filled, kinds: kinds).map(\.id), ["cursor", "codex"],
                "补齐是幂等的")

    let existing = [BillingInstanceID.defaultInstance(kindID: "cursor", title: "Cursor"),
                    BillingInstance(id: "cursor::work", kindID: "cursor", title: "Cursor（工作）")]
    assertEqual(BillingInstanceMutation.filled(existing, kinds: kinds).map(\.id), ["cursor", "cursor::work", "codex"],
                "已有实例保序，缺失 kind 末尾补默认实例")

    var addedList: [BillingInstance] = []
    do {
        let (list, instance) = try BillingInstanceMutation.adding(filled, kindID: "cursor",
                                                                  slug: "work", title: "Cursor 工作")
        addedList = list
        assertEqual(list.count, 3, "新增后数量 +1")
        assertEqual(instance.id, "cursor::work", "新增实例 id")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "新增命名实例")
    }

    var duplicateError: BillingInstanceError?
    do {
        _ = try BillingInstanceMutation.adding(addedList, kindID: "cursor", slug: "work", title: "重复")
    } catch let error as BillingInstanceError {
        duplicateError = error
    } catch {}
    assertEqual(duplicateError, .duplicateSlug("work"), "重复后缀报 duplicateSlug")

    var invalidError: BillingInstanceError?
    do {
        _ = try BillingInstanceMutation.adding(filled, kindID: "cursor", slug: "BAD", title: "x")
    } catch let error as BillingInstanceError {
        invalidError = error
    } catch {}
    assertEqual(invalidError, .invalidSlug, "非法后缀报 invalidSlug")

    let renamedList = BillingInstanceMutation.renaming(addedList, instanceID: "cursor::work", title: "  工作号  ")
    assertEqual(renamedList.first { $0.id == "cursor::work" }?.title ?? "", "工作号", "改名去首尾空白")
    assertEqual(BillingInstanceMutation.renaming(renamedList, instanceID: "cursor::work", title: "   ")
        .first { $0.id == "cursor::work" }?.title ?? "", "工作号", "空标题被忽略")

    var defaultRemoveError: BillingInstanceError?
    do { _ = try BillingInstanceMutation.removing(renamedList, instanceID: "cursor") }
    catch let error as BillingInstanceError { defaultRemoveError = error } catch {}
    assertEqual(defaultRemoveError, .cannotRemoveDefault, "默认实例不可删")

    var notFoundError: BillingInstanceError?
    do { _ = try BillingInstanceMutation.removing(renamedList, instanceID: "cursor::nope") }
    catch let error as BillingInstanceError { notFoundError = error } catch {}
    assertEqual(notFoundError, .notFound("cursor::nope"), "不存在报 notFound")

    do {
        let remaining = try BillingInstanceMutation.removing(renamedList, instanceID: "cursor::work")
        assertEqual(remaining.count, 2, "命名实例可删")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "删除命名实例")
    }

    let storage = InMemoryStorage()
    let store = BillingInstanceStore(storage: storage)
    assertEqual(store.load().isEmpty, true, "未写过时为空")
    assertEqual(store.ensureDefaults(kinds: kinds).map(\.id), ["cursor", "codex"], "ensureDefaults 首次写入默认实例")
    assertEqual(BillingInstanceStore(storage: storage).load().map(\.id), ["cursor", "codex"],
                "落盘后重新读取一致（JSON 往返）")
    assertEqual(store.ensureDefaults(kinds: kinds).map(\.id), ["cursor", "codex"], "ensureDefaults 幂等")

    do {
        let instance = try store.add(kindID: "cursor", slug: "work", title: "Cursor 工作")
        assertEqual(instance.id, "cursor::work", "存储层新增返回实例")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "存储层新增")
    }
    store.rename(instanceID: "cursor::work", title: "Cursor 工作号")
    assertEqual(store.load().first { $0.id == "cursor::work" }?.title ?? "", "Cursor 工作号", "存储层改名落盘")

    do {
        try store.remove(instanceID: "cursor::work")
        assertEqual(store.load().map(\.id), ["cursor", "codex"], "存储层删除落盘")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "存储层删除")
    }
}

// MARK: - 装饰器

private func testProviderInstanceDecorator() {
    let base = InstanceStubProvider(id: "cursor", displayName: "Cursor",
                                    supportsUsage: false, minimumRefreshInterval: 300)
    let instance = BillingInstanceID.namedInstance(kindID: "cursor", slug: "work", title: "Cursor 工作")!
    let decorated = BillingProviderInstance(base: base, instance: instance)

    assertEqual(decorated.id, "cursor::work", "装饰器 id 是实例标识")
    assertEqual(decorated.displayName, "Cursor 工作", "装饰器展示名是实例标题")
    assertEqual(decorated.symbolName, base.symbolName, "图标名转发")
    assertEqual(decorated.supportsUsage, false, "能力位转发")
    assertEqual(decorated.supportsModelBreakdown, base.supportsModelBreakdown, "模型明细能力位转发")
    assertEqual(decorated.minimumRefreshInterval, 300, "刷新间隔转发")
    assertEqual(decorated.environmentCredentialKey, "BILLING_CURSOR_WORK_API_KEY", "环境变量键按实例生成")

    let defaultDecorated = BillingProviderInstance(
        base: base, instance: BillingInstanceID.defaultInstance(kindID: "cursor", title: "Cursor"))
    assertEqual(defaultDecorated.id, "cursor", "默认实例装饰器 id 仍是 kindID")
    assertEqual(defaultDecorated.environmentCredentialKey, base.environmentCredentialKey,
                "默认实例环境变量键与原实现一致")
}

// MARK: - 注册表

private func testRegistryMultiInstance() {
    let registry = BillingProviderRegistry()
    let cursorDefault = BillingInstanceID.defaultInstance(kindID: "cursor", title: "Cursor")
    let cursorWork = BillingInstanceID.namedInstance(kindID: "cursor", slug: "work", title: "Cursor 工作")!

    registry.register(InstanceStubProvider(id: "cursor", displayName: "Cursor"), instance: cursorDefault)
    registry.register(InstanceStubProvider(id: "cursor", displayName: "Cursor 工作"), instance: cursorWork)
    assertEqual(registry.all.count, 2, "同一 kind 可注册多个实例")
    assertEqual(registry.instances.map(\.id), ["cursor", "cursor::work"], "实例顺序即注册顺序")
    assertEqual(registry.registrations(ofKind: "cursor").count, 2, "按 kind 取全部实例")
    assertEqual(registry.registrations(ofKind: "codex").count, 0, "未注册的 kind 为空")
    assertEqual(registry.instance(id: "cursor::work")?.title ?? "", "Cursor 工作", "按实例标识取实例")
    assertEqual(registry.provider(id: "cursor::work")?.displayName ?? "", "Cursor 工作", "按实例标识取 provider")

    registry.register(InstanceStubProvider(id: "cursor", displayName: "Cursor（替换）"), instance: cursorWork)
    assertEqual(registry.all.count, 2, "同实例重复注册不新增条目")
    assertEqual(registry.provider(id: "cursor::work")?.displayName ?? "", "Cursor（替换）", "同实例注册是替换")

    assertEqual(registry.unregister(instanceID: "cursor::work"), true, "注销存在的实例返回 true")
    assertEqual(registry.unregister(instanceID: "cursor::work"), false, "重复注销返回 false")
    assertEqual(registry.instances.map(\.id), ["cursor"], "注销后只剩默认实例")

    let legacy = BillingProviderRegistry(providers: [InstanceStubProvider(id: "ollama", displayName: "Ollama")])
    assertEqual(legacy.instances.map(\.id), ["ollama"], "旧入口按默认实例登记")
    assertEqual(legacy.registrations.first?.instance.title ?? "", "Ollama", "默认实例标题取 displayName")
}

import Foundation
import NetworkMonitorCore

// MARK: - 贴图右键菜单顺序（分组换序 + 危险项恒在末尾）

/// PinMenuOrderResolver 的完整契约
///
/// 一条一条守着：缺键回落、未知项丢弃、组内换序、跨组拒绝、危险项恒在最后、读路径不写回。
func runPinMenuOrderTests() {
    print("🧪 Testing pin context menu order...")

    let defaults = PinMenuAction.defaultOrder.map(\.rawValue)

    // MARK: 枚举本身的口径

    assertEqual(PinMenuAction.allCases.count, 9, "贴图右键菜单共九项")
    assertEqual(PinMenuAction.defaultOrder, PinMenuAction.allCases,
                "默认顺序即声明顺序（与硬编码菜单时期的顺序一致）")
    assertEqual(PinMenuAction.groupOrder.map(\.rawValue),
                ["output", "transform", "reset", "dismiss"],
                "组顺序固定：复制另存 / 变换 / 重置 / 关闭销毁")

    // 分组：每项都归属且只归属一个组，九项加总等于全体
    let grouped = PinMenuActionGroup.allCases.flatMap { PinMenuAction.defaultOrder(in: $0) }
    assertEqual(Set(grouped), Set(PinMenuAction.allCases), "每个菜单项都有分组，不重不漏")
    assertEqual(PinMenuAction.defaultOrder(in: .output), [.copy, .save], "输出组两项")
    assertEqual(PinMenuAction.defaultOrder(in: .transform),
                [.rotate, .mirrorHorizontal, .mirrorVertical, .thumbnail], "变换组四项")
    assertEqual(PinMenuAction.defaultOrder(in: .reset), [.resetSizeAndAlpha], "重置组一项")
    assertEqual(PinMenuAction.defaultOrder(in: .dismiss), [.close, .destroy], "关闭销毁组两项")

    // 危险组不可排序，其余三组可排序
    assertEqual(PinMenuActionGroup.allCases.filter { $0.isSortable },
                [.output, .transform, .reset], "只有危险组之外的三组可排序")
    assertEqual(PinMenuAction.allCases.filter { $0.isDestructive }, [.close, .destroy],
                "危险项只有关闭（可恢复）与销毁")

    // MARK: 缺键回落

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: nil).map(\.rawValue), defaults,
                "缺键回落 defaultOrder，老配置外观不变")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "").map(\.rawValue), defaults,
                "空串同样回落 defaultOrder")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: " , , ").map(\.rawValue), defaults,
                "只有空白与逗号时回落 defaultOrder")

    // MARK: 未知项丢弃 + 重复项去重

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "bogus,trash").map(\.rawValue), defaults,
                "未知项只丢该项，其余仍按默认顺序")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "save,save,copy,copy").map(\.rawValue),
                PinMenuOrderResolver.resolve(orderRaw: "save,copy").map(\.rawValue),
                "重复项只留第一次出现，不影响最终位置")

    // MARK: 组内换序生效

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "save,copy").map(\.rawValue),
                ["save", "copy", "rotate", "mirrorHorizontal", "mirrorVertical", "thumbnail",
                 "resetSizeAndAlpha", "close", "destroy"],
                "输出组内换序生效，其余组按默认顺序跟随")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "thumbnail,rotate").map(\.rawValue),
                ["copy", "save", "thumbnail", "rotate", "mirrorHorizontal", "mirrorVertical",
                 "resetSizeAndAlpha", "close", "destroy"],
                "变换组内换序生效，组内缺项按默认顺序补尾")

    // MARK: 跨组换序被拒（确定语义：按固定组顺序重新落位）

    let destroyFirst = PinMenuOrderResolver.resolve(orderRaw: "destroy,close,copy,save")
    assertEqual(destroyFirst.map(\.rawValue).suffix(2), ["close", "destroy"],
                "把销毁写进偏好最前，解析后仍在最后两项")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "resetSizeAndAlpha,rotate,copy").map(\.rawValue),
                ["copy", "save", "rotate", "mirrorHorizontal", "mirrorVertical", "thumbnail",
                 "resetSizeAndAlpha", "close", "destroy"],
                "跨组乱序不改变组顺序，只在组内生效")

    // MARK: 危险项恒在最后

    for raw in ["destroy", "destroy,close", "close,destroy", "destroy,copy", "save,destroy,copy"] {
        let order = PinMenuOrderResolver.resolve(orderRaw: raw)
        assertEqual(order.map(\.rawValue).suffix(2), ["close", "destroy"],
                    "偏好「\(raw)」下危险项恒在最后两项")
        assertEqual(order.filter { $0.isDestructive }.map(\.rawValue), ["close", "destroy"],
                    "偏好「\(raw)」下危险组内部顺序不被改写")
    }

    // MARK: 移动口径（设置页上移 / 下移）

    assertEqual(PinMenuOrderResolver.moved(defaults, id: "copy", offset: 1),
                ["save", "copy"] + Array(defaults.suffix(7)),
                "输出组内下移：复制与另存为互换")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "save", offset: 1), defaults,
                "跨组移动被拒：另存为不会掉进变换组")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "rotate", offset: -1), defaults,
                "跨组移动被拒：旋转不会上浮到输出组")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "destroy", offset: -1), defaults,
                "销毁不能被上移到关闭之前")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "close", offset: 1), defaults,
                "关闭不能被下移到销毁之后")

    // 按钮启用判据与移动同源
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 0, offset: 1), true,
                "输出组首项可下移")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 1, offset: 1), false,
                "输出组末项不能下移（跨组）")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 6, offset: -1), false,
                "变换组首项不能上移（跨组）")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 7, offset: -1), false,
                "危险组里关闭也不能上移（危险组整体不可排序）")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 8, offset: -1), false,
                "销毁的上移按钮恒禁用")

    // MARK: 偏好读写（读路径不写回）

    let storage = InMemoryStorage()
    // 缺键读：返回默认顺序，且不往存储里写任何东西
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue), defaults,
                "存储里没有顺序键时读回落默认顺序")
    assertEqual(storage.object(forKey: PinMenuPreferenceKey.contextMenuOrder) == nil, true,
                "读路径不写回：缺键读完仍然是缺键")

    // 写偏好即生效：组内换序读回来仍是换过的顺序
    let swapped = PinMenuOrderResolver.resolve(orderRaw: "save,copy")
    PinMenuOrderResolver.save(swapped, storage: storage)
    assertEqual(storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder),
                SettingsOrderCoding.encode(swapped.map(\.rawValue)),
                "save 落盘的正是归一后的完整九项顺序")
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue).prefix(2), ["save", "copy"],
                "写偏好即生效：读回仍是另存为在复制之前")

    // 手工写坏的数据：读的时候纠正，但不动原始键（读路径不写回）
    storage.set("destroy,bogus,copy", forKey: PinMenuPreferenceKey.contextMenuOrder)
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue).suffix(2), ["close", "destroy"],
                "手工写坏的顺序读出来仍是危险项在最后")
    assertEqual(storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder), "destroy,bogus,copy",
                "读路径不回写：坏数据原样留在存储里")

    // 恢复默认 = 删键
    PinMenuOrderResolver.save(PinMenuOrderResolver.resolve(orderRaw: "thumbnail,rotate"), storage: storage)
    PinMenuOrderResolver.reset(storage: storage)
    assertEqual(storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder), nil,
                "恢复默认删掉顺序键")
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue), defaults,
                "删键后读回落默认顺序")

    // MARK: 通用可排序卡片的分组口径（movePolicy）

    let policy = PinMenuOrderResolver.movePolicy
    assertEqual(policy.normalize(["save", "copy"], defaults, defaults),
                ["save", "copy", "rotate", "mirrorHorizontal", "mirrorVertical", "thumbnail",
                 "resetSizeAndAlpha", "close", "destroy"],
                "卡片口径归一与菜单口径同源（组顺序固定）")
    assertEqual(policy.canMove(defaults, 0, 1), true, "卡片口径：输出组首项可下移")
    assertEqual(policy.canMove(defaults, 1, 1), false, "卡片口径：跨组下移被拒")
    assertEqual(policy.move(defaults, "destroy", -1), defaults, "卡片口径：危险项不动")
    // 默认口径（其余三张排序卡）仍是整列自由换序，不被本轮改动影响
    assertEqual(SettingsOrderMovePolicy.free.canMove(["a", "b"], 0, 1), true,
                "默认口径仍是整列自由换序")
    assertEqual(SettingsOrderMovePolicy.free.move(["a", "b"], "b", -1), ["b", "a"],
                "默认口径下任意相邻两项仍可互换")

    print("✅ 贴图菜单顺序测试通过")
}

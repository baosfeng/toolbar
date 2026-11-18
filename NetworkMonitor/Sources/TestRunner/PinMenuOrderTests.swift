import Foundation
import NetworkMonitorCore

// MARK: - 贴图右键菜单顺序（九项全部放开可调）

/// PinMenuOrderResolver 的完整契约
///
/// 一条一条守着：缺键回落、未知项丢弃、跨组换序生效、危险项位置由顺序键决定、
/// 旧偏好（组内顺序）仍能读、分隔线按最终顺序落在语义分组变化处、读路径不写回。
func runPinMenuOrderTests() {
    print("🧪 Testing pin context menu order...")

    let defaults = PinMenuAction.defaultOrder.map(\.rawValue)

    // MARK: 枚举本身的口径

    assertEqual(PinMenuAction.allCases.count, 9, "贴图右键菜单共九项")
    assertEqual(PinMenuAction.defaultOrder, PinMenuAction.allCases,
                "默认顺序即声明顺序（与硬编码菜单时期的顺序一致）")

    // 分组：每项都归属且只归属一个组，九项加总等于全体
    let grouped = PinMenuActionGroup.allCases.flatMap { PinMenuAction.defaultOrder(in: $0) }
    assertEqual(Set(grouped), Set(PinMenuAction.allCases), "每个菜单项都有分组，不重不漏")
    assertEqual(PinMenuAction.defaultOrder(in: .output), [.copy, .save], "输出组两项")
    assertEqual(PinMenuAction.defaultOrder(in: .transform),
                [.rotate, .mirrorHorizontal, .mirrorVertical, .thumbnail], "变换组四项")
    assertEqual(PinMenuAction.defaultOrder(in: .reset), [.resetSizeAndAlpha], "重置组一项")
    assertEqual(PinMenuAction.defaultOrder(in: .dismiss), [.close, .destroy], "关闭销毁组两项")

    // 危险项只有关闭与销毁；分组不再是排序边界（没有可排序 / 不可排序之分）
    assertEqual(PinMenuAction.allCases.filter { $0.isDestructive }, [.close, .destroy],
                "危险项只有关闭（可恢复）与销毁")
    assertEqual(PinMenuActionGroup.allCases.map(\.title),
                ["复制与另存为", "变换", "重置", "关闭与销毁"],
                "分组名只用于副标题与说明，不再限制排序")

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

    // MARK: 组内换序生效（旧偏好形态，老用户换过的组内顺序仍按原样读回）

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "save,copy").map(\.rawValue),
                ["save", "copy", "rotate", "mirrorHorizontal", "mirrorVertical", "thumbnail",
                 "resetSizeAndAlpha", "close", "destroy"],
                "输出组内换序照旧生效，缺项按默认顺序补尾")
    // 旧偏好里只写了组内两项的串：已写项按原相对顺序在前，缺项按默认顺序补尾。
    // 组内换序在新规则下依然成立，只是组与组之间不再有强制落位。
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "thumbnail,rotate").map(\.rawValue),
                ["thumbnail", "rotate", "copy", "save", "mirrorHorizontal", "mirrorVertical",
                 "resetSizeAndAlpha", "close", "destroy"],
                "组内换序照旧生效，缺项按默认顺序补尾")

    // MARK: 跨组换序生效（本轮放开的核心语义）

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "destroy,close,copy,save").map(\.rawValue).prefix(4),
                ["destroy", "close", "copy", "save"],
                "把销毁写进偏好最前，菜单里就排在最前（位置由顺序键决定）")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "resetSizeAndAlpha,rotate,copy").map(\.rawValue).prefix(3),
                ["resetSizeAndAlpha", "rotate", "copy"],
                "跨组乱序同样生效：重置、旋转、复制按偏好顺序排列")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "thumbnail,copy,destroy,save").map(\.rawValue).prefix(4),
                ["thumbnail", "copy", "destroy", "save"],
                "变换 / 输出 / 危险三组交叉换序全部生效")

    // MARK: 危险项位置由顺序键决定，不再恒在末尾

    for raw in ["destroy", "destroy,close", "close,destroy", "destroy,copy", "save,destroy,copy"] {
        let order = PinMenuOrderResolver.resolve(orderRaw: raw)
        let head = SettingsOrderCoding.decode(raw)
        assertEqual(order.map(\.rawValue).prefix(head.count), ArraySlice(head),
                    "偏好「\(raw)」下前 \(head.count) 项逐位一致（危险项不再被移到末尾）")
    }
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "destroy").first, .destroy,
                "只写一项时销毁就在第一位")

    // MARK: 九项任意排列：齐全、不重不漏

    let permutations: [[String]] = [
        defaults.reversed(),
        ["destroy", "thumbnail", "save", "rotate", "close", "copy",
         "resetSizeAndAlpha", "mirrorVertical", "mirrorHorizontal"],
        ["rotate", "copy", "destroy", "save", "mirrorHorizontal", "close",
         "thumbnail", "resetSizeAndAlpha", "mirrorVertical"],
        ["close", "resetSizeAndAlpha", "mirrorVertical", "mirrorHorizontal",
         "rotate", "thumbnail", "save", "copy", "destroy"]
    ]
    for permutation in permutations {
        let order = PinMenuOrderResolver.resolve(orderRaw: SettingsOrderCoding.encode(permutation))
        assertEqual(order.count, 9, "任意排列都解析出九项")
        assertEqual(order.map(\.rawValue), permutation, "任意排列逐位保留，不被分组重排")
        assertEqual(Set(order), Set(PinMenuAction.allCases), "九项齐全不重不漏")
    }

    // 偏序（只写了前几项）时缺失项按默认顺序补尾，仍是九项齐全
    let partial = PinMenuOrderResolver.resolve(orderRaw: "destroy,copy")
    assertEqual(partial.count, 9, "只写两项也补齐九项")
    assertEqual(Array(partial.map(\.rawValue).prefix(2)), ["destroy", "copy"], "已写的两项保持原位")
    assertEqual(Set(partial), Set(PinMenuAction.allCases), "补齐后不重不漏")

    // MARK: 分隔线按最终顺序落在语义分组变化处

    let defaultSeparators = PinMenuDivider.leadingSeparators(for: PinMenuAction.defaultOrder)
    assertEqual(defaultSeparators.count, 9, "分隔线判据与菜单项一一对应")
    assertEqual(defaultSeparators, [false, false, true, false, false, false, true, true, false],
                "默认顺序下：第 3 / 7 / 8 项之前各一条分隔线（首项之前不画）")
    assertEqual(PinMenuDivider.leadingSeparators(for: [.copy, .save]), [false, false],
                "同组相邻不画分隔线")
    assertEqual(PinMenuDivider.leadingSeparators(for: [.copy, .destroy]), [false, true],
                "跨组相邻在第二项之前画一条")
    assertEqual(PinMenuDivider.leadingSeparators(for: [.destroy]), [false],
                "单一项之前不画分隔线")
    assertEqual(PinMenuDivider.leadingSeparators(for: []).isEmpty, true, "空菜单没有分隔线")
    // 跨组连续换序：分组变化处才断，不会画出连续两条空段
    let mixed: [PinMenuAction] = [.thumbnail, .copy, .destroy, .save, .rotate]
    assertEqual(PinMenuDivider.leadingSeparators(for: mixed), [false, true, true, true, true],
                "跨组换序后按相邻项分组变化插入分隔线")
    let clustered: [PinMenuAction] = [.rotate, .mirrorHorizontal, .thumbnail, .copy, .save]
    assertEqual(PinMenuDivider.leadingSeparators(for: clustered), [false, false, false, true, false],
                "分组聚在一起时只在真正的边界断一次")

    // MARK: 移动口径（设置页上移 / 下移，跨组同样可用）

    assertEqual(PinMenuOrderResolver.moved(defaults, id: "copy", offset: 1),
                ["save", "copy"] + Array(defaults.suffix(7)),
                "输出组内下移：复制与另存为互换")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "save", offset: 1),
                ["copy", "rotate", "save"] + Array(defaults.suffix(6)),
                "跨组下移生效：另存为越过边界落到变换组首位")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "rotate", offset: -1),
                ["copy", "rotate", "save"] + Array(defaults.suffix(6)),
                "跨组上移生效：旋转上浮到输出组末尾")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "destroy", offset: -1),
                Array(defaults.prefix(7)) + ["destroy", "close"],
                "销毁能上移到关闭之前（危险项不再被钉住）")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "close", offset: 1),
                Array(defaults.prefix(7)) + ["destroy", "close"],
                "关闭也能下移到销毁之后")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "copy", offset: -1), defaults,
                "首项上移越界，原样返回")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "destroy", offset: 1), defaults,
                "末项下移越界，原样返回")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "nope", offset: 1), defaults,
                "未知 id 原样返回")

    // 按钮启用判据与移动同源：只有越界才禁用
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 0, offset: 1), true,
                "首项可下移")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 0, offset: -1), false,
                "首项不能上移（越界）")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 1, offset: 1), true,
                "组末项也能下移（跨组允许）")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 6, offset: -1), true,
                "组首项也能上移（跨组允许）")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 7, offset: -1), true,
                "关闭能上移")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 8, offset: -1), true,
                "销毁的上移按钮同样可用")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 8, offset: 1), false,
                "末项下移越界")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: 99, offset: 1), false,
                "越界下标返回 false")

    // MARK: 偏好读写（读路径不写回）

    let storage = InMemoryStorage()
    // 缺键读：返回默认顺序，且不往存储里写任何东西
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue), defaults,
                "存储里没有顺序键时读回落默认顺序")
    assertEqual(storage.object(forKey: PinMenuPreferenceKey.contextMenuOrder) == nil, true,
                "读路径不写回：缺键读完仍然是缺键")

    // 写偏好即生效：跨组换序读回来仍是换过的顺序
    let swapped = PinMenuOrderResolver.resolve(orderRaw: "destroy,save,copy,rotate")
    PinMenuOrderResolver.save(swapped, storage: storage)
    assertEqual(storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder),
                SettingsOrderCoding.encode(swapped.map(\.rawValue)),
                "save 落盘的正是归一后的完整九项顺序")
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue).prefix(4),
                ["destroy", "save", "copy", "rotate"],
                "写偏好即生效：跨组换序读回原样")

    // 旧偏好（组内换序时代写下的顺序串，分组边界固定）读出来逐位不变
    let legacy = "save,copy,thumbnail,rotate,mirrorHorizontal,mirrorVertical,resetSizeAndAlpha,close,destroy"
    storage.set(legacy, forKey: PinMenuPreferenceKey.contextMenuOrder)
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue),
                SettingsOrderCoding.decode(legacy),
                "旧偏好（组内顺序）逐位读回，升级不改用户已有排列")

    // 手工写坏的数据：读的时候纠正，但不动原始键（读路径不写回）
    storage.set("destroy,bogus,copy", forKey: PinMenuPreferenceKey.contextMenuOrder)
    let broken = PinMenuOrderResolver.load(storage: storage)
    assertEqual(broken.count, 9, "坏数据读出来仍补齐九项")
    assertEqual(Array(broken.map(\.rawValue).prefix(2)), ["destroy", "copy"],
                "坏数据里的已知项按原顺序保留")
    assertEqual(storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder), "destroy,bogus,copy",
                "读路径不回写：坏数据原样留在存储里")

    // 恢复默认 = 删键
    PinMenuOrderResolver.save(PinMenuOrderResolver.resolve(orderRaw: "thumbnail,rotate"), storage: storage)
    PinMenuOrderResolver.reset(storage: storage)
    assertEqual(storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder), nil,
                "恢复默认删掉顺序键")
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue), defaults,
                "删键后读回落默认顺序")

    // MARK: 通用可排序卡片的口径（movePolicy）

    let policy = PinMenuOrderResolver.movePolicy
    assertEqual(policy.normalize(["save", "copy"], defaults, defaults),
                ["save", "copy", "rotate", "mirrorHorizontal", "mirrorVertical", "thumbnail",
                 "resetSizeAndAlpha", "close", "destroy"],
                "卡片口径归一与菜单口径同源（缺项补尾）")
    assertEqual(policy.canMove(defaults, 0, 1), true, "卡片口径：首项可下移")
    assertEqual(policy.canMove(defaults, 1, 1), true, "卡片口径：跨组下移可用")
    assertEqual(policy.move(defaults, "destroy", -1),
                Array(defaults.prefix(7)) + ["destroy", "close"],
                "卡片口径：危险项也能上移")
    assertEqual(policy.move(defaults, "copy", -1), defaults, "卡片口径：越界仍原样返回")
    // 默认口径（其余三张排序卡）行为不变
    assertEqual(SettingsOrderMovePolicy.free.canMove(["a", "b"], 0, 1), true,
                "默认口径仍是整列自由换序")
    assertEqual(SettingsOrderMovePolicy.free.move(["a", "b"], "b", -1), ["b", "a"],
                "默认口径下任意相邻两项仍可互换")

    print("✅ 贴图菜单顺序测试通过")
}

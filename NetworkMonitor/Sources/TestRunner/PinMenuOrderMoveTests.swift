import Foundation
import NetworkMonitorCore

// MARK: - 贴图右键菜单：分隔线 / 移动 / 偏好读写

/// 与 PinMenuOrderTests 同属「贴图右键菜单顺序」这一族，按职责拆成两份守住单文件体积门禁：
/// 那份管归一化口径（缺键回落 / 未知项丢弃 / 新项补尾），这份管落位与读写
/// （分隔线在哪断、上移下移、偏好读写不写回）。
func runPinMenuOrderMoveTests() {
    print("🧪 Testing pin context menu order (move & storage)...")

    let defaults = PinMenuAction.defaultOrder.map(\.rawValue)
    let allCount = PinMenuAction.allCases.count

    // MARK: 分隔线按最终顺序落在语义分组变化处

    let defaultSeparators = PinMenuDivider.leadingSeparators(for: PinMenuAction.defaultOrder)
    assertEqual(defaultSeparators.count, allCount, "分隔线判据与菜单项一一对应")
    assertEqual(defaultSeparators,
                [false, false, true, false, false, false, false, false, true, true, true, false],
                "默认顺序下：第 3 项（旋转）/ 灰度前（背景）/ 重置前 / 关闭前各一条分隔线")
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
    let clustered: [PinMenuAction] = [.rotate, .mirrorHorizontal, .grayscale, .invert, .thumbnail,
                                      .copy, .save]
    assertEqual(PinMenuDivider.leadingSeparators(for: clustered),
                [false, false, false, false, false, true, false],
                "灰度 / 反色留在变换组内部，不额外断线")

    // MARK: 移动口径（设置页上移 / 下移，跨组同样可用）

    assertEqual(PinMenuOrderResolver.moved(defaults, id: "copy", offset: 1),
                ["save", "copy"] + Array(defaults.dropFirst(2)),
                "输出组内下移：复制与另存为互换")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "grayscale", offset: -1),
                ["copy", "save", "rotate", "mirrorHorizontal", "grayscale", "mirrorVertical",
                 "invert", "thumbnail", "boardBackground", "resetSizeAndAlpha", "close", "destroy"],
                "灰度能上移到镜像之前（新项同样可自由换序）")
    assertEqual(PinMenuOrderResolver.moved(defaults, id: "boardBackground", offset: 1),
                Array(defaults.prefix(8)) + ["resetSizeAndAlpha", "boardBackground"]
                    + Array(defaults.dropFirst(10)),
                "棋盘底能下移到重置之后")
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
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: allCount - 1, offset: -1), true,
                "新增项之后，销毁仍有上移空间")
    assertEqual(PinMenuOrderResolver.canMove(defaults, index: allCount - 1, offset: 1), false,
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
                "save 落盘的正是归一后的完整顺序")
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue).prefix(4),
                ["destroy", "save", "copy", "rotate"],
                "写偏好即生效：跨组换序读回原样")

    // 旧偏好（组内换序时代写下的顺序串，只有原九项）读出来逐位不变、新项补尾
    let legacy = "save,copy,thumbnail,rotate,mirrorHorizontal,mirrorVertical,resetSizeAndAlpha,close,destroy"
    storage.set(legacy, forKey: PinMenuPreferenceKey.contextMenuOrder)
    assertEqual(PinMenuOrderResolver.load(storage: storage).map(\.rawValue),
                SettingsOrderCoding.decode(legacy) + ["grayscale", "invert", "boardBackground"],
                "旧偏好逐位读回，升级不改用户已有排列；新增三项只在末尾追加")

    // 手工写坏的数据：读的时候纠正，但不动原始键（读路径不写回）
    storage.set("destroy,bogus,copy", forKey: PinMenuPreferenceKey.contextMenuOrder)
    let broken = PinMenuOrderResolver.load(storage: storage)
    assertEqual(broken.count, allCount, "坏数据读出来仍补齐全部菜单项")
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
                ["save", "copy"] + Array(defaults.dropFirst(2)),
                "卡片口径归一与菜单口径同源（缺项补尾）")
    assertEqual(policy.canMove(defaults, 0, 1), true, "卡片口径：首项可下移")
    assertEqual(policy.canMove(defaults, 1, 1), true, "卡片口径：跨组下移可用")
    assertEqual(policy.move(defaults, "grayscale", -1),
                ["copy", "save", "rotate", "mirrorHorizontal", "grayscale", "mirrorVertical",
                 "invert", "thumbnail", "boardBackground", "resetSizeAndAlpha", "close", "destroy"],
                "卡片口径：新项灰度也能上移")
    assertEqual(policy.move(defaults, "copy", -1), defaults, "卡片口径：越界仍原样返回")
    // 默认口径（其余三张排序卡）行为不变
    assertEqual(SettingsOrderMovePolicy.free.canMove(["a", "b"], 0, 1), true,
                "默认口径仍是整列自由换序")
    assertEqual(SettingsOrderMovePolicy.free.move(["a", "b"], "b", -1), ["b", "a"],
                "默认口径下任意相邻两项仍可互换")

    print("✅ 贴图菜单顺序（落位与读写）测试通过")
}

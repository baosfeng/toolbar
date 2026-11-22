import Foundation
import NetworkMonitorCore

// MARK: - 贴图右键菜单顺序（整列全部放开可调）

/// PinMenuOrderResolver 的完整契约
///
/// 一条一条守着：缺键回落、未知项丢弃、跨组换序生效、危险项位置由顺序键决定、
/// 旧偏好（组内顺序）仍能读、分隔线按最终顺序落在语义分组变化处、读路径不写回。
/// 另有一条硬约束：新增项（灰度 / 反色 / 棋盘底）对老偏好只是「缺失项」，
/// 用户已排好的前九项逐位不动，新功能只追加在菜单尾部。
func runPinMenuOrderTests() {
    print("🧪 Testing pin context menu order...")

    let defaults = PinMenuAction.defaultOrder.map(\.rawValue)
    let allCount = PinMenuAction.allCases.count

    // MARK: 枚举本身的口径

    assertEqual(allCount, 12, "贴图右键菜单共十二项（原九项 + 灰度 / 反色 / 棋盘底）")
    assertEqual(PinMenuAction.defaultOrder, PinMenuAction.allCases,
                "默认顺序即声明顺序")

    // 分组：每项都归属且只归属一个组，加总等于全体
    let grouped = PinMenuActionGroup.allCases.flatMap { PinMenuAction.defaultOrder(in: $0) }
    assertEqual(Set(grouped), Set(PinMenuAction.allCases), "每个菜单项都有分组，不重不漏")
    assertEqual(PinMenuAction.defaultOrder(in: .output), [.copy, .save], "输出组两项")
    assertEqual(PinMenuAction.defaultOrder(in: .transform),
                [.rotate, .mirrorHorizontal, .mirrorVertical, .grayscale, .invert, .thumbnail],
                "变换组六项：旋转 / 镜像 / 灰度 / 反色 / 缩略图（灰度与反色紧跟镜像）")
    assertEqual(PinMenuAction.defaultOrder(in: .background), [.boardBackground], "背景组一项")
    assertEqual(PinMenuAction.defaultOrder(in: .reset), [.resetSizeAndAlpha], "重置组一项")
    assertEqual(PinMenuAction.defaultOrder(in: .dismiss), [.close, .destroy], "关闭销毁组两项")

    // 危险项只有关闭与销毁；分组不再是排序边界
    assertEqual(PinMenuAction.allCases.filter { $0.isDestructive }, [.close, .destroy],
                "危险项只有关闭（可恢复）与销毁")
    assertEqual(PinMenuActionGroup.allCases.map(\.title),
                ["复制与另存为", "变换", "背景", "重置", "关闭与销毁"],
                "分组名只用于副标题与说明，不再限制排序")
    // 新项的分组归属：灰度 / 反色进「变换」，棋盘底自成一「背景」组
    assertEqual(PinMenuAction.grayscale.group, .transform, "灰度归变换组")
    assertEqual(PinMenuAction.invert.group, .transform, "反色归变换组")
    assertEqual(PinMenuAction.boardBackground.group, .background, "棋盘底归背景组")

    // MARK: 缺键回落

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: nil).map(\.rawValue), defaults,
                "缺键回落 defaultOrder，老配置外观不变")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "").map(\.rawValue), defaults,
                "空串同样回落 defaultOrder")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: " , , ").map(\.rawValue), defaults,
                "只有空白与逗号时回落 defaultOrder")

    // MARK: 老偏好（只有原来的九项）+ 新增三项：前九项逐位不动，新项补到末尾

    let legacies = [
        "save,copy,thumbnail,rotate,mirrorHorizontal,mirrorVertical,resetSizeAndAlpha,close,destroy",
        "destroy,close,copy,save,rotate,mirrorHorizontal,mirrorVertical,thumbnail,resetSizeAndAlpha",
        "copy,save,rotate,mirrorHorizontal,mirrorVertical,thumbnail,resetSizeAndAlpha,close,destroy"
    ]
    for legacy in legacies {
        let head = SettingsOrderCoding.decode(legacy)
        let resolution = PinMenuOrderResolver.resolve(orderRaw: legacy)
        assertEqual(resolution.map(\.rawValue).prefix(head.count), ArraySlice(head),
                    "老偏好「\(head.count) 项」的前 \(head.count) 项逐位不动（新项不插队）")
        assertEqual(Set(resolution.map(\.rawValue).suffix(allCount - head.count)),
                    ["grayscale", "invert", "boardBackground"],
                    "新增的灰度 / 反色 / 棋盘底只补在菜单末尾")
    }

    // MARK: 未知项丢弃 + 重复项去重

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "bogus,trash").map(\.rawValue), defaults,
                "未知项只丢该项，其余仍按默认顺序")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "save,save,copy,copy").map(\.rawValue),
                PinMenuOrderResolver.resolve(orderRaw: "save,copy").map(\.rawValue),
                "重复项只留第一次出现，不影响最终位置")

    // MARK: 组内换序生效（旧偏好形态，老用户换过的组内顺序仍按原样读回）

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "save,copy").map(\.rawValue),
                ["save", "copy"] + Array(defaults.dropFirst(2)),
                "输出组内换序照旧生效，缺项按默认顺序补尾")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "thumbnail,rotate").map(\.rawValue),
                ["thumbnail", "rotate", "copy", "save", "mirrorHorizontal", "mirrorVertical",
                 "grayscale", "invert", "boardBackground", "resetSizeAndAlpha", "close", "destroy"],
                "组内换序照旧生效，缺项按默认顺序补尾")

    // MARK: 跨组换序生效（本轮放开的核心语义）

    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "destroy,close,copy,save").map(\.rawValue).prefix(4),
                ["destroy", "close", "copy", "save"],
                "把销毁写进偏好最前，菜单里就排在最前（位置由顺序键决定）")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "resetSizeAndAlpha,rotate,copy").map(\.rawValue).prefix(3),
                ["resetSizeAndAlpha", "rotate", "copy"],
                "跨组乱序同样生效：重置、旋转、复制按偏好顺序排列")
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "grayscale,thumbnail,copy,destroy").map(\.rawValue).prefix(4),
                ["grayscale", "thumbnail", "copy", "destroy"],
                "新项同样可以跨组排到最前，不受分组约束")

    // MARK: 危险项位置由顺序键决定，不再恒在末尾

    for raw in ["destroy", "destroy,close", "close,destroy", "destroy,copy", "save,destroy,copy"] {
        let order = PinMenuOrderResolver.resolve(orderRaw: raw)
        let head = SettingsOrderCoding.decode(raw)
        assertEqual(order.map(\.rawValue).prefix(head.count), ArraySlice(head),
                    "偏好「\(raw)」下前 \(head.count) 项逐位一致（危险项不再被移到末尾）")
    }
    assertEqual(PinMenuOrderResolver.resolve(orderRaw: "destroy").first, .destroy,
                "只写一项时销毁就在第一位")

    // MARK: 任意排列：齐全、不重不漏

    let permutations: [[PinMenuAction]] = [
        [PinMenuAction](PinMenuAction.allCases.reversed()),
        [.destroy, .thumbnail, .save, .rotate, .close, .copy,
         .resetSizeAndAlpha, .mirrorVertical, .mirrorHorizontal, .invert, .boardBackground, .grayscale],
        [.grayscale, .copy, .destroy, .save, .mirrorHorizontal, .close,
         .thumbnail, .resetSizeAndAlpha, .mirrorVertical, .invert, .boardBackground, .rotate]
    ]
    for permutation in permutations {
        let ids = permutation.map(\.rawValue)
        let order = PinMenuOrderResolver.resolve(orderRaw: SettingsOrderCoding.encode(ids))
        assertEqual(order.count, allCount, "任意排列都解析出全部菜单项")
        assertEqual(order.map(\.rawValue), ids, "任意排列逐位保留，不被分组重排")
        assertEqual(Set(order), Set(PinMenuAction.allCases), "全部菜单项齐全不重不漏")
    }

    // 偏序（只写了前几项）时缺失项按默认顺序补尾，仍是全部菜单项齐全
    let partial = PinMenuOrderResolver.resolve(orderRaw: "destroy,copy")
    assertEqual(partial.count, allCount, "只写两项也补齐全部菜单项")
    assertEqual(Array(partial.map(\.rawValue).prefix(2)), ["destroy", "copy"], "已写的两项保持原位")
    assertEqual(Set(partial), Set(PinMenuAction.allCases), "补齐后不重不漏")

    print("✅ 贴图菜单顺序测试通过")
}

import Foundation

// MARK: - 「按项目 / 按模型」二级页的范围口径文案（Core 纯函数派生，视图只透传）

/// 二级页分布页（按项目 / 按模型）用到的全部文案
///
/// 存在理由：主面板两张卡已跟随范围（今日 / 近 7 天 / 近 30 天），二级页却仍写
/// 「累计口径」「不能按今日 / 近 7 天过滤」，同一屏两套说法，用户直接反馈
/// 「上面的数据和下面的数据对不上」。文案统一在 Core 派生，视图只取值，
/// TestRunner 才能对文案本身做断言（视图里拼字符串就测不到了）。
package struct TokenDistroCopy {
    /// 当前范围名（「今日」/「近 7 天」/「近 30 天」）
    package let rangeTitle: String
    /// 按项目页：面包屑右侧说明
    package let projectsCrumbMeta: String
    /// 按模型页：面包屑右侧说明
    package let modelsCrumbMeta: String
    /// 按项目页：Hero 副标题
    package let projectsHeroSub: String
    /// 按模型页：Hero 副标题
    package let modelsHeroSub: String
    /// 按项目页：底部口径说明卡
    package let projectsNote: String
    /// 按模型页：底部口径说明卡
    package let modelsNote: String
    /// 按项目页：占比条的读屏文案
    package let projectsBarAccessibility: String
    /// 按模型页：占比条的读屏文案
    package let modelsBarAccessibility: String
    /// 按模型页「命中率与 provider」卡的头部说明
    package let hitCardMeta: String

    /// 缓存命中页底部口径说明
    ///
    /// 曾写「逐桶命中率跟随主面板范围」，而实现里逐桶取的是 todayBuckets（固定今日 24 桶），
    /// 说明与实现不符。现按实现判决：主数值今日、走势与均值固定 30 天、逐桶固定今日，
    /// 三块各自固定口径，都不随主面板范围切换。放在 Core 才能被 TestRunner 直接断言。
    package static let cacheNote = "口径：命中率只看「缓存读」与「未缓存输入」两项，输出不进分母"
        + "（输出不可能被缓存）。本页三块各自固定口径、都不随主面板范围切换："
        + "主数值取今日、走势与均值固定 30 天、逐桶命中率固定今日 24 桶，不共用同一个数。"
        + "没有单价表，所以不给金额折算。"

    /// 单桶详情页（历史日）底部口径说明 —— 静态文案，但要与「跟随范围」的现状一致：
    /// 这里曾写「项目与模型仍是累计口径，不随窗口变化」，与主面板已矛盾的表述必须去掉。
    package static let dayBucketNote = "口径：历史日仅天粒度——小时拆分只有今日与昨日可得，"
        + "所以本页只给日汇总 + 与前一日对比，不画小时柱。"
        + "项目与模型跟随主面板范围（今日 / 近 7 天 / 近 30 天），切换范围即换数据。"
}

extension TokenDerive {

    /// 分布页文案 —— 一眼看清「跟谁同口径」与「占比分母是什么」
    ///
    /// 分母口径与 projectRows / modelRows 的实现一致：该窗口内全部项目 / 模型的合计，
    /// 不是列表里 TopN 行的求和（后者会让每行占比虚高）。
    package static func distroCopy(range: TokenRange) -> TokenDistroCopy {
        let title = range.title
        return TokenDistroCopy(
            rangeTitle: title,
            projectsCrumbMeta: title + "口径",
            modelsCrumbMeta: title + "口径",
            projectsHeroSub: title + " tok · 会话数 · 排名 · 与主面板同范围",
            modelsHeroSub: "provider + model 二元组 · " + title + " tok 与命中率 · 与主面板同范围",
            projectsNote: "口径：项目按会话 cwd 归属聚合，" + title + " 窗口内按内容键去重"
                + "（同一项目的多版本会话文件已合并）；占比分母是该窗口内全部项目的合计，"
                + "不是列表里 TopN 行的求和。项目与模型跟随主面板范围，切换范围即换数据，"
                + "与首屏 Hero 同一窗口。",
            modelsNote: "口径：模型维度同样跟随主面板范围（" + title + "）；"
                + "占比分母是该窗口内全部模型的合计。命中率按该模型的缓存读 "
                + "÷（缓存读 + 未缓存输入）逐模型算。同 provider 不同 model 分行，不合并。",
            // 占比条读屏文案唯一来源是 TokenDistroDimension（主面板与二级页共用同一句），
            // 这里只是转手，避免两处各写一份「按项目 X 占比条」而逐渐漂移
            projectsBarAccessibility: TokenDistroDimension.projects.barAccessibility(range: range),
            modelsBarAccessibility: TokenDistroDimension.models.barAccessibility(range: range),
            hitCardMeta: title
        )
    }
}

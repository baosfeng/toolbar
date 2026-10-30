import AppKit

// MARK: - 系统页卡片 toolTip 文案

/// 系统页各卡的 `toolTip` 文案 — 界面只留数值与 ≤4 字标签，口径 / 来源 / 不可得原因全部走这里
///
/// 集中一处：卡片装配与历史刷新两条链路要写同一份说明，散落两处必然走样
/// （此前温度卡 toolTip 还留着「取自 SMC」，实际已改走 IOHID）。
enum SystemPaneTip {

    /// CPU 卡：总占用口径 + 用户态 / 系统态双序列 + 每核柱阵
    static let cpu = "CPU 利用率 = 1 − 空闲占比；USER + SYSTEM + NICE + IRQ ticks 差分 ÷ 全部 ticks（含 idle），"
        + "1 秒采样。图上浅蓝面积 = 用户态（应用与用户进程），其上深色带 = 系统态（内核与驱动），"
        + "带顶线为总占用；两段同处 0…100 刻度，带厚即系统态真实占比，不是量程换算。"
        + "右侧每核柱阵按 P 核在前、E 核在后排列，悬停可看单核占用"

    /// GPU 卡：利用率 + 显存
    static let gpu = "GPU 利用率为设备性能计数器读数；折线为最近 60 秒趋势；"
        + "统一内存机型无显存总量，只显示已用显存（取不到时显示「—」）"

    /// 内存卡：四段口径（已用不含 inactive）+ 压力 + 换出量
    static let memory = "物理内存四段（按物理内存占比）：深蓝 = 内核 wired（不可换出、不可压缩，源 wire_count）、"
        + "主蓝 = 活跃 active（应用页，源 active_count）、浅蓝 = 压缩 compressed（压缩器实际物理占用，"
        + "源 compressor_page_count，是压缩后的物理占用而非压缩前体量）、空白 = 空闲 free；"
        + "四段之和等于物理内存总量，已用 = 活跃 + 内核 + 压缩，不含 inactive（可被系统随时回收，"
        + "计进去读数会长期偏高）。圆点为系统内存压力（绿正常、黄警告、红严重，"
        + "源 kern.memorystatus_vm_pressure_level）；右下「交换」为当前 swap 占用（源 sysctl vm.swapusage）"

    /// 磁盘卡：容量 + 字节速率 + IOPS 虚线 + 繁忙度
    ///
    /// - Parameter busyPeakPercent: 近 60 秒繁忙度峰值（百分数）；nil 表示尚无历史
    static func disk(busyPeakPercent: Int?) -> String {
        let base = "容量取自根卷属性（含系统与用户数据）；实心面积为读写字节速率（Bytes 差分 ÷ 采样间隔），"
            + "虚线的为每秒操作数（Operations 差分，对数刻度——0…3000 op/s 跨两个数量级，线性刻度会把日常量级压到底部；"
            + "形状可比，真实数值见文字），读写共用同一纵轴，曲线为近 60 秒。"
            + "IOPS / 繁忙度与字节速率同一次 IOBlockStorageDriver 调用取回，零额外采样开销；"
            + "该机型未返回 Operations / Total Time 键时 IOPS 与繁忙度显示「—」，字节速率照常。"
            + "繁忙度 =（读服务时间 + 写服务时间）÷ 采样间隔，即设备处于 IO 的时间占比；"
            + "高 IOPS 低字节（大量小文件随机 IO）时字节线平、繁忙度与 IOPS 高，只看吞吐看不出来"
        guard let busyPeakPercent else { return base }
        return base + "；近 60 秒繁忙度峰值 \(busyPeakPercent)%"
    }

    /// 温度卡：温度来自 IOHID（非 SMC）+ GPU 温度 / 功耗 / 风扇不可得
    static let thermal = "温度取自从 IOHIDEventSystemClient 读到的事件字段（非 SMC 键）；"
        + "CPU（SoC）超过 85°C 转入警示色。右侧依次是 GPU 温度、功耗：Apple Silicon 上两者都取不到"
        + "（未暴露对应 IOHID 字段），因此显示「—」；风扇转速同样不可得，不单列"
}

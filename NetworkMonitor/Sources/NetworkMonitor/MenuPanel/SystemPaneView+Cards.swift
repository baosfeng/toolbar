import AppKit

// MARK: - 卡片装配（拆出主文件，避免热文件超过 15 KiB 上限）

extension SystemPaneView {

    /// 顶部四联：CPU / GPU / 内存 / 负载 等宽小格（(296 - 12) / 4 = 71pt）
    ///
    /// 四格比三联窄，主数值字号随之下调（见 SystemHeroTileView.compactValueFont），
    /// 行高按原型 v4 收一档，省下的高度留给首屏的压力卡与状态带。
    /// 四联不属于「五卡」范围（本轮只改卡内），保持原有 AppKit 小格。
    func makeHeroRow() -> NSView {
        let row = NSStackView(views: [cpuTile, gpuTile, memoryTile, loadTile])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        row.distribution = .fillEqually
        row.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return row
    }

    /// 压力卡：负载三线图 + 进程 Top-2；卡头右端「全部 ›」进压力详情
    ///
    /// 负载是「就绪队列多长」、进程榜是「谁在吃 CPU」，两者合起来才叫压力，
    /// 故同卡上下排布；版2 把 Top-3 收到 Top-2 并取消「切」按钮（内存榜无入口，
    /// 定稿论证见 variants.md §3：3 条之外没有可下沉字段）。
    func makeLoadCard() -> NSView {
        loadCard.toolTip = SystemPaneTip.load()
        loadCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.process, from: self.loadCard)
        }
        // 「全部 ›」与整卡同一入口（都进压力详情），但读屏与 toolTip 各自独立
        loadCard.headAction = SystemCardView.HeadAction(
            title: "全部 ›",
            font: NSFont.systemFont(ofSize: 9, weight: .bold),
            color: SystemPalette.loadInk,
            tip: SystemPaneTip.processAll,
            activate: { [weak self] in self?.showDetail(.process, from: self?.loadCard) })
        return loadCard
    }

    /// CPU 卡：卡内 23pt 总利用率 + 60 秒叠加面积图（版2 不画每核柱阵 → CPU 详情）
    ///
    /// 用户态 / 系统态两枚图例挂在卡头、与标题同行（零新增行高）。
    func makeCPUCard() -> NSView {
        cpuCard.toolTip = SystemPaneTip.cpu
        cpuCard.showsChevron = true
        cpuCard.chevronColor = SystemPalette.cpuInk
        cpuCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.cpu, from: self.cpuCard)
        }
        return cpuCard
    }

    /// GPU 卡：环形利用率 + 60 秒折线 + 已用显存数值行（版2 去掉显存条 → GPU 详情）
    func makeGPUCard() -> NSView {
        gpuCard.toolTip = SystemPaneTip.gpu
        gpuCard.showsChevron = true
        gpuCard.chevronColor = SystemPalette.gpuInk
        gpuCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.gpu, from: self.gpuCard)
        }
        return gpuCard
    }

    /// 内存卡：只留四段堆叠条 + 压力徽标（四段数值行下沉到内存详情）
    func makeMemoryCard() -> NSView {
        memoryCard.toolTip = SystemPaneTip.memory
        memoryCard.showsChevron = true
        memoryCard.chevronColor = SystemPalette.memoryInk
        memoryCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.memory, from: self.memoryCard)
        }
        return memoryCard
    }

    /// 磁盘卡：版2 压成单行 —— 卡头繁忙度微条 + 已用/总容量 + ›
    func makeDiskCard() -> NSView {
        // 繁忙度峰值随历史刷新补进说明（见 updateDiskBusyTip），此处给基础口径
        diskCard.toolTip = SystemPaneTip.disk(busyPeakPercent: nil)
        diskCard.showsChevron = true
        diskCard.chevronColor = SystemPalette.diskInk
        diskCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.disk, from: self.diskCard)
        }
        return diskCard
    }

    /// 显示 / 隐藏状态带里的温度段（设置页 PanelItem.thermal 开关的新语义）
    ///
    /// 温度卡在 v4 已下线：开关不再控制整张卡，而是控制底部状态带里的温度读数。
    func setShowsThermalCard(_ shows: Bool) {
        stateBand.setShowsTemperature(shows)
    }
}

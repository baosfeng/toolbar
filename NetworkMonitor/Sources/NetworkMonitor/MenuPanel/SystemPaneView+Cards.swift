import AppKit

// MARK: - 卡片装配（拆出主文件，避免热文件超过 15 KiB 上限）

extension SystemPaneView {

    /// 顶部四联：CPU / GPU / 内存 / 负载 等宽小格（(296 - 12) / 4 = 71pt）
    ///
    /// 四格比三联窄，主数值字号随之下调（见 SystemHeroTileView.compactValueFont），
    /// 行高按原型 v4 收一档，省下的高度留给首屏的压力卡与状态带。
    func makeHeroRow() -> NSView {
        let row = NSStackView(views: [cpuTile, gpuTile, memoryTile, loadTile])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        row.distribution = .fillEqually
        row.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return row
    }

    /// 压力卡：负载三线图 + 进程 Top-2；卡头右端「全部 ›」进 CPU 详情
    ///
    /// 负载是「就绪队列多长」、进程榜是「谁在吃 CPU」，两者合起来才叫压力，
    /// 故同卡上下排布；版2 把 Top-3 收到 Top-2 并取消「切」按钮（内存榜无入口，
    /// 定稿论证见 variants.md §3：3 条之外没有可下沉字段）。
    func makeLoadCard() -> NSView {
        loadCard.toolTip = SystemPaneTip.load()
        loadCard.setHeaderAccessory(loadNumbers)
        loadCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.process, from: self.loadCard)
        }

        processAllButton.target = self
        processAllButton.action = #selector(showAllProcesses)
        processAllButton.isBordered = false
        processAllButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        processAllButton.contentTintColor = SystemPalette.loadInk
        processAllButton.setButtonType(.momentaryChange)
        processAllButton.setAccessibilityLabel("查看进程详情")
        processAllButton.toolTip = SystemPaneTip.processAll
        loadCard.setHeaderAction(processAllButton)

        let content = NSStackView(views: [loadChart, processList])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 4
        for subview in content.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        loadCard.addContent(content)
        return loadCard
    }

    /// 「全部 ›」→ 压力详情（Top-10 进程榜 + CPU 榜 / 内存榜切换）
    @objc func showAllProcesses() {
        showDetail(.process, from: loadCard)
    }

    /// CPU 卡：卡内 23pt 总利用率 + 60 秒叠加面积图（版2 不画每核柱阵 → CPU 详情）
    ///
    /// 用户态 / 系统态两枚图例挂在卡头、与标题同行（零新增行高）。
    func makeCPUCard() -> NSView {
        cpuCard.toolTip = SystemPaneTip.cpu
        cpuCard.setHeaderAccessory(cpuSplit)
        cpuCard.setDisclosure(visible: true, color: SystemPalette.cpuInk)
        cpuCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.cpu, from: self.cpuCard)
        }
        // 系统态带与卡头图例色块必须同源：两处各写一份就会「图例深、图上浅」
        cpuArea.overlayColor = SystemPaneStyle.systemUsageBand
        cpuHero.setContentHuggingPriority(.required, for: .horizontal)
        cpuHero.setContentCompressionResistancePriority(.required, for: .horizontal)
        cpuArea.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cpuArea.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [cpuHero, cpuArea])
        row.orientation = .horizontal
        row.alignment = .bottom
        row.spacing = 8
        row.distribution = .fill
        cpuCard.addContent(row)
        return cpuCard
    }

    /// GPU 卡：环形利用率 + 60 秒折线 + 已用显存数值行（版2 去掉显存条 → GPU 详情）
    func makeGPUCard() -> NSView {
        gpuCard.toolTip = SystemPaneTip.gpu
        gpuCard.setDisclosure(visible: true, color: SystemPalette.gpuInk)
        gpuCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.gpu, from: self.gpuCard)
        }
        gpuSparkline.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sparklineRow = NSStackView(views: [gpuRing, gpuSparkline])
        sparklineRow.orientation = .horizontal
        sparklineRow.alignment = .centerY
        sparklineRow.spacing = 10
        gpuSparkline.widthAnchor.constraint(equalTo: sparklineRow.widthAnchor,
                                            constant: -50).isActive = true

        let memoryRow = Self.trailingValueRow(caption: "显存", value: gpuMemoryLabel)
        let content = NSStackView(views: [sparklineRow, memoryRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 4
        for subview in content.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        gpuCard.addContent(content)
        return gpuCard
    }

    /// 内存卡：只留四段堆叠条 + 压力徽标（四段数值行下沉到内存详情）
    func makeMemoryCard() -> NSView {
        memoryCard.toolTip = SystemPaneTip.memory
        memoryCard.setHeaderAccessory(pressureDot)
        memoryCard.setDisclosure(visible: true, color: SystemPalette.memoryInk)
        memoryCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.memory, from: self.memoryCard)
        }
        memoryCard.addContent(memoryBar)
        return memoryCard
    }

    /// 磁盘卡：版2 压成单行 —— 卡头繁忙度微条 + 已用/总容量 + ›
    func makeDiskCard() -> NSView {
        // 繁忙度峰值随历史刷新补进说明（见 updateDiskBusyTip），此处给基础口径
        diskCard.toolTip = SystemPaneTip.disk(busyPeakPercent: nil)
        diskCard.setHeaderAccessory(Self.trailingValueRow(caption: "忙", value: diskBusyLabel,
                                                          track: diskBusyTrack))
        diskCard.setDisclosure(visible: true, color: SystemPalette.diskInk)
        diskCard.onTap = { [weak self] in
            guard let self else { return }
            self.showDetail(.disk, from: self.diskCard)
        }
        return diskCard
    }

    /// 「标签 + 值」或「标签 + 值 + 微条」卡头小组（GPU 显存行 / 磁盘繁忙度）
    ///
    /// 版2 的磁盘卡只有卡头一行，微条必须紧跟在「忙 xx%」后面才有读数感。
    static func trailingValueRow(caption: String, value: NSTextField,
                                 track: MenuPanelTrackView? = nil) -> NSStackView {
        let captionLabel = MenuPanelLabel.text(caption,
                                               font: SystemPaneStyle.microFont,
                                               color: SystemPalette.meta)
        captionLabel.setContentHuggingPriority(.required, for: .horizontal)
        let arranged: [NSView] = track.map { [captionLabel, value, $0] } ?? [captionLabel, value]
        let row = NSStackView(views: arranged)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        value.setContentHuggingPriority(.required, for: .horizontal)
        track?.setContentHuggingPriority(.required, for: .horizontal)
        track?.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }

    /// 显示 / 隐藏状态带里的温度段（设置页 PanelItem.thermal 开关的新语义）
    ///
    /// 温度卡在 v4 已下线：开关不再控制整张卡，而是控制底部状态带里的温度读数。
    func setShowsThermalCard(_ shows: Bool) {
        stateBand.setShowsTemperature(shows)
    }
}

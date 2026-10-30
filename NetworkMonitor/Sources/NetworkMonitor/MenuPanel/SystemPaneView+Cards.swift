import AppKit

// MARK: - 卡片装配（拆出主文件，避免热文件超过 15 KiB 上限）

extension SystemPaneView {

    /// 顶部三联：CPU / GPU / 内存 等宽小格（(296 - 8) / 3 = 96pt）
    func makeHeroRow() -> NSView {
        let row = NSStackView(views: [cpuTile, gpuTile, memoryTile])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        row.distribution = .fillEqually
        row.heightAnchor.constraint(equalToConstant: 64).isActive = true
        return row
    }

    /// CPU 卡：左 60 秒叠加面积图 + 右每核柱阵（柱阵不写字，悬停出核号与占比）
    ///
    /// 用户态 / 系统态两枚图例挂在卡头、与标题同行（零新增行高）。
    func makeCPUCard() -> NSView {
        cpuCard.toolTip = SystemPaneTip.cpu
        cpuCard.setHeaderAccessory(cpuSplit)
        // 系统态带与卡头图例色块必须同源：两处各写一份就会「图例深、图上浅」
        cpuArea.overlayColor = SystemPaneStyle.systemUsageBand
        let row = NSStackView(views: [cpuArea, coreGrid])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        coreGrid.widthAnchor.constraint(equalToConstant: 112).isActive = true
        cpuArea.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -120).isActive = true
        cpuCard.addContent(row)
        return cpuCard
    }

    /// GPU 卡：环形利用率 + 60 秒折线 + 显存细条（显存不可得显示「—」）
    func makeGPUCard() -> NSView {
        gpuCard.toolTip = SystemPaneTip.gpu
        let sparklineRow = NSStackView(views: [gpuRing, gpuSparkline])
        sparklineRow.orientation = .horizontal
        sparklineRow.alignment = .centerY
        sparklineRow.spacing = 10
        gpuSparkline.widthAnchor.constraint(equalTo: sparklineRow.widthAnchor, constant: -54).isActive = true

        let memoryRow = NSStackView(views: [gpuMemoryTrack, gpuMemoryLabel])
        memoryRow.orientation = .horizontal
        memoryRow.alignment = .centerY
        memoryRow.spacing = 8
        gpuMemoryLabel.setContentHuggingPriority(.required, for: .horizontal)
        gpuMemoryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        gpuMemoryTrack.widthAnchor.constraint(equalTo: memoryRow.widthAnchor, constant: -96).isActive = true

        let content = NSStackView(views: [sparklineRow, memoryRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        for subview in content.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        gpuCard.addContent(content)
        return gpuCard
    }

    /// 内存卡：四段堆叠条 + 压力徽标 + 四段数值与换出量一行
    func makeMemoryCard() -> NSView {
        memoryCard.toolTip = SystemPaneTip.memory
        memoryCard.setHeaderAccessory(pressureDot)
        let barRow = NSStackView(views: [memoryBar])
        barRow.orientation = .horizontal
        barRow.alignment = .centerY
        barRow.spacing = 6
        memoryBar.widthAnchor.constraint(equalTo: barRow.widthAnchor).isActive = true

        let content = NSStackView(views: [barRow, memorySplit])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        for subview in content.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        memoryCard.addContent(content)
        return memoryCard
    }

    /// 磁盘卡：卡头繁忙度微条 + 读写双色曲线（共坐标系）+ 容量条 + 读写速率与 IOPS
    func makeDiskCard() -> NSView {
        // 繁忙度峰值随历史刷新补进说明（见 updateDiskBusyTip），此处给基础口径
        diskCard.toolTip = SystemPaneTip.disk(busyPeakPercent: nil)
        // IOPS 虚线用的灰阶口径集中在 SystemPaneStyle，避免与样式表各写一份
        diskSparkline.primaryOverlayColor = SystemPaneStyle.iopsPrimary
        diskSparkline.secondaryOverlayColor = SystemPaneStyle.iopsSecondary
        let busyRow = NSStackView(views: [diskBusyLabel, diskBusyTrack])
        busyRow.orientation = .horizontal
        busyRow.alignment = .centerY
        busyRow.spacing = 4
        diskBusyTrack.setContentHuggingPriority(.required, for: .horizontal)
        diskBusyTrack.widthAnchor.constraint(equalToConstant: 22).isActive = true
        diskCard.setHeaderAccessory(busyRow)

        let ratesRow = NSStackView(views: [diskReadIOPSLabel, diskReadLabel,
                                           MenuPanelLabel.spacer(),
                                           diskWriteIOPSLabel, diskWriteLabel])
        ratesRow.orientation = .horizontal
        ratesRow.alignment = .firstBaseline
        ratesRow.spacing = 4
        for label in [diskReadIOPSLabel, diskReadLabel, diskWriteIOPSLabel, diskWriteLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
        }

        let content = NSStackView(views: [diskSparkline, diskCapacityTrack, ratesRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 5
        for subview in content.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        diskCard.addContent(content)
        return diskCard
    }

    /// 显示 / 隐藏温度卡（设置页开关驱动；隐藏后不占面板高度）
    func setShowsThermalCard(_ shows: Bool) {
        let shouldHide = !shows
        guard thermalCard.isHidden != shouldHide else { return }
        thermalCard.isHidden = shouldHide
    }

    /// 温度卡：CPU 温度 hero（>85°C 警示色）+ GPU 温度 / 功耗
    func makeThermalCard() -> NSView {
        thermalCard.toolTip = SystemPaneTip.thermal
        let row = NSStackView(views: [thermalValueLabel, thermalUnitLabel,
                                      MenuPanelLabel.spacer(), thermalDetailLabel])
        row.orientation = .horizontal
        row.alignment = .lastBaseline
        row.spacing = 3
        thermalDetailLabel.setContentHuggingPriority(.required, for: .horizontal)
        thermalCard.addContent(row)
        return thermalCard
    }
}

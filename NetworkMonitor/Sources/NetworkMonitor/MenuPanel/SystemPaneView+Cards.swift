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

    /// CPU 卡：左 60 秒面积图 + 右每核柱阵（柱阵不写字，悬停出核号与占比）
    func makeCPUCard() -> NSView {
        cpuCard.toolTip = "CPU 利用率 = 1 减空闲占比，1 秒采样差分；左侧为最近 60 秒面积趋势；"
            + "右侧每核柱阵按 P 核在前、E 核在后排列，悬停可看单核占用"
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
        gpuCard.toolTip = "GPU 利用率为设备性能计数器读数；折线为最近 60 秒趋势；"
            + "统一内存机型无显存总量，只显示已用显存（取不到时显示「—」）"
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

    /// 内存卡：分段堆叠条 + 压力徽标 + SWAP 一行
    func makeMemoryCard() -> NSView {
        memoryCard.toolTip = "内存已用 = wired + compressed + active；堆叠条自左至右为非压缩已用 / 压缩内存 / 空闲；"
            + "圆点为系统内存压力（绿正常、黄警告、红严重）；快照未拆分 wired/active，故合并为一段显示"
        let barRow = NSStackView(views: [memoryBar, pressureDot])
        barRow.orientation = .horizontal
        barRow.alignment = .centerY
        barRow.spacing = 6
        memoryBar.widthAnchor.constraint(equalTo: barRow.widthAnchor, constant: -14).isActive = true

        let swapRow = NSStackView(views: [
            MenuPanelLabel.text("SWAP", font: MenuPanelStyle.smallValueFont,
                                color: MenuPanelStyle.tertiaryText),
            MenuPanelLabel.spacer(),
            memorySwapLabel,
        ])
        swapRow.orientation = .horizontal
        swapRow.alignment = .centerY
        swapRow.spacing = 6
        memorySwapLabel.setContentHuggingPriority(.required, for: .horizontal)

        let content = NSStackView(views: [barRow, swapRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        for subview in content.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        memoryCard.addContent(content)
        return memoryCard
    }

    /// 磁盘卡：读写双色曲线（共坐标系）+ 容量条 + 读写速率
    func makeDiskCard() -> NSView {
        diskCard.toolTip = "读/写速率为 1 秒采样差分（系统未提供时显示「—」）；两条曲线共用同一纵轴；"
            + "容量条为已用 / 总量"
        let ratesRow = NSStackView(views: [diskReadLabel, MenuPanelLabel.spacer(), diskWriteLabel])
        ratesRow.orientation = .horizontal
        ratesRow.alignment = .centerY
        ratesRow.spacing = 8
        diskReadLabel.setContentHuggingPriority(.required, for: .horizontal)
        diskWriteLabel.setContentHuggingPriority(.required, for: .horizontal)

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
        thermalCard.toolTip = "温度取自 SMC 传感器；CPU 超过 85°C 转入警示色。"
            + "右侧「GPU — · —」依次是 GPU 温度、整机功耗：本机两者都取不到（Apple Silicon 上"
            + "GPU 温度与整机功耗未暴露 SMC 键），因此都显示「—」；风扇转速同样不可得，不单列"
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

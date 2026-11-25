import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureSnip
import NetworkMonitorUI

// MARK: - 设置页：标注卡片里的「像素效果」两行

/// 马赛克粒度 / 模糊强度两行的组装、回灌与动作
///
/// 为什么单独成文件而不挂在 SettingsCapturePane+Annotation：标注卡片本身已经装着
/// 颜色 / 线宽 / 虚线 / 字号四行，再加两行就撞同族合计门禁；而这两行是**像素效果**
/// （作用于底图像素，与笔的颜色线宽无关），概念上也是独立的一族。
/// 文件名不带 `SettingsCapturePane` 前缀，因此单独成族、不占标注卡片的额度。
extension SettingsCapturePane {

    // MARK: - 组装

    /// 往标注卡片追加「马赛克粒度 / 模糊强度」两行
    ///
    /// 这两个值过去写死在 SnipMosaicProcessor 里（都是 14），全仓没有任何入口 ——
    /// 用户既不能调、也无从知道它可调。
    func addEffectStyleRows(to card: SettingsCardView) {
        let mosaic = makeStepper(min: SnipEffectStyle.mosaicRange.lowerBound,
                                 max: SnipEffectStyle.mosaicRange.upperBound,
                                 action: #selector(mosaicBlockChanged))
        let mosaicValue = makeValueLabel(SnipNumericParam.mosaicBlock.format(SnipEffectStyle.defaultMosaicBlock))
        mosaicControl = mosaic
        mosaicValueLabel = mosaicValue
        let mosaicRow = SettingsRowView(title: "马赛克粒度",
                                        subtitle: "像素块边长；截图里选中马赛克工具时滚轮可调")
        mosaicRow.trailingStack.addArrangedSubview(makeStepperStack(value: mosaicValue, stepper: mosaic))
        card.addRow(mosaicRow)

        let blur = makeStepper(min: SnipEffectStyle.blurRange.lowerBound,
                               max: SnipEffectStyle.blurRange.upperBound,
                               action: #selector(blurRadiusChanged))
        let blurValue = makeValueLabel(SnipNumericParam.blurRadius.format(SnipEffectStyle.defaultBlurRadius))
        blurControl = blur
        blurValueLabel = blurValue
        let blurRow = SettingsRowView(title: "模糊强度",
                                      subtitle: "高斯模糊半径；与马赛克各自独立记忆")
        blurRow.trailingStack.addArrangedSubview(makeStepperStack(value: blurValue, stepper: blur))
        card.addRow(blurRow)
    }

    // MARK: - 回灌

    /// 两个步进器与数值文本回灌（进页面时调）
    func refreshEffectStyleRows() {
        let effect = SnipEffectStylePreference.load(storage: storage)
        mosaicControl?.doubleValue = Double(effect.mosaicBlock)
        mosaicValueLabel?.stringValue = SnipNumericParam.mosaicBlock.format(effect.mosaicBlock)
        blurControl?.doubleValue = Double(effect.blurRadius)
        blurValueLabel?.stringValue = SnipNumericParam.blurRadius.format(effect.blurRadius)
    }

    // MARK: - 动作

    @objc func mosaicBlockChanged() {
        let value = SnipEffectStyle.clampMosaic(CGFloat(mosaicControl?.doubleValue ?? 14))
        var effect = SnipEffectStylePreference.load(storage: storage)
        effect.mosaicBlock = value
        SnipEffectStylePreference.save(effect, storage: storage)
        mosaicValueLabel?.stringValue = SnipNumericParam.mosaicBlock.format(value)
        logger.info("马赛克粒度：" + SnipNumericParam.mosaicBlock.format(value))
    }

    @objc func blurRadiusChanged() {
        let value = SnipEffectStyle.clampBlur(CGFloat(blurControl?.doubleValue ?? 14))
        var effect = SnipEffectStylePreference.load(storage: storage)
        effect.blurRadius = value
        SnipEffectStylePreference.save(effect, storage: storage)
        blurValueLabel?.stringValue = SnipNumericParam.blurRadius.format(value)
        logger.info("模糊强度：" + SnipNumericParam.blurRadius.format(value))
    }
}

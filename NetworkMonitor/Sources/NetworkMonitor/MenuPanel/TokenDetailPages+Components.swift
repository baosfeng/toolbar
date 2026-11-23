import AppKit
import NetworkMonitorCore

// MARK: - Token 二级页 · 返回条改写

/// 二级页共用组件已直接调 TokenContentKit（TokenScreenContent.swift）：
/// 原先这里有一层同名转发（hero / head / keyRow / axisView / twoColumn / note / splitShares），
/// 转发文件本身不产生任何逻辑，却让 TokenDetailPages 族多占几十行、还得跟着组件改签名。
/// 现在页面直接引用 TokenContentKit，本文件只保留真正属于返回条的改写入口。
extension TokenDetailPaneView {

    /// 返回条被页面改写时同步面包屑与右侧说明
    func overrideCrumb(_ text: String, meta: String) {
        crumbLabel.stringValue = text
        metaLabel.stringValue = meta
    }
}

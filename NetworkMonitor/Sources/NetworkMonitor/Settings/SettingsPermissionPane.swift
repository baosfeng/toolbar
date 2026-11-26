import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 系统权限设置页

/// 系统权限 —— 五类系统授权集中在这一页（方案 A + B 组合：集中可查 + 各功能页保留就地简版）
///
/// 单点口径：状态读 `permissions.snapshot`（`SystemPermissionCenter.refresh()`），
/// 文案 / 灯色 / 标签 / 按钮全部来自 `SystemPermissionEntry`，深链只在
/// `SystemPermissionCenter.openSettings(for:)` 拼一次 —— 本页不碰任何系统 API、不拼 URL。
///
/// 页头胶囊与卡下说明都跟着快照走：全绿时说明只剩「切回应用即刷新」，
/// 有待处理时补上「按中文名找到应用」的引导与屏幕录制的重启提示。
final class SettingsPermissionPane: SettingsPaneView {

    /// 跨文件访问：本页持有的权限协议（基类的 `permissionSource` 供就地卡使用）
    let permissions: any SystemPermissionProviding
    private let logger: LoggingService
    /// 签名变化提示带（refresh 时按最新快照重刷「哪些权限待重授」）
    private var signingBand: SettingsSigningNoticeBand?

    init(permissions: any SystemPermissionProviding,
         logger: LoggingService = AppContext.shared.logger) {
        self.permissions = permissions
        self.logger = logger
        super.init(section: .permissions)
    }

    override func buildContent() {
        // 提示带排在第一张卡之上：签名变了的时候它比任何一张卡都重要，
        // 而用户此时最常做的动作就是「打开系统设置」重勾
        buildSigningNoticeBand()
        let card = SystemPermissionCard(permissions: permissions, logger: logger)
        card.attach(to: page)
        buildEntryCard()
        page.addNote("五类权限的标题、状态、深链与「要不要重启」只有一个出处："
                     + "各功能页的就地入口读的是同一份快照，不会出现两页说法不一致。")
        refresh()
    }

    /// 签名变化提示带（仅当检测到身份变化时可见）
    ///
    /// 深链走权限中心已有的 `openSettings(for:)`，本页不拼 URL；
    /// 目标锚点固定「隐私与安全性」总面板 —— 一次变化会命中好几类权限，
    /// 把用户送到某一条的子锚点反而要他再跳回来。
    private func buildSigningNoticeBand() {
        let band = SettingsSigningNoticeBand()
        band.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.permissions.openSettings(for: .clipboard)
        }
        page.addRow(band, gapBefore: SettingsTheme.groupSpacingTop)
        band.update(permissions.signingNotice, snapshot: permissions.snapshot)
        signingBand = band
    }

    /// 「各功能页的就地入口」说明卡 —— 告诉用户其他地方只显示状态，按钮都跳回本页
    private func buildEntryCard() {
        let rows: [(String, String)] = [
            ("剪贴板页", "辅助功能 + 剪贴板访问两行简版，按钮跳本页"),
            ("截图与贴图页", "只留屏幕录制一行状态 + 「重启应用」"),
            ("通用页", "开机自启动开关留在启动卡；登记状态与失败回滚在本页说明"),
            ("通知与音效页", "只留通知授权状态，按钮跳本页"),
        ]
        let card = SettingsCardView()
        for (title, detail) in rows {
            let row = SettingsRowView(title: title, subtitle: detail)
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "就地入口")
    }

    override func refresh() {
        // 卡片自己订阅快照重绘；这里只同步页头胶囊（切页 / 窗口重开时立即是最新值）
        permissions.refresh()
        let snapshot = permissions.snapshot
        signingBand?.update(permissions.signingNotice, snapshot: snapshot)
        page.setStatusChip(SettingsStatusChip(subject: snapshot.summaryLabel,
                                              detail: nil,
                                              tone: snapshot.summaryTone))
    }
}

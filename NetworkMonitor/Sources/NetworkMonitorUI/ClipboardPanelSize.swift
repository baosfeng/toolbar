import Foundation

// MARK: - 面板高度档位（纯逻辑）

/// 剪贴板面板的高度档位 —— 工具条按钮、设置页滑块与偏好读取共用同一份真源
///
/// 对标 Paste 的帮助文档口径「高度三档：大 / 小 / Compact Mode」：
/// 面板越高 → 卡片越大 → 一屏越少几张；面板越矮 → 卡片越小 → 一屏越多几张。
/// 卡片尺寸始终由面板高度推出（`ClipboardCardGeometry.cardSize`），档位只给一个快捷落点，
/// 不改卡片比例、不改一屏排布方向（永远单行横向）。
///
/// 存进偏好的永远是**高度数值**（`clipboard.panelHeight`），不是档位名：
/// 用户在设置页把滑块拖到档位之外的自定义高度时，档位只是「最接近的那一档」，
/// 不会被吸附或改写 —— 否则用户拖到 350 再打开面板会莫名变成 320。
public enum ClipboardPanelSize: String, CaseIterable, Sendable {
    /// 紧凑：面板压到几何下限（卡片 172×150，一屏约 8 张）
    case compact
    /// 标准：默认档（卡片 227×198，一屏约 6 张）
    case standard
    /// 宽松：卡片更大、每张能多读几行（卡片 291×254，一屏约 5 张）
    case roomy

    /// 档位对应的高度（pt）
    ///
    /// 三档按「一屏张数」排开：8 / 6 / 5 张。改前三档是 6 / 5 / 4 张，
    /// 默认档的卡片 291×254 里常常只放着一行正文、其余全是空白 —— 空间利用率太低，
    /// 因此整体下移一档：默认回到基准卡 227×198（正好是 Paste 243×212 的量级）。
    ///
    /// 紧凑档直接取几何下限（改最小卡高时自动跟着变），不会再出现「档位比下限还低、
    /// 夹紧后两张档位长得一样」。
    public var height: Double {
        switch self {
        case .compact: return ClipboardPanelLayout.minPanelHeight
        case .standard: return 264
        case .roomy: return 320
        }
    }

    /// 档位名（工具条 tooltip 与读屏共用）
    public var label: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .roomy: return "宽松"
        }
    }

    /// 工具条按钮图标（随档位换，一眼看出当前在哪一档）
    public var symbolName: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .standard: return "rectangle.split.1x2"
        case .roomy: return "rectangle.expand.vertical"
        }
    }

    /// 按高度取最接近的档位（自定义高度落在两档之间时给近的那个）
    public static func nearest(to height: Double) -> ClipboardPanelSize {
        guard height.isFinite, height > 0 else { return .standard }
        return allCases.min { abs($0.height - height) < abs($1.height - height) } ?? .standard
    }

    /// 循环到下一档（紧凑 → 标准 → 宽松 → 紧凑）
    public var next: ClipboardPanelSize {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .standard }
        return all[(index + 1) % all.count]
    }

    /// 工具条按钮的无障碍标签与 tooltip：文案必须同时说清「现在是什么」与「点一下会变什么」
    public var switchHint: String {
        "面板高度：\(label)（点按切换为\(next.label)）"
    }
}

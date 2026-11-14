import CoreGraphics

// MARK: - 绘制层的可断言口径（纯数学，无 AppKit）

/// 层不透明度的折叠 —— 表面层（卡底 / 叠色 / 描边）都带一个「层不透明度」
///
/// 抽出来的理由：折叠规则与「多少以下不画」这两条原本散在三个绘制实现里各写一遍，
/// 错一处就会出现 1px 灰边或半透明层留下脏像素。
public enum DrawnLayerAlpha {

    /// 元素自身 alpha × 层不透明度
    public static func fold(_ base: CGFloat, layer: CGFloat) -> CGFloat {
        base * layer
    }

    /// 这一层是否值得画：低于 1/1000 一律不画（过渡值刚起步的帧不落笔）
    public static func isVisible(_ alpha: CGFloat) -> Bool {
        alpha > 0.001
    }
}

/// 卡片阴影的换算 —— 三个容易搞错的换算式集中在一处
///
/// 三条口径都来自改造前 CALayer 阴影与 CGContext 阴影的对照实测：
/// - 阴影强度：`CALayer.shadowOpacity` 不受内容 alpha 调制，而 `CGContext.setShadow` 会按绘制内容
///   的 alpha 打折，所以要除以内容 alpha 反算回去；
/// - 扩散跨度：`CGContext` 的 blur 是模糊核尺度，与 `CALayer.shadowRadius` 的可见扩散半径约 2 倍关系；
/// - 形状：阴影矩形按半像素内缩，避免描边被裁掉一半。
public enum DrawnShadowMath {

    /// 叠在内容之上的等效阴影不透明度（内容 alpha 为 0 时退化为 0）
    public static func shadowAlpha(opacity: CGFloat, contentAlpha: CGFloat) -> CGFloat {
        guard contentAlpha > 0.001 else { return 0 }
        return opacity / contentAlpha
    }

    /// 可见扩散半径 → CGContext 模糊核尺度
    public static func blur(visibleRadius: CGFloat) -> CGFloat {
        visibleRadius * 2
    }

    /// 阴影形状矩形（= 卡片矩形内缩 inset）
    public static func shapeRect(for cardRect: CGRect, inset: CGFloat) -> CGRect {
        cardRect.insetBy(dx: inset, dy: inset)
    }
}

/// 焦点环的路径口径 —— 行内环与整卡环的内缩 / 圆角规则
public enum DrawnFocusRingMath {

    /// 行内焦点环的描边路径矩形：横向内缩 1、纵向内缩 1.5
    public static func rowRect(for rect: CGRect) -> CGRect {
        rect.insetBy(dx: 1, dy: 1.5)
    }

    /// 整卡焦点环的描边路径矩形：四周内缩 1
    public static func cardRect(for bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 1, dy: 1)
    }

    /// 整卡焦点环的圆角：跟着内缩走（卡圆角 − 1），不小于 0
    public static func cardRadius(_ cardRadius: CGFloat) -> CGFloat {
        max(cardRadius - 1, 0)
    }
}

# 00 需求澄清：剪贴板历史面板（00-brief-clipboard）

platform: desktop
canvas: 640x260
frames: [browser-chrome]
responsive: no
breakpoints: []
min_supported: 640
dark_mode: required
locale: zh-CN
deliverable: interactive-prototype
first_screen: 搜索框 + 类型过滤 + 横向卡片流（最近的剪贴板条目）+ 键盘提示，一屏内可浏览与直选
fixed_constraints: 面板贴屏幕底部居中；非激活面板不抢焦点；键盘优先（↑↓ 选中、Enter 粘贴、⌘1–9 直选、Esc 收起）
notes: 现状来自 ClipboardPanelController.swift / ClipboardPanelView.swift / ClipboardCardView.swift：640×260、NSVisualEffectView 材质、卡片 168×190 圆角 12、选中 2pt accent 描边 + scale 1.02 + 阴影；p2/p3 为结构探索版（画布 640×360 / 760×340）

# 说明：本画布 640×260 与菜单栏面板的 320×600 不同源，实现时按各自尺寸，不要按 320 裁切。

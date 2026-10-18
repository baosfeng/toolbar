# r2 实机取证：面板对比度（真实 popover 窗口截图）

截图方式：`NM_SHOW_PANEL=1 NM_FORCE_APPEARANCE=light|dark ./debug/NetworkMonitor`（走真实 `togglePanel()` 打开 popover，
保持打开），2.5s 后 `screencapture -x -l <popover window id>`。**不是离屏 cacheDisplay。**

| 文件 | 外观 | 页 |
|---|---|---|
| popover-real-light.png | 浅色 | 网络 |
| popover-real-dark.png | 深色 | 网络 |
| popover-real-clipboard-light.png | 浅色 | 剪贴板 |
| popover-real-clipboard-dark.png | 深色 | 剪贴板 |

像素采样（笔画核心色 vs 背景，WCAG 2.x 相对亮度）：

| 元素 | 浅色 (bg 255,255,255) | 深色 (bg 30,30,30) |
|---|---|---|
| 正文 / 空态文字 | 14.94:1 | 12.16:1 |
| 行标题等次要文字 | 10.37:1 | 9.76:1 |
| 小号说明（占今日总量） | 6.90:1 | 7.69:1 |
| 未选中 tab 文字 | 6.90:1 | 7.60:1 |

装饰色（labelColor α 叠在 windowBackgroundColor 上）：浅色 bar 1.78:1 / track 1.38:1 / subtleFill 1.17:1；
深色 bar 2.20:1 / track 1.56:1 / 1.23:1（均为非文本图形，柱体另有数值与日期文字标注）。

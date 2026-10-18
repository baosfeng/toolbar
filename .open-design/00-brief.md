# 00 需求澄清（前置必问，填完再进第 1 步）
#
# 这份单子是机器可读的：key: value 一行一条，数组写 [a, b]。
# gallery 的 --frame、verify 的 --platform / 响应式断点检查都从这里取。

platform: desktop            # mobile | tablet | desktop | web | multi
canvas: 320x600              # 菜单栏下拉面板主画布（宽 320pt × 高 600pt 上下浮动）
frames: [browser-chrome]     # 对照图统一套同一个框，便于并排比较

responsive: no               # 固定宽度浮层，不做多断点；只保证 300–340pt 宽内排版不破
breakpoints: []
min_supported: 300

dark_mode: required          # 菜单栏应用必须深浅色都成立
locale: zh-CN
deliverable: interactive-prototype
first_screen: 实时网速 + 今日流量 + 活跃进程 + 剪贴板入口 + 退出（一屏内完成所有日常操作）
fixed_constraints: 面板宽 300–340pt；单列纵向流；高度自适应且不超过屏幕高 80%；圆角与材质需贴合 macOS Sonoma/Sequoia 的菜单栏浮层观感
notes: 用户原话「ai 相关的可以全部移除，我对当前的 ui 等不满意」；已拍板：AI 分析与 Token 用量（Token 概览 / 24h 柱状图 / 历史用量）全部删除；形态由用户在「原生菜单精修」与「自定义面板」等版本中自行挑选

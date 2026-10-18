# 01 模版选择

- template: `web-prototype`
- platform: `desktop`
- mode: `prototype`

## 理由

1. `odops templates --mode prototype --platform desktop` 共 39 个模版；本项目是 macOS 菜单栏应用的 320×600 浮层，属于「单文件桌面原型」而非营销页 / 报表 / 画布演示。
2. `web-prototype` 是唯一的通用桌面单文件骨架（`assets/template.html` 是自包含 HTML + 内联 CSS，零外部依赖），能直接承载三版结构对照，不需要 dashboard / kanban 这类自带业务语义的模版。
3. 它的 `references/checklist.md` P0 与本项目一致：无裸色值、`data-od-id` 全覆盖、禁 emoji 图标、禁填充文案——正好对应 `.reasonix/skills/toolbar-ui-standards` 的 SF Symbols + 系统色要求。
4. 其余候选与排除理由：
   - `dashboard`：固定左侧栏 + 大画布，与 320pt 浮层形态冲突；
   - `tweaks`：是给已有产物加参数面板，不是从零出骨架；
   - `wireframe-*`（3 个）：灰阶线框，但带纸张 / 蓝图 / 手绘质感，会干扰「原生菜单精修」的观感判断；
   - `contact-widget`：浮层聊天件，交互模型不匹配。

## seed

`odops template-use web-prototype --to .open-design/seed --yes` → `.open-design/seed/{assets/template.html, references/{checklist,layouts}.md}`。

seed 自带 6 个占位变量（`--bg --surface --fg --muted --border --accent`），骨架阶段只用到这 6 个的灰阶取值。

> 注：seed 的 `template.html` 是营销页骨架（hero / feature grid / sticky nav），与 320pt 菜单浮层结构不同。三版骨架**沿用它的约定**（token 只出现在 `:root`、单文件自包含、`data-od-id` 锚点、无外链资源），**不沿用它的版式块**——这点在 `03-layouts/variants.md` 里也记了。

#!/usr/bin/env python3
"""设置窗口视觉统一度量测 — 对 NM_SNAPSHOT_DIR 产出的 settings-*.png 做像素级取证。

用法：
    python3 Scripts/measure-settings-style.py <快照目录> [--expected-card 0xF5F5F7] [--expected-row 34]

判据（见 docs/设计/设置窗口-视觉统一-设计规格.md）：
- 卡片底必须是主题 cardFill（浅色 Apple=0xF5F5F7 / 石墨=0xECF0F6 / 米白见 ThemeCatalog）；
  纯白 0xFFFFFF 说明仍是旧的「描边白卡」语言
- 卡片圆角 9pt（与 PaneCardStyle.cardRadius 同档）
- 卡内行高 34pt（窗口档映射表）
输出表格可直接贴进验收报告。
"""
import sys
import os
from collections import Counter
from PIL import Image

SIDEBAR_WIDTH = 168
PAGES = [
    ("settings-general", "通用"),
    ("settings-appearance", "外观"),
    ("settings-providers", "额度 Provider"),
    ("settings-clipboard", "剪贴板"),
    ("settings-capture", "截图与贴图"),
    ("settings-transfer", "局域网互传"),
    ("settings-notifications", "通知与音效"),
    ("settings-system", "系统"),
    ("settings-about", "关于"),
]


def hex_of(color):
    return "0x%02X%02X%02X" % tuple(color[:3])


def content_region(image):
    """内容区（排除侧栏与四边）的矩形。"""
    width, height = image.size
    return SIDEBAR_WIDTH + 12, 4, width - 12, height - 8


def background_colors(image):
    """内容区四角采样 → 页面底色 / 内容区底（卡外区域的主色）。"""
    x0, y0, x1, y1 = content_region(image)
    # 只取页头与空白处的三个角：内容区中部可能已被卡片占满，采样进来会把卡底当背景
    points = [(x0 + 2, y0 + 2), (x1 - 2, y0 + 2), (x0 + 2, y1 - 2)]
    counts = Counter(image.getpixel(p) for p in points)
    return {counts.most_common(1)[0][0]}


def card_color(image):
    """内容区里面积最大、且不是页面底 / 内容区底的颜色 = 卡片底。"""
    counts = Counter()
    backgrounds = background_colors(image)
    x0, y0, x1, y1 = content_region(image)
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            color = image.getpixel((x, y))
            if color not in backgrounds:
                counts[color] += 1
    if not counts:
        return None
    return counts.most_common(1)[0][0]


def card_bbox(image, color):
    x0, y0, x1, y1 = content_region(image)
    xs, ys = [], []
    for y in range(y0, y1, 1):
        for x in range(x0, x1, 1):
            if image.getpixel((x, y)) == color:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def corner_radius(image, color, bbox):
    x0, y0, x1, _ = bbox
    for dy in range(1, 16):
        row = [x for x in range(x0, min(x0 + 16, x1)) if image.getpixel((x, y0 + dy)) == color]
        if row and row[0] - x0 == 0:
            return dy
    return None


def row_height(image, color, bbox):
    x0, y0, x1, y1 = bbox
    x = (x0 + x1) // 2
    gaps, last = [], None
    for y in range(y0 + 3, y1 - 2):
        if image.getpixel((x, y)) != color:
            if last is not None and 18 <= y - last <= 70:
                gaps.append(y - last)
            last = y
    if not gaps:
        return None
    return Counter(gaps).most_common(1)[0][0]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    directory = sys.argv[1]
    expected_card = None
    if "--expected-card" in sys.argv:
        raw = int(sys.argv[sys.argv.index("--expected-card") + 1], 16)
        expected_card = (raw >> 16 & 0xFF, raw >> 8 & 0xFF, raw & 0xFF)
    expected_card_dark = None
    if "--expected-card-dark" in sys.argv:
        raw = int(sys.argv[sys.argv.index("--expected-card-dark") + 1], 16)
        expected_card_dark = (raw >> 16 & 0xFF, raw >> 8 & 0xFF, raw & 0xFF)
    expected_row = 34
    if "--expected-row" in sys.argv:
        expected_row = int(sys.argv[sys.argv.index("--expected-row") + 1])

    print("| 页面 | 外观 | 卡片底 | 圆角 | 行高 | 判定 |")
    print("|------|------|--------|------|------|------|")
    failures = 0
    for suffix, name in PAGES:
        for appearance in ("light", "dark"):
            path = os.path.join(directory, "%s-%s.png" % (suffix, appearance))
            if not os.path.exists(path):
                continue
            image = Image.open(path).convert("RGB")
            color = card_color(image)
            if color is None:
                print("| %s | %s | — | — | — | 无卡片 |" % (name, appearance))
                continue
            bbox = card_bbox(image, color)
            if bbox is None:
                print("| %s | %s | %s | — | — | 无卡片 |" % (name, appearance, hex_of(color)))
                continue
            radius = corner_radius(image, color, bbox)
            height = row_height(image, color, bbox)
            verdict = []
            expectation = expected_card if appearance == "light" else expected_card_dark
            if expectation and color != expectation:
                verdict.append("卡片底≠主题 cardFill(%s)" % hex_of(expectation))
            # 圆角为近似量测（抗锯齿 + 渲染倍率影响 ±3pt），精确值以代码常量
            # NetworkMonitorUI/SettingsSkeletonLogic.swift 的 cardRadius 为准
            if radius is not None and not (5 <= radius <= 13):
                verdict.append("圆角量测 %d 超出近似区间(5–13)" % radius)
            # 行高受卡片内容（多行说明 / 输入框）影响，只报告不判定；需要硬判据时加 --strict-row
            if "--strict-row" in sys.argv and height is not None and abs(height - expected_row) > 1:
                verdict.append("行高 %d≠%d" % (height, expected_row))
            if verdict:
                failures += 1
            print("| %s | %s | %s | %s | %s | %s |" % (
                name, appearance, hex_of(color), radius if radius is not None else "—",
                height if height is not None else "—", "；".join(verdict) or "通过"))
    print("\n失败项：%d" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

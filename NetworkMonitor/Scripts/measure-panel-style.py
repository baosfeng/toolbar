#!/usr/bin/env python3
"""面板五页风格一致度量测 — 对 NM_SNAPSHOT_DIR 产出的快照做像素级取证。

用法：
    python3 Scripts/measure-panel-style.py <快照目录> [<对照目录>]

判据（见 docs/设计/面板五页风格统一-设计规格.md）：
- 首行是分页条（28pt，五页同一件，不算页头）
- 分页条之后要有页头行：22pt 高、只放文字不铺底，判据是「条下 2–22pt 内存在非白像素」
  —— 此前只有额度 / Token 有页头，网络 / 剪贴板 / 传送 / 系统第一行直接是内容
- 末行要有状态带：20pt、铺满宽度的实色带；此前只有额度 / Token / 系统有
- 卡片底统一 0xF5F5F7（系统页五张语义分族卡是本页定稿的偏离，单列一栏）

输出为表格，可直接贴进验收报告。
"""
import sys
import os
from PIL import Image

PAGES = [
    ("menu-network-light.png", "网络"),
    ("menu-clipboard-light.png", "剪贴板"),
    ("menu-transfer-light.png", "传送"),
    ("menu-credits-light.png", "额度"),
    ("menu-token-520-light.png", "Token"),
    ("menu-system-light.png", "系统"),
]
WHITE = (255, 255, 255)
TAB_BAR_MAX = 32
BAND_MAX = 22
HEADER_PROBE = 20


def bands(path):
    """满宽填充区块：每块 (y0, y1, 高度, 底色)。"""
    image = Image.open(path).convert("RGB")
    width, height = image.size
    result = []
    inside = False
    start = 0
    for y in range(3, height):
        row = [image.getpixel((x, y)) for x in range(13, width - 13)]
        filled = sum(1 for color in row if color != WHITE) > (width - 26) * 0.85
        if filled and not inside:
            inside, start = True, y
        elif not filled and inside:
            inside = False
            result.append((start, y - 1, y - start, image.getpixel((width // 2, start + 1))))
    if inside:
        result.append((start, height - 1, height - start, image.getpixel((width // 2, start + 1))))
    return image, result


def has_header_text(image, tab_bar_bottom):
    """分页条下方 2–22pt 内是否有文字像素（页头行只放文字、不铺底）。"""
    width, _ = image.size
    for y in range(tab_bar_bottom + 2, tab_bar_bottom + HEADER_PROBE):
        # 页头文字贴着内容左边界起（左右各 12pt 面板内边距）
        for x in range(14, width - 14):
            if image.getpixel((x, y)) != WHITE:
                return True
    return False


def hex_of(color):
    return f"#{color[0]:02X}{color[1]:02X}{color[2]:02X}"


def report(directory, label):
    print(f"\n=== {label}（{directory}）===")
    print(f"{'页面':<7}{'尺寸':<11}{'页头':<7}{'状态带':<8}{'卡片数':<7}{'卡片底色'}")
    for file_name, page in PAGES:
        path = os.path.join(directory, file_name)
        if not os.path.exists(path):
            print(f"{page:<7}缺失")
            continue
        image, blocks = bands(path)
        size = image.size
        tab_bar = blocks[0] if blocks and blocks[0][2] <= TAB_BAR_MAX else None
        rest = blocks[1:] if tab_bar else blocks
        header_text = has_header_text(image, tab_bar[1]) if tab_bar else False
        # 状态带是 20pt 满宽实色底：最后一整块高度 ≤ 20 即判为状态带
        #（剪贴板 / 传送页没有卡片，rest 只有这一块，不能要求 rest 多于一块）
        has_band = bool(rest) and rest[-1][2] <= BAND_MAX
        band = rest[-1] if has_band else None
        cards = rest[:-1] if has_band else rest
        fills = sorted({hex_of(c) for _, _, _, c in cards})
        print(f"{page:<7}{size[0]}×{size[1]:<8}"
              f"{('有' if header_text else '无'):<7}"
              f"{(f'{band[2]}pt' if band else '无'):<8}"
              f"{len(cards):<7}{','.join(fills) if fills else '—'}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    report(sys.argv[1], "当前")
    if len(sys.argv) > 2:
        report(sys.argv[2], "对照")
    return 0


if __name__ == "__main__":
    sys.exit(main())

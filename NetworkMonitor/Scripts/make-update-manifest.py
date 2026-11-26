#!/usr/bin/env python3
"""生成 update.json —— 自动更新器的静态更新通道。

为什么不用 GitHub API 作为唯一数据源：
- 匿名 /releases/latest 每个 IP 每小时只有 60 次额度，用户多了就集体「无法检查」；
- 发布资产还要再走一次 API 才知道下载地址，一次检查两个请求。

做法：把「版本 + 下载地址 + 校验和 + 说明」预先生成一个 JSON，随发布上传。
更新器读固定地址
    https://github.com/<owner>/<repo>/releases/latest/download/update.json
这一条 URL 永远指向最新一次发布的资产（GitHub 的 latest 重定向），
既不吃 API 额度，也不怕限流；读不到时更新器再回退 API（兼容没有该资产的旧发布）。

asset 仍是 universal 包（老更新器只认它，升级路上不能变）；platforms 是增量字段，
给出 arm64 / x86_64 各自的单包，让新更新器只下载自己那一片、少下一半体积。

用法：
    make-update-manifest.py --tag v1.30.0 --dmg dist/Yilan-1.30.0.dmg \
        --platform-dmg arm64=dist/Yilan-1.30.0-arm64.dmg \
        --platform-dmg x86_64=dist/Yilan-1.30.0-x86_64.dmg \
        --notes-file release-notes.md --out update.json
"""

import argparse
import contextlib
import datetime as dt
import hashlib
import io
import json
import os
import re
import sys
import tempfile

# schemaVersion 不动：platforms 是纯增量键，旧更新器按 asset 读不受影响
SCHEMA_VERSION = 1
# 两个架构必须一起发：宁可这一版发不出去，也不要 Intel 用户手里只有 universal 或干脆没包
PLATFORM_ARCHS = ("arm64", "x86_64")


def fail(message: str) -> "None":
    print(f"❌ {message}", file=sys.stderr)
    sys.exit(1)


def parse_tag(tag: str) -> str:
    """v1.30.0 → 1.30.0；不接受其它形状（更新器按语义化三段比对）"""
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)", tag)
    if not match:
        fail(f"tag 要形如 v1.30.0，收到：{tag}")
    return match.group(1)


def minimum_system_version(package_swift: str) -> str:
    """从 Package.swift 的 .macOS(.v14) 推出 14.0 —— 平台下限只有一处真源"""
    with open(package_swift, "r", encoding="utf-8") as handle:
        content = handle.read()
    match = re.search(r"\.macOS\(\.v(\d+)(?:\.(\d+))?\)", content)
    if not match:
        fail(f"在 {package_swift} 里找不到 .macOS(.vNN) 平台声明")
    major = match.group(1)
    minor = match.group(2) or "0"
    return f"{major}.{minor}"


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_platform_dmg(spec: str) -> tuple:
    """arm64=dist/Yilan-1.30.0-arm64.dmg → ("arm64", "dist/Yilan-1.30.0-arm64.dmg")"""
    arch, separator, path = spec.partition("=")
    if not separator or not arch or not path:
        fail(f"--platform-dmg 要形如 arm64=dist/Yilan-1.30.0-arm64.dmg，收到：{spec}")
    if arch not in PLATFORM_ARCHS:
        fail(f"未知架构 {arch}（只支持 {' / '.join(PLATFORM_ARCHS)}）")
    return arch, path


def asset_entry(dmg_path: str, tag: str, repo: str) -> dict:
    """一个 dmg 的下载四元组：名字 / 地址 / 校验和 / 体积（地址与发布资产同名）"""
    name = os.path.basename(dmg_path)
    if not os.path.exists(dmg_path):
        fail(f"找不到 dmg：{dmg_path}")
    return {
        "name": name,
        "url": f"https://github.com/{repo}/releases/download/{tag}/{name}",
        "sha256": sha256_of(dmg_path),
        "byteCount": os.path.getsize(dmg_path),
    }


def build_platforms(platform_dmgs: dict, version: str, tag: str, repo: str) -> dict:
    """单架构资产名必须是 Yilan-<版本>-<arch>.dmg —— 更新器按这个名字挑自己那一片"""
    missing = [arch for arch in PLATFORM_ARCHS if arch not in platform_dmgs]
    if missing:
        fail(f"缺少单架构 dmg：{' / '.join(missing)}（两个架构必须齐全，否则该架构用户拿不到包）")

    platforms = {}
    for arch in PLATFORM_ARCHS:
        path = platform_dmgs[arch]
        expected_name = f"Yilan-{version}-{arch}.dmg"
        if os.path.basename(path) != expected_name:
            fail(f"{arch} 的 dmg 名要形如 {expected_name}，收到：{os.path.basename(path)}")
        platforms[arch] = asset_entry(path, tag, repo)
    return platforms


def build_manifest(tag: str,
                   dmg_path: str,
                   platform_dmgs: dict,
                   notes: str,
                   repo: str,
                   published_at: str,
                   min_system: str) -> dict:
    version = parse_tag(tag)
    dmg_name = os.path.basename(dmg_path)

    # 资产名带上版本号，避免「同一个文件名换内容」让浏览器 / CDN 缓存住旧包
    expected_name = f"Yilan-{version}.dmg"
    if dmg_name != expected_name:
        fail(f"dmg 名要形如 {expected_name}（保证每次发布资产名唯一），收到：{dmg_name}")
    if not os.path.exists(dmg_path):
        fail(f"找不到 dmg：{dmg_path}")
    if not notes.strip():
        fail("发布说明为空：更新器的「新版本说明」会变成一片空白")

    asset = asset_entry(dmg_path, tag, repo)
    asset["architecture"] = "universal"

    return {
        "schemaVersion": SCHEMA_VERSION,
        "tag": tag,
        "version": version,
        "publishedAt": published_at,
        "minimumSystemVersion": min_system,
        "pageURL": f"https://github.com/{repo}/releases/tag/{tag}",
        "notes": notes,
        "asset": asset,
        "platforms": build_platforms(platform_dmgs, version, tag, repo),
    }


def write_manifest(manifest: dict, out_path: str) -> None:
    """先写临时文件再改名：中途失败不会留下半个 update.json"""
    directory = os.path.dirname(os.path.abspath(out_path))
    handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=directory,
                                         delete=False, suffix=".tmp")
    try:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.close()
        os.replace(handle.name, out_path)
    except BaseException:
        handle.close()
        os.unlink(handle.name)
        raise


def expect_failure(action, label: str) -> None:
    """负向用例：该拒绝的没拒绝，就等于把错包发出去了"""
    try:
        action()
    except SystemExit:
        return
    raise AssertionError(f"{label} 时应当失败")


def self_check() -> None:
    """内置断言：这些口径错了，更新器会「看到新版本但装不上」"""
    assert parse_tag("v1.30.0") == "1.30.0"
    # 负向用例的 ❌ 是本函数预期输出，收进缓冲避免污染 CI 日志
    quiet = io.StringIO()
    with contextlib.redirect_stderr(quiet):
        for bad in ["1.30.0", "v1.30", "v1.30.0-beta", "v1.30.0.1"]:
            expect_failure(lambda bad=bad: parse_tag(bad), f"parse_tag 应拒绝 {bad}")

    # 平台下限只有 Package.swift 一处真源：写死会跟随应用升级而漂移
    assert minimum_system_version_from_text(".macOS(.v14)") == "14.0"
    assert minimum_system_version_from_text(".macOS(.v26)") == "26.0"
    assert minimum_system_version_from_text(".macOS(.v14), .iOS(.v17),") == "14.0"

    assert parse_platform_dmg("arm64=dist/Yilan-1.30.0-arm64.dmg") == \
        ("arm64", "dist/Yilan-1.30.0-arm64.dmg")
    with contextlib.redirect_stderr(quiet):
        for bad in ["arm64", "=x.dmg", "arm64=", "amd64=dist/Yilan-1.30.0-amd64.dmg"]:
            expect_failure(lambda bad=bad: parse_platform_dmg(bad),
                           f"parse_platform_dmg 应拒绝 {bad}")

    with tempfile.TemporaryDirectory() as sandbox:
        def fake_dmg(name: str, payload: bytes) -> str:
            path = os.path.join(sandbox, name)
            with open(path, "wb") as handle:
                handle.write(payload)
            return path

        dmg = fake_dmg("Yilan-1.30.0.dmg", b"yilan")
        arm = fake_dmg("Yilan-1.30.0-arm64.dmg", b"arm64!")
        intel = fake_dmg("Yilan-1.30.0-x86_64.dmg", b"intel!!")

        # 正常形状：universal 进 asset，两个单架构进 platforms
        manifest = build_manifest("v1.30.0", dmg, {"arm64": arm, "x86_64": intel},
                                  "说明", "owner/repo", "2026-11-22T00:00:00Z", "14.0")
        assert manifest["version"] == "1.30.0"
        assert manifest["asset"]["url"].endswith("/download/v1.30.0/Yilan-1.30.0.dmg")
        assert manifest["asset"]["byteCount"] == 5
        assert len(manifest["asset"]["sha256"]) == 64
        assert manifest["asset"]["architecture"] == "universal"
        assert set(manifest["platforms"]) == {"arm64", "x86_64"}
        assert manifest["platforms"]["arm64"]["name"] == "Yilan-1.30.0-arm64.dmg"
        assert manifest["platforms"]["x86_64"]["url"].endswith(
            "/download/v1.30.0/Yilan-1.30.0-x86_64.dmg")
        # 清单里的校验和 / 体积必须就是文件本身：写错这一处，用户下载后被校验和拒装
        assert manifest["platforms"]["arm64"]["sha256"] == sha256_of(arm)
        assert manifest["platforms"]["x86_64"]["sha256"] == sha256_of(intel)
        assert manifest["platforms"]["arm64"]["byteCount"] == os.path.getsize(arm)
        assert manifest["platforms"]["x86_64"]["byteCount"] == os.path.getsize(intel)

        with contextlib.redirect_stderr(quiet):
            # 缺一个架构必须拒绝：只发 universal 时 Intel 用户没有可选的单包
            expect_failure(
                lambda: build_manifest("v1.30.0", dmg, {"arm64": arm},
                                       "说明", "owner/repo", "2026-11-22T00:00:00Z", "14.0"),
                "缺少 x86_64 单架构 dmg")

            # 单架构资产名不符必须拒绝：更新器靠名字里的 arch 挑包
            renamed = fake_dmg("Yilan-1.30.0.dmg.arm64", b"arm64!")
            expect_failure(
                lambda: build_manifest("v1.30.0", dmg, {"arm64": renamed, "x86_64": intel},
                                       "说明", "owner/repo", "2026-11-22T00:00:00Z", "14.0"),
                "arm64 dmg 名不符")

            # 单架构 dmg 不存在必须拒绝（发布脚本挑错路径时不能静默）
            expect_failure(
                lambda: build_manifest("v1.30.0", dmg,
                                       {"arm64": os.path.join(sandbox, "nope-arm64.dmg"),
                                        "x86_64": intel},
                                       "说明", "owner/repo", "2026-11-22T00:00:00Z", "14.0"),
                "单架构 dmg 不存在")

            # 资产名与版本不一致必须拒绝：否则「装了 1.30.0 却是 1.29.0 的包」
            expect_failure(
                lambda: build_manifest("v1.30.1", dmg, {"arm64": arm, "x86_64": intel},
                                       "说明", "owner/repo", "2026-11-22T00:00:00Z", "14.0"),
                "dmg 名与 tag 不一致")

            # 说明为空必须拒绝
            expect_failure(
                lambda: build_manifest("v1.30.0", dmg, {"arm64": arm, "x86_64": intel},
                                       "   ", "owner/repo", "2026-11-22T00:00:00Z", "14.0"),
                "发布说明为空")

        out = os.path.join(sandbox, "update.json")
        write_manifest(manifest, out)
        with open(out, encoding="utf-8") as handle:
            reloaded = json.load(handle)
        assert reloaded["schemaVersion"] == SCHEMA_VERSION
        assert reloaded["notes"] == "说明"
        assert reloaded["platforms"]["arm64"]["byteCount"] == os.path.getsize(arm)

    print("✅ update.json 生成器自检通过")


def minimum_system_version_from_text(text: str) -> str:
    match = re.search(r"\.macOS\(\.v(\d+)(?:\.(\d+))?\)", text)
    assert match, "缺少 .macOS(.vNN)"
    return f"{match.group(1)}.{match.group(2) or '0'}"


def main() -> None:
    parser = argparse.ArgumentParser(description="生成自动更新器的静态更新通道 update.json")
    parser.add_argument("--tag", help="发布 tag（v1.30.0）")
    parser.add_argument("--dmg", help="universal dmg 路径（写进 asset）")
    parser.add_argument("--platform-dmg", action="append", default=[], metavar="ARCH=PATH",
                        help="单架构 dmg，可重复：--platform-dmg arm64=… --platform-dmg x86_64=…")
    parser.add_argument("--notes-file", help="发布说明 markdown 文件")
    parser.add_argument("--out", default="update.json", help="输出路径")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "baosfeng/toolbar"))
    parser.add_argument("--published-at", default=None, help="ISO8601 发布时间，默认当前 UTC")
    parser.add_argument("--min-system-from", default=None, help="从中解析最低系统版本的 Package.swift")
    parser.add_argument("--self-check", action="store_true", help="只跑内置断言")
    args = parser.parse_args()

    if args.self_check:
        self_check()
        return

    if not (args.tag and args.dmg and args.notes_file):
        parser.error("--tag / --dmg / --notes-file 都是必填")
    if not args.platform_dmg:
        parser.error("--platform-dmg 至少给一次（arm64 与 x86_64 必须齐全）")

    platform_dmgs = dict(parse_platform_dmg(spec) for spec in args.platform_dmg)

    with open(args.notes_file, encoding="utf-8") as handle:
        notes = handle.read()

    published_at = args.published_at or dt.datetime.now(dt.timezone.utc) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")

    if args.min_system_from:
        min_system = minimum_system_version(args.min_system_from)
    else:
        min_system = "14.0"

    manifest = build_manifest(args.tag, args.dmg, platform_dmgs, notes, args.repo,
                              published_at, min_system)
    write_manifest(manifest, args.out)
    print(f"✅ 已生成 {args.out}（{manifest['version']}，"
          f"universal {manifest['asset']['byteCount']} 字节 + "
          f"{'/'.join(PLATFORM_ARCHS)} 单架构包）")


if __name__ == "__main__":
    main()

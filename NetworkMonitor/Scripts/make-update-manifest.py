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

用法：
    make-update-manifest.py --tag v1.30.0 --dmg dist/Yilan-1.30.0.dmg \
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

SCHEMA_VERSION = 1


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


def build_manifest(tag: str,
                   dmg_path: str,
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

    return {
        "schemaVersion": SCHEMA_VERSION,
        "tag": tag,
        "version": version,
        "publishedAt": published_at,
        "minimumSystemVersion": min_system,
        "pageURL": f"https://github.com/{repo}/releases/tag/{tag}",
        "notes": notes,
        "asset": {
            "name": dmg_name,
            "url": f"https://github.com/{repo}/releases/download/{tag}/{dmg_name}",
            "sha256": sha256_of(dmg_path),
            "byteCount": os.path.getsize(dmg_path),
            "architecture": "universal",
        },
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


def self_check() -> None:
    """内置断言：这些口径错了，更新器会「看到新版本但装不上」"""
    assert parse_tag("v1.30.0") == "1.30.0"
    # 负向用例的 ❌ 是本函数预期输出，收进缓冲避免污染 CI 日志
    quiet = io.StringIO()
    with contextlib.redirect_stderr(quiet):
        for bad in ["1.30.0", "v1.30", "v1.30.0-beta", "v1.30.0.1"]:
            try:
                parse_tag(bad)
            except SystemExit:
                pass
            else:
                raise AssertionError(f"parse_tag 应当拒绝 {bad}")

    # 平台下限只有 Package.swift 一处真源：写死会跟随应用升级而漂移
    assert minimum_system_version_from_text(".macOS(.v14)") == "14.0"
    assert minimum_system_version_from_text(".macOS(.v26)") == "26.0"
    assert minimum_system_version_from_text(".macOS(.v14), .iOS(.v17),") == "14.0"

    with tempfile.TemporaryDirectory() as sandbox:
        dmg = os.path.join(sandbox, "Yilan-1.30.0.dmg")
        with open(dmg, "wb") as handle:
            handle.write(b"yilan")
        manifest = build_manifest("v1.30.0", dmg, "说明", "owner/repo",
                                   "2026-11-22T00:00:00Z", "14.0")
        assert manifest["version"] == "1.30.0"
        assert manifest["asset"]["url"].endswith("/download/v1.30.0/Yilan-1.30.0.dmg")
        assert manifest["asset"]["byteCount"] == 5
        assert len(manifest["asset"]["sha256"]) == 64

        with contextlib.redirect_stderr(quiet):
            # 资产名与版本不一致必须拒绝：否则「装了 1.30.0 却是 1.29.0 的包」
            try:
                build_manifest("v1.30.1", dmg, "说明", "owner/repo",
                                "2026-11-22T00:00:00Z", "14.0")
            except SystemExit:
                pass
            else:
                raise AssertionError("dmg 名与 tag 不一致时应当失败")

            # 说明为空必须拒绝
            try:
                build_manifest("v1.30.0", dmg, "   ", "owner/repo",
                                "2026-11-22T00:00:00Z", "14.0")
            except SystemExit:
                pass
            else:
                raise AssertionError("发布说明为空时应当失败")

        out = os.path.join(sandbox, "update.json")
        write_manifest(manifest, out)
        with open(out, encoding="utf-8") as handle:
            reloaded = json.load(handle)
        assert reloaded["schemaVersion"] == SCHEMA_VERSION
        assert reloaded["notes"] == "说明"

    print("✅ update.json 生成器自检通过")


def minimum_system_version_from_text(text: str) -> str:
    match = re.search(r"\.macOS\(\.v(\d+)(?:\.(\d+))?\)", text)
    assert match, "缺少 .macOS(.vNN)"
    return f"{match.group(1)}.{match.group(2) or '0'}"


def main() -> None:
    parser = argparse.ArgumentParser(description="生成自动更新器的静态更新通道 update.json")
    parser.add_argument("--tag", help="发布 tag（v1.30.0）")
    parser.add_argument("--dmg", help="universal dmg 路径")
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

    with open(args.notes_file, encoding="utf-8") as handle:
        notes = handle.read()

    published_at = args.published_at or dt.datetime.now(dt.timezone.utc) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")

    if args.min_system_from:
        min_system = minimum_system_version(args.min_system_from)
    else:
        min_system = "14.0"

    manifest = build_manifest(args.tag, args.dmg, notes, args.repo, published_at, min_system)
    write_manifest(manifest, args.out)
    print(f"✅ 已生成 {args.out}（{manifest['version']}，{manifest['asset']['byteCount']} 字节）")


if __name__ == "__main__":
    main()

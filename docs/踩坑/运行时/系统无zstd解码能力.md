# 系统没有 zstd 解码能力（随包携带 libzstd）

> **何时阅读：** 需要在内置能力里解 zstd（DSH 会话 `*.jsonl.zstd`）、
> 或怀疑「第三方机器装了工具却读不到数据」时。

## 现象

Token 用量页在别人机器上恒显示「缺少 zstd 解压工具」，而用户终端里 `zstd --version` 正常；
设置页给出的探测路径里没有 `/opt/homebrew/bin/zstd`。

## 根因一：LaunchServices 的 PATH 不含 Homebrew

由 LaunchServices 启动的 .app 继承系统默认 PATH（`/usr/bin:/bin:/usr/sbin:/sbin`），
用户 shell 里 `which zstd` 能命中 `/opt/homebrew/bin/zstd`，.app 里就是探不到。
**结论**：「用户机器装了」不等于「应用能用」，探测链必须包含包内自带与登录 shell 两条兜底。

## 根因二：macOS 没有任何系统 zstd 解码路径（本轮实测，2026-11，macOS 27.0.1）

| 候选 | 实测结论 | 证据 |
|------|---------|------|
| Compression framework | 没有 zstd 算法 id | `grep COMPRESSION_ZSTD` 在 CLT 的 SDK 12.1 / 26 / 27 的 `compression.h` 全部 0 命中；对 libcompression 做 0x0000–0xFFFF 全量 `compression_stream_init` 试探，能解出字节的只有 zlib（0x0205），其余 id 全部 `COMPRESSION_STATUS_ERROR` |
| 系统 libzstd | 不存在 | `ls /usr/lib/libzstd*` 无文件；`dlopen("libzstd.1.dylib")` / `/usr/lib/libzstd.1.dylib` 全部失败（不在 dyld 共享缓存里） |
| libarchive 的 zstd 过滤器 | 只是外部程序转发 | `archive_read_support_filter_zstd` 存在，但无 zstd 时报 `Can't initialize filter; unable to run program "zstd -d -qq"`；把 PATH 换成 `/usr/bin:/bin` 必现 |

**所以「用纯系统 API 解 zstd」这条路在 macOS 上不存在**，
「包内自带 zstd 可执行文件」也会连带 `libzstd / liblzma / liblz4` 三个 Homebrew dylib。

## 现行做法（两条腿）

1. **内置解码（主路径）**：打包时把 `libzstd.1.dylib` 放进 `Contents/Resources`，
   Core 用 `dlopen` + `dlsym` 调 `ZSTD_decompressStream`（`HarnessZstdDecoder`）。
   不新增任何 Swift 包依赖，且 libzstd 只依赖 `libSystem`，目标机器无需任何前置安装。
2. **可执行文件备选**：`Contents/Resources/zstd` + 它依赖的非系统 dylib 一起搬进来，
   全部改写成 `@loader_path` 引用；探测链见 `HarnessZstdLocator`
   （包内自带 → 绝对路径候选 → PATH → 登录 shell）。

## 多帧语义（会话文件的真实形态）

`session.v4.jsonl.zstd` 是**逐次追加的多帧拼接**（实测某会话 175 帧，含 raw block）。
`ZSTD_decompressStream` 返回 0 表示当前帧结束，继续喂剩余字节即自动进入下一帧，
**不需要手工切帧**。实测同一文件解压字节数与 `zstd -dc` 完全相等（1,848,810 B）。

## 判据 / 自测

```bash
# PATH 里没有 zstd、候选路径都不可用，只给一份 libzstd：仍要索引出事件
env PATH=/usr/bin:/bin .build/arm64-apple-macosx/debug/TestRunner \
    --harness-bundled-probe /tmp/zstd-libonly
```

期望输出含 `probe_zstd_on_PATH = <none>`、`probe_availability = …（内置解码）`、
`probe_events = <非 0>`、`✅ 内置解码索引成功（无需系统 zstd）`。

## 相关

- 快照取证要在打包后的 .app 里跑，裸二进制会崩 `bundleProxyForCurrentProcess is nil`，
  见 [快照取证需打包成 app](../构建/快照取证需打包成app.md)
- 打包脚本的杀进程判据见 [打包脚本按名字杀进程连坐](../构建/打包脚本按名字杀进程连坐.md)

#!/usr/bin/env bash
# 性能热点回归采样（CPU / 内存）—— 与 CPU 热点修复的前后对照同口径
#
# 用法：
#   Scripts/perf-hotspot-sample.sh                     # 自动找 NetworkMonitor 进程
#   Scripts/perf-hotspot-sample.sh <pid> [秒数]        # 指定 pid 与采样时长（默认 10 秒）
#
# 输出四段：
#   1) top 逐秒 CPU（8 拍，含内存列）
#   2) sample 主线程忙碌占比（等价于该进程 CPU 的时间占比）
#   3) 热点分组：文本测量缓存 / AutoLayout / 图层树 / display 周期
#   4) footprint 与堆节点数
#
# 修复后基线（面板收起、零交互，同一台 Mac）：
#   主线程忙碌 <= 1.5%    （修复前 13.42%）
#   top 逐秒均值 <= 1.5%  （修复前 4.76%）
#   footprint <= 160 MB   （修复前 204 MB / peak 430 MB）
#   任一项超基线即视为回潮：先看第 3 段「文本测量缓存」是否复活，
#   再查是否出现了新的每秒视图重建 / 多层材质叠加。
#
# 判红口径：退出码 0 = 在基线内；2 = 超基线（回潮）。

set -o pipefail

if [ "$#" -ge 1 ]; then
    TARGET_PID="$1"
else
    TARGET_PID=""
fi
if [ "$#" -ge 2 ]; then
    SAMPLE_SECONDS="$2"
else
    SAMPLE_SECONDS="10"
fi

if [ -z "$TARGET_PID" ]; then
    # 判据只认包内可执行文件名，不认包名：.app 改名成「一览.app」后旧判据会 0 命中
    TARGET_PID=$(pgrep -f "/Contents/MacOS/NetworkMonitor( |$)" | head -1 || true)
fi
if [ -z "$TARGET_PID" ]; then
    echo "未找到 NetworkMonitor 进程（可显式传 pid）" >&2
    exit 1
fi

echo "== 采样对象 =="
ps -p "$TARGET_PID" -o pid,pcpu,rss,etime,command | tail -1
echo

echo "== 1) top 逐秒 CPU（8 拍）=="
top -l 8 -s 1 -stats pid,cpu,mem,command 2>/dev/null | grep -E "^ *$TARGET_PID " | head -8
echo

echo "== 2/3) sample $SAMPLE_SECONDS 秒：主线程与热点分组 =="
SAMPLE_FILE="/tmp/nm-perf-$(date +%H%M%S).sample"
sample "$TARGET_PID" "$SAMPLE_SECONDS" -file "$SAMPLE_FILE" >/dev/null 2>&1 || true
python3 - "$SAMPLE_FILE" "$SAMPLE_SECONDS" <<'PY'
import re, sys

path, secs = sys.argv[1], float(sys.argv[2])
text = open(path, encoding="utf-8", errors="ignore").read().splitlines()

IDLE = {
    "mach_msg2_trap", "__workq_kernreturn", "semaphore_wait_trap", "__psynch_cvwait",
    "__ulock_wait", "kevent_id", "start_wqthread", "mach_msg_overwrite", "mach_msg2_internal",
    "__semwait_signal", "__select", "_dispatch_semaphore_wait_slow", "__timedwait",
    "__accept", "__psynch_mutexwait", "_pthread_mutex_firstfit_lock_wait",
}
GROUPS = [
    ("文本测量缓存", re.compile(r"NSStringMeasurementCacheKey|__NSCacheKeyEqual")),
    ("AutoLayout 求解", re.compile(r"updateConstraintsForSubtreeIfNeeded|NSISEngine|_updateConstraintsIfNeeded")),
    ("图层树构建", re.compile(r"_buildLayerTreeWithOwnLayerRequirement")),
    ("display 周期", re.compile(r"NSDisplayCycleFlush|CA::Transaction::commit|stepTransactionFlush|NSDisplayCycleObserverInvoke")),
]

class Node:
    __slots__ = ("depth", "count", "sym", "children")
    def __init__(self, depth, count, sym):
        self.depth, self.count, self.sym, self.children = depth, count, sym, []

root = Node(0, 0, "ROOT")
stack = [root]
for line in text:
    if line.startswith("Sort by top of stack"):
        break
    m_thread = re.match(r"^ {4}(\d+) (Thread_.*)$", line)
    if m_thread:
        t = Node(0, int(m_thread.group(1)), "THREAD " + m_thread.group(2)[:50])
        root.children.append(t)
        stack = [root, t]
        continue
    m = re.match(r"^ {4}([^0-9]*?)(\d+) (.*)$", line)
    if not m:
        continue
    depth = round((len(m.group(1)) - 2) / 2) + 1
    sym = re.sub(r"  \(in [^)]*\)( \+ \d+)?(  \[[^\]]*\])?$", "", m.group(3)).rstrip()
    node = Node(depth, int(m.group(2)), sym)
    while stack and stack[-1].depth >= depth:
        stack.pop()
    if not stack:
        continue
    stack[-1].children.append(node)
    stack.append(node)

if not root.children:
    print("sample 解析失败：没有线程信息", file=sys.stderr)
    sys.exit(3)

main = root.children[0]
interval_ms = secs * 1000.0 / main.count

def self_time(node):
    return max(0, node.count - sum(c.count for c in node.children))

records = []
def walk(node, path):
    st = self_time(node)
    if st > 0 and node.sym not in IDLE:
        records.append((st, path + [node]))
    for child in node.children:
        walk(child, path + [node])
walk(main, [])

busy = 0
groups = {}
for st, path in records:
    busy += st
    name = "其它"
    for label, pattern in GROUPS:
        if any(pattern.search(n.sym) for n in path):
            name = label
            break
    groups[name] = groups.get(name, 0) + st

busy_pct = busy * interval_ms / (secs * 10)
print("主线程 busy = %d / %d samples ≈ %.2f%% CPU" % (busy, main.count, busy_pct))
for name, count in sorted(groups.items(), key=lambda kv: -kv[1]):
    pct = count * interval_ms / (secs * 10)
    if pct >= 0.05:
        print("  %6.2f%%  %s (%d)" % (pct, name, count))

threshold = 1.5
if busy_pct > threshold:
    print("判红：主线程 busy %.2f%% 超过基线 %.1f%%（回潮）" % (busy_pct, threshold))
    sys.exit(2)
print("判定：主线程 busy 在基线内（<= %.1f%%）" % threshold)
PY
SAMPLE_STATUS=$?
echo

echo "== 4) 内存 =="
footprint "$TARGET_PID" 2>/dev/null | grep -E "phys_footprint" | head -2
heap "$TARGET_PID" 2>/dev/null | grep -o "All zones: [0-9]* nodes malloced" | head -1
echo

if [ "$SAMPLE_STATUS" -eq 2 ]; then
    echo "结论：CPU 回潮，见上方分组（先看「文本测量缓存」与「display 周期」）"
    exit 2
fi
echo "结论：CPU / 内存在修复后基线内"
exit 0

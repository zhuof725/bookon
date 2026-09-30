#!/bin/bash
# 在可用的 iPhone 模拟器上用 xcodebuild test 跑全部测试 target。
set -euo pipefail

# 固定 scheme（不取列表第一个）。本 SwiftPM 包被 xcodebuild 打开时，
# 自动生成的唯一 scheme 名等于 package/library 名 "LegadoBookSource"
# （`-list` 实测：Schemes 只有 LegadoBookSource；"-Package" 后缀 scheme 在本包不存在）。
SCHEME="LegadoBookSource"
echo "使用 scheme: $SCHEME"
echo "可用 scheme 列表（供核对）："
xcodebuild -list || true

# 选一个可用的 iPhone 模拟器 UDID。
UDID=$(xcrun simctl list devices available -j | python3 -c '
import sys, json
d = json.load(sys.stdin)
found = ""
for runtime, arr in d["devices"].items():
    if "iOS" not in runtime:
        continue
    for dev in arr:
        if dev.get("isAvailable") and "iPhone" in dev.get("name", ""):
            found = dev["udid"]
            break
    if found:
        break
print(found)
')
echo "使用模拟器 UDID: $UDID"

if [ -z "$UDID" ]; then
  echo "错误：未找到可用 iPhone 模拟器"
  exit 1
fi

# 运行测试，同时把输出留存到文件以便统计执行的测试数。
LOG=$(mktemp)
set +e
xcodebuild test \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | tee "$LOG"
XC_STATUS=${PIPESTATUS[0]}
set -e

# 统计「实际执行的测试总数」：汇总所有 "Executed N tests" 里的 N。
# 每个测试 bundle 会打印两行相同的汇总，故按「Test Suite 'All tests' ... Executed」去重不可靠；
# 这里直接对每个 xctest bundle 的顶层 "Test Suite '*.xctest'" 后的 Executed 求和。
TOTAL=$(python3 - "$LOG" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
# 顶层 bundle 汇总紧跟在 "Test Suite '....xctest' passed/failed" 之后的
# "Executed N tests" 行。用 bundle 级别的汇总求和，避免把每个 suite 都算进去。
total = 0
lines = text.splitlines()
for i, ln in enumerate(lines):
    if re.search(r"Test Suite '.*\.xctest' (passed|failed)", ln):
        # 向下找最近的 Executed 行
        for j in range(i+1, min(i+4, len(lines))):
            m = re.search(r"Executed (\d+) test", lines[j])
            if m:
                total += int(m.group(1))
                break
print(total)
PY
)

echo "==================================================="
echo "iOS 模拟器实际执行的测试总数: $TOTAL"
echo "xcodebuild 退出码: $XC_STATUS"
echo "==================================================="

if [ "$XC_STATUS" -ne 0 ]; then
  echo "错误：xcodebuild test 失败（退出码 $XC_STATUS）"
  exit "$XC_STATUS"
fi

if [ "$TOTAL" -eq 0 ]; then
  echo "错误：实际执行的测试数为 0，视为失败（可能未链接测试 target 或 destination 错误）"
  exit 1
fi

echo "iOS 模拟器测试通过，共执行 $TOTAL 个测试。"

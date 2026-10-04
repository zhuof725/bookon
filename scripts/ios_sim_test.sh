#!/bin/bash
# 在可用的 iPhone 模拟器上用 xcodebuild test 跑全部测试 target。
#
# 测试总数核对（第 4 步收尾新增）：
#   - macOS job（swift test）把它的 "All tests" Executed 总数写进 artifact `macos-test-count`
#     里的 macos_test_count.txt；本脚本在 CI 下会读取该文件。
#   - iOS 这边用 xcodebuild，按「每个 *.xctest bundle 的顶层 Executed」求和得出 iOS 总数。
#   - 若 macOS 总数文件存在，则 iOS 总数必须与它相等，否则判定为「有 target 没跑」并让 job 失败。
#   - 若该文件不存在（例如本地单独运行、未经 macOS job），则跳过相等性核对，仅保证 iOS 总数 > 0。
set -euo pipefail

# 固定 scheme（不取列表第一个）。本 SwiftPM 包被 xcodebuild 打开时，
# 自动生成的唯一 scheme 名等于 package/library 名 "LegadoBookSource"。
SCHEME="LegadoBookSource"
echo "使用 scheme: ${SCHEME}"
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
echo "使用模拟器 UDID: ${UDID}"

if [ -z "${UDID}" ]; then
  echo "错误：未找到可用 iPhone 模拟器"
  exit 1
fi

# 运行测试，同时把输出留存到文件以便统计执行的测试数。
LOG=$(mktemp)
set +e
xcodebuild test \
  -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,id=${UDID}" \
  2>&1 | tee "${LOG}"
XC_STATUS=${PIPESTATUS[0]}
set -e

# 统计 iOS 总数：对每个 *.xctest bundle 的顶层汇总 "Executed N tests" 求和，并打印逐个 bundle。
# （不按 "Test Suite 'All tests'" 去重——xcodebuild 每个 bundle 都会打印自己的 All tests 汇总，
#  会导致重复；bundle 级别的 "Test Suite '<Name>.xctest'" 汇总行每个 bundle 恰好一次，最可靠。）
TOTAL=$(python3 - "${LOG}" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8", errors="ignore").read().splitlines()
total = 0
print("---- iOS 各 xctest bundle 执行数 ----", file=sys.stderr)
for i, ln in enumerate(lines):
    m = re.search(r"Test Suite '([A-Za-z0-9_]+\.xctest)' (passed|failed)", ln)
    if not m:
        continue
    name = m.group(1)
    for j in range(i + 1, min(i + 4, len(lines))):
        e = re.search(r"Executed (\d+) test", lines[j])
        if e:
            n = int(e.group(1))
            total += n
            print(f"  {name}: {n}", file=sys.stderr)
            break
print(total)
PY
)

echo "==================================================="
echo "iOS 模拟器实际执行的测试总数: ${TOTAL}"
echo "xcodebuild 退出码: ${XC_STATUS}"
echo "==================================================="

if [ "${XC_STATUS}" -ne 0 ]; then
  echo "错误：xcodebuild test 失败（退出码 ${XC_STATUS}）"
  exit "${XC_STATUS}"
fi

if [ "${TOTAL}" -eq 0 ]; then
  echo "错误：实际执行的测试数为 0，视为失败（可能未链接测试 target 或 destination 错误）"
  exit 1
fi

# 与 macOS 总数核对（CI 下由 test-macos job 的 artifact 提供）。
MACOS_COUNT_FILE="${MACOS_COUNT_FILE:-macos-test-count/macos_test_count.txt}"
if [ -f "${MACOS_COUNT_FILE}" ]; then
  MACOS_TOTAL=$(tr -dc '0-9' < "${MACOS_COUNT_FILE}")
  echo "macOS 测试总数（来自 artifact）: ${MACOS_TOTAL}"
  if [ -z "${MACOS_TOTAL}" ]; then
    echo "错误：macOS 测试总数文件内容无效：${MACOS_COUNT_FILE}"
    exit 1
  fi
  if [ "${TOTAL}" -ne "${MACOS_TOTAL}" ]; then
    echo "错误：iOS 测试总数（${TOTAL}）与 macOS 测试总数（${MACOS_TOTAL}）不相等。"
    echo "       这通常意味着某个测试 target/bundle 在 iOS 上没有被跑到。请检查上面逐 bundle 的执行数。"
    exit 1
  fi
  echo "✅ iOS 总数与 macOS 总数一致（均为 ${TOTAL}）。"
else
  echo "注意：未找到 macOS 总数文件（${MACOS_COUNT_FILE}），跳过 iOS==macOS 相等性核对（仅保证 iOS 总数 > 0）。"
fi

echo "iOS 模拟器测试通过，共执行 ${TOTAL} 个测试。"

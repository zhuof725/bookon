#!/bin/bash
# 在可用的 iPhone 模拟器上用 xcodebuild test 跑全部测试 target。
set -euo pipefail

echo "可用 scheme 列表："
xcodebuild -list || true

# SwiftPM 包的自动 scheme 名通常等于 package/library 名；取第一个 scheme。
SCHEME=$(xcodebuild -list -json 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin)
info = d.get("workspace") or d.get("project") or {}
schemes = info.get("schemes", [])
print(schemes[0] if schemes else "LegadoBookSource")
')
echo "选用 scheme: $SCHEME"

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
  echo "未找到可用 iPhone 模拟器，退回按名称指定"
  xcodebuild test -scheme "$SCHEME" -destination 'platform=iOS Simulator,name=iPhone 15'
else
  xcodebuild test -scheme "$SCHEME" -destination "platform=iOS Simulator,id=$UDID"
fi

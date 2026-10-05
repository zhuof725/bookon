#!/bin/bash
# 校验 XcodeGen 生成的 .xcodeproj 的 objectVersion 能被当前 Xcode 读取。
#
# 背景（CI run 37297969936）：
#   XcodeGen 2.44+ 默认 projectFormat = `xcode16_0`，写出 `objectVersion = 77`；
#   而 macos-14 runner 的 Xcode 15.4 **读不了** 77，xcodebuild 直接报
#     Unable to read project '…'
#     Reason: … future Xcode project file format (77) …
#   报错信息不指向 project.yml，排查成本高。这里在 generate 之后、build 之前显式校验，
#   失败时直接指出「哪个 objectVersion、当前 Xcode 读得读到多少、怎么改」。
#
# 用法：bash scripts/verify_xcodeproj_format.sh [BookonDebug.xcodeproj]
set -euo pipefail

PROJ="${1:-BookonDebug.xcodeproj}"
PBXPROJ="$PROJ/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
  echo "错误：找不到 $PBXPROJ（请先运行 xcodegen generate）"
  exit 1
fi

OBJ_VER=$(grep -m1 -oE 'objectVersion = [0-9]+' "$PBXPROJ" | grep -oE '[0-9]+' || true)
if [ -z "$OBJ_VER" ]; then
  echo "错误：无法从 $PBXPROJ 解析 objectVersion"
  exit 1
fi

# 当前 Xcode 版本（形如 "Xcode 15.4" / "Xcode 16.0"）
XCODE_STR=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
XCODE_MAJOR="${XCODE_STR%%.*}"
echo "当前 Xcode: ${XCODE_STR:-unknown}（major=${XCODE_MAJOR:-?}）"
echo "生成的工程 objectVersion = $OBJ_VER"

# objectVersion 与 Xcode 的对应关系（XcodeGen projectFormat 映射）：
#   xcode14_0 -> 56 ; xcode15_0 -> 60 ; xcode15_3 -> 60 ; xcode16_0 -> 77 ; xcode16_3 -> 77
# Xcode 15.x 最高读 60；Xcode 16.x 读 77。
if [ -z "${XCODE_MAJOR:-}" ]; then
  echo "警告：无法确定 Xcode 主版本，跳过兼容性判定"
  exit 0
fi

if [ "$XCODE_MAJOR" -lt 16 ] && [ "$OBJ_VER" -gt 60 ]; then
  echo "❌ 不兼容：Xcode $XCODE_STR 读不了 objectVersion $OBJ_VER（> 60）。"
  echo "   请在 project.yml 的 options 里设置 projectFormat（如 xcode15_3），再重新 xcodegen generate。"
  exit 1
fi

echo "✅ objectVersion $OBJ_VER 与 Xcode $XCODE_STR 兼容"

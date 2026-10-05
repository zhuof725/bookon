#!/bin/bash
# 校验 XcodeGen 生成的 .xcodeproj 的 objectVersion 能被当前 Xcode 读取。
#
# 背景（CI run 37297969936）：
#   XcodeGen 2.44+ 默认 projectFormat = `xcode16_0`，写出 `objectVersion = 77`；
#   而 macos-14 runner 的 Xcode 15.4 读不了 77，xcodebuild 直接报
#     Unable to read project '...'
#     Reason: ... future Xcode project file format (77) ...
#   报错信息不指向 project.yml，排查成本高。这里在 generate 之后、build 之前显式校验，
#   失败时直接指出「objectVersion 是多少、需要哪个 Xcode、怎么改」。
#
# 用法：bash scripts/verify_xcodeproj_format.sh [BookonDebug.xcodeproj]
set -euo pipefail

PROJ="${1:-BookonDebug.xcodeproj}"
PBXPROJ="$PROJ/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
  echo "错误：找不到 ${PBXPROJ}（请先运行 xcodegen generate）"
  exit 1
fi

OBJ_VER=$(grep -m1 -oE 'objectVersion = [0-9]+' "${PBXPROJ}" | grep -oE '[0-9]+' || true)
if [ -z "${OBJ_VER}" ]; then
  echo "错误：无法从 ${PBXPROJ} 解析 objectVersion"
  exit 1
fi

# objectVersion -> 能读它的最低 Xcode（主.次）。
# 权威来源：CocoaPods/Xcodeproj 的 COMPATIBILITY_VERSION_BY_OBJECT_VERSION
#   77 => Xcode 16.0 ; 63 => Xcode 15.3 ; 60 => Xcode 15.0 ;
#   56 => Xcode 14.0 ; 55 => Xcode 13.0 ; 54 => Xcode 12.0
# XcodeGen 的 projectFormat 取值与之一一对应：
#   xcode16_0/xcode16_3 -> 77 ; xcode15_3 -> 63 ; xcode15_0 -> 60 ; xcode14_0 -> 56
REQUIRED_XCODE=""
case "${OBJ_VER}" in
  77) REQUIRED_XCODE="16.0" ;;
  63) REQUIRED_XCODE="15.3" ;;
  60) REQUIRED_XCODE="15.0" ;;
  56) REQUIRED_XCODE="14.0" ;;
  55) REQUIRED_XCODE="13.0" ;;
  54) REQUIRED_XCODE="12.0" ;;
  *)  REQUIRED_XCODE="" ;;   # 未知版本：无法判定，只提示
esac

# 当前 Xcode 版本（形如 "Xcode 15.4" / "Xcode 16.0"）
XCODE_STR=""
if command -v xcodebuild >/dev/null 2>&1; then
  XCODE_STR=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
fi

if [ -z "${XCODE_STR}" ]; then
  echo "警告：无法确定 Xcode 版本（可能不在 macOS 上），跳过兼容性判定"
  exit 0
fi

XCODE_MAJOR="${XCODE_STR%%.*}"
XCODE_MINOR="${XCODE_STR#*.}"
XCODE_MINOR="${XCODE_MINOR%%.*}"
echo "当前 Xcode: ${XCODE_STR}（major=${XCODE_MAJOR} minor=${XCODE_MINOR}）"
echo "生成的工程 objectVersion = ${OBJ_VER}（需 Xcode ${REQUIRED_XCODE:-未知} 及以上）"

if [ -z "${REQUIRED_XCODE}" ]; then
  echo "警告：objectVersion ${OBJ_VER} 不在已知映射表中，无法判定兼容性"
  exit 0
fi

REQ_MAJOR="${REQUIRED_XCODE%%.*}"
REQ_MINOR="${REQUIRED_XCODE#*.}"

# 版本比较：当前 Xcode 是否 >= 所需版本。
IS_OLD=0
if [ "${XCODE_MAJOR}" -lt "${REQ_MAJOR}" ]; then
  IS_OLD=1
elif [ "${XCODE_MAJOR}" -eq "${REQ_MAJOR}" ] && [ "${XCODE_MINOR}" -lt "${REQ_MINOR}" ]; then
  IS_OLD=1
fi

if [ "${IS_OLD}" -eq 1 ]; then
  # 变量后紧跟全角括号时必须用 ${VAR}：bash 会把全角括号的字节并进变量名，
  # 配合 set -u 会立即报 unbound variable（CI run 37300771895 即栽在这里）。
  echo "不兼容：当前 Xcode ${XCODE_STR} 读不了 objectVersion ${OBJ_VER}（需要 Xcode ${REQUIRED_XCODE} 及以上）。"
  echo "   修复：在 project.yml 的 options 里下调 projectFormat（如 xcode15_3 / xcode15_0），再重新 xcodegen generate。"
  exit 1
fi

echo "objectVersion ${OBJ_VER} 与当前 Xcode ${XCODE_STR} 兼容"

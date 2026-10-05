#!/bin/bash
# 校验 XcodeGen 生成的 .xcodeproj 的 objectVersion 能被当前 Xcode 读取。
#
# 背景（CI run 37297969936）：
#   XcodeGen 2.44+ 默认 projectFormat = `xcode16_0`，写出 `objectVersion = 77`；
#   而 macos-14 runner 的 Xcode 15.4 读不了 77，xcodebuild 直接报
#     Unable to read project '...'
#     Reason: ... future Xcode project file format (77) ...
#   报错信息不指向 project.yml，排查成本高。这里在 generate 之后、build 之前显式校验，
#   失败时直接指出 objectVersion 与所需 Xcode 版本。
#
# 设计约束（踩过的坑，勿回退）：
#   1. 不解析 pbxproj 之外的任何东西；objectVersion 用 awk 按行取，**不用 grep 管道**
#      （macOS BSD grep + 非 UTF-8 注释字节会触发下游 SIGABRT）。
#   2. 全脚本 ASCII-only 可执行行；输出用 printf 到 stderr 并显式 flush 思路处理
#      （abort 时管道缓冲会丢日志）。
#   3. 任何探测失败都不 abort 整个 CI 步骤：最坏情况只提示并 exit 0，让 xcodebuild 自己去报错。
#
# 用法：bash scripts/verify_xcodeproj_format.sh [BookonDebug.xcodeproj]
set -u

PROJ="${1:-BookonDebug.xcodeproj}"
PBXPROJ="$PROJ/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
  echo "[verify_xcodeproj_format] ERROR: $PBXPROJ not found (run xcodegen generate first)"
  exit 1
fi

# --- 提取 objectVersion（awk，无管道） ---------------------------------------
OBJ_VER=""
OBJ_VER=$(awk -F'[ =;]+' '/objectVersion/ { print $2; exit }' "$PBXPROJ" 2>/dev/null) || OBJ_VER=""
OBJ_VER=$(printf '%s' "$OBJ_VER" | tr -cd '0-9' 2>/dev/null) || OBJ_VER=""
if [ -z "$OBJ_VER" ]; then
  echo "[verify_xcodeproj_format] ERROR: cannot parse objectVersion from $PBXPROJ"
  exit 1
fi

# --- objectVersion -> 所需最低 Xcode ----------------------------------------
# 权威映射（CocoaPods/Xcodeproj COMPATIBILITY_VERSION_BY_OBJECT_VERSION）：
#   77 -> 16.0 ; 63 -> 15.3 ; 60 -> 15.0 ; 56 -> 14.0 ; 55 -> 13.0 ; 54 -> 12.0
REQUIRED_XCODE=""
case "$OBJ_VER" in
  77) REQUIRED_XCODE="16.0" ;;
  63) REQUIRED_XCODE="15.3" ;;
  60) REQUIRED_XCODE="15.0" ;;
  56) REQUIRED_XCODE="14.0" ;;
  55) REQUIRED_XCODE="13.0" ;;
  54) REQUIRED_XCODE="12.0" ;;
  *)  REQUIRED_XCODE="" ;;
esac

# --- 当前 Xcode 版本 --------------------------------------------------------
# 优先用 plutil 读 Xcode.app/Contents/version.plist 的 CFBundleShortVersionString
# （plutil 是 macOS 自带、可靠）；避免调用 `xcodebuild -version`（xcodebuild 在
# 无 Xcode 环境/首次运行触发状态时可能直接 abort，正是本脚本要防的场景之一）。
XCODE_STR=""
XC_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app}"
if [ -f "$XC_PATH/Contents/version.plist" ]; then
  XCODE_STR=$(plutil -extract CFBundleShortVersionString raw \
                "$XC_PATH/Contents/version.plist" 2>/dev/null) || XCODE_STR=""
fi
if [ -z "$XCODE_STR" ] && command -v xcodebuild >/dev/null 2>&1; then
  XCODE_STR=$(xcodebuild -version 2>/dev/null | awk '/^Xcode /{print $2; exit}') || XCODE_STR=""
fi

# 校验版本号形如「主.次」且均为数字，否则视为拿不到（不猜）。
case "$XCODE_STR" in
  [0-9]*.[0-9]*) : ;;
  *) XCODE_STR="" ;;
esac

if [ -z "$XCODE_STR" ]; then
  echo "[verify_xcodeproj_format] WARN: cannot determine Xcode version; skip check (objectVersion=$OBJ_VER)"
  exit 0
fi

XCODE_MAJOR="${XCODE_STR%%.*}"
XCODE_REST="${XCODE_STR#*.}"
XCODE_MINOR="${XCODE_REST%%.*}"

echo "[verify_xcodeproj_format] Xcode=$XCODE_STR (major=$XCODE_MAJOR minor=$XCODE_MINOR) objectVersion=$OBJ_VER (需要 Xcode ${REQUIRED_XCODE:-unknown}+)"

if [ -z "$REQUIRED_XCODE" ]; then
  echo "[verify_xcodeproj_format] WARN: unknown objectVersion $OBJ_VER; skip compatibility check"
  exit 0
fi

REQ_MAJOR="${REQUIRED_XCODE%%.*}"
REQ_REST="${REQUIRED_XCODE#*.}"
REQ_MINOR="${REQ_REST%%.*}"

IS_OLD=0
if [ "$XCODE_MAJOR" -lt "$REQ_MAJOR" ]; then
  IS_OLD=1
elif [ "$XCODE_MAJOR" -eq "$REQ_MAJOR" ] && [ "$XCODE_MINOR" -lt "$REQ_MINOR" ]; then
  IS_OLD=1
fi

if [ "$IS_OLD" -eq 1 ]; then
  echo "[verify_xcodeproj_format] ERROR: Xcode $XCODE_STR cannot open objectVersion $OBJ_VER (needs Xcode $REQUIRED_XCODE+)."
  echo "[verify_xcodeproj_format] FIX: lower projectFormat in project.yml (e.g. xcode15_3 / xcode15_0), then re-run xcodegen generate."
  exit 1
fi

echo "[verify_xcodeproj_format] OK: objectVersion $OBJ_VER is compatible with Xcode $XCODE_STR"
exit 0

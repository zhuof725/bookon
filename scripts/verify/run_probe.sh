#!/bin/bash
# 编译并运行 scripts/verify 下的单个 @main 探针（Linux 本地）。
#
# 前置：先跑 `bash scripts/verify/build_local_lib.sh` 生成
#       .build/local-tc/libLegadoBookSource.so（含全部 LegadoBookSource 源码）。
# 本脚本只做「编译探针 + 链接 + 运行」，不重建库，避免每次等数分钟。
#
# 用法: bash scripts/verify/run_probe.sh scripts/verify/<probe>.swift
set -uo pipefail
SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/.build/local-tc"

if [ ! -f "$OUT/libLegadoBookSource.so" ]; then
  echo "缺少 $OUT/libLegadoBookSource.so；请先运行 bash scripts/verify/build_local_lib.sh" >&2
  exit 1
fi

SRC="$1"
[ -f "$SRC" ] || { echo "找不到探针源文件: $SRC" >&2; exit 1; }
NAME="$(basename "${SRC%.swift}")"
BIN="$OUT/$NAME"

# 探针有两种写法：@main 入口（需 -parse-as-library）与顶层代码（默认模式）。
# 自动探测，避免逐个脚本手改编译参数。
if grep -q '@main' "$SRC"; then PARSE_FLAG="-parse-as-library"; else PARSE_FLAG=""; fi

echo "== 编译探针 $NAME =="
"$SWIFT_BIN/swiftc" -swift-version 5 $PARSE_FLAG \
  -I "$OUT" -L "$OUT" \
  -lLegadoBookSource -lSwiftSoup \
  -Xlinker -rpath -Xlinker "$OUT" \
  -o "$BIN" "$SRC" 2>&1 | grep -E "error:" | head -20 || true
if [ ! -x "$BIN" ]; then echo "❌ 探针编译失败"; exit 1; fi

echo "== 运行 $NAME =="
LD_LIBRARY_PATH="$OUT" "$BIN"

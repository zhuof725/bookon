#!/bin/bash
# Linux 本地类型检查脚手架：BookonDebugKit（B 段）+ 其测试。
# 先构建带 -enable-testing 的 LegadoBookSource 模块（含 shim），再构建 BookonDebugKit 模块，
# 最后对 Tests/BookonDebugKitTests 做 @testable import 类型检查。
# 真实验收仍以 macOS CI 的 swift test / xcodebuild test 为准。
set -uo pipefail
SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/.build/local-tc"

# 1) LegadoBookSource 模块（复用 local_typecheck_tests.sh 的构建逻辑，仅构建模块）
if [ ! -f "$OUT/LegadoBookSource.swiftmodule" ]; then
  bash "$REPO/scripts/local_typecheck_tests.sh" /tmp/dummy_test.swift >/dev/null 2>&1
fi

# 2) BookonDebugKit 模块
echo "== 构建 BookonDebugKit 模块（-enable-testing）=="
"$SWIFT_BIN/swiftc" -emit-module -module-name BookonDebugKit -swift-version 5 -enable-testing \
  -I "$OUT" -L "$OUT" -lSwiftSoup \
  -emit-module-path "$OUT/BookonDebugKit.swiftmodule" \
  "$REPO"/Sources/BookonDebugKit/*.swift 2>&1 | grep -E "error:" | head -30
if [ ! -f "$OUT/BookonDebugKit.swiftmodule" ]; then echo "❌ BookonDebugKit 模块构建失败"; exit 1; fi

# 3) 类型检查测试
TEST_FILES=("$REPO"/Tests/BookonDebugKitTests/*.swift)
echo "== 类型检查 ${#TEST_FILES[@]} 个测试文件 =="
"$SWIFT_BIN/swiftc" -typecheck -swift-version 5 \
  -I "$OUT" -L "$OUT" -lSwiftSoup \
  "${TEST_FILES[@]}" 2>&1 | grep -E "error:|warning:" | grep -v "never mutated\|never used\|redundant" | head -60
echo "done"

#!/bin/bash
# Linux 本地验证：BookonDebugKit 第 7 步 C 段返工的纯逻辑（DebugTab / DebugTextLimit /
# AppBuildInfo / DebugTabBarState）。用「编译真实产品代码 + 独立断言驱动」实测，非阅读推测。
#
# 真实验收仍以 macOS CI 的 swift test / xcodebuild test 为准。
set -uo pipefail
SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/.build/local-tc"
TCDIR=/root/work/tc

# 1) 确保 LegadoBookSource 模块 + 动态库就绪（复用 tests 脚手架的构建逻辑）。
if [ ! -f "$OUT/libLegadoBookSource.so" ]; then
  bash "$REPO/scripts/local_typecheck_tests.sh" /tmp/dummy_test.swift >/dev/null 2>&1
  TC_SRC="$OUT/tc_src"
  FILES=($(cd "$TC_SRC" && find Sources/LegadoBookSource -name '*.swift' | sed "s|^|$TC_SRC/|"))
  ARGS=(); for f in "${FILES[@]}"; do
    skip=0
    for ex in "Sources/LegadoBookSource/Network/URLSessionHTTPClient.swift" "Sources/LegadoBookSource/Network/RealAjaxProvider.swift"; do
      [ "$TC_SRC/$ex" = "$f" ] && skip=1
    done
    [ "$skip" -eq 0 ] && ARGS+=("$f")
  done
  "$SWIFT_BIN/swiftc" -emit-library -module-name LegadoBookSource -swift-version 5 -enable-testing \
    -I "$OUT" -L "$OUT" -lSwiftSoup -o "$OUT/libLegadoBookSource.so" \
    "$TCDIR/CryptoKit.swift" "$TCDIR/URLSessionHTTPClientStub.swift" "$TCDIR/jquery_jsc_module.swift" "$TCDIR/jsc_internal_stubs.swift" "${ARGS[@]}" >/dev/null 2>&1
fi

# 2) 构建 BookonDebugKit 动态库。
"$SWIFT_BIN/swiftc" -emit-library -module-name BookonDebugKit -swift-version 5 -enable-testing \
  -I "$OUT" -L "$OUT" -lSwiftSoup -o "$OUT/libBookonDebugKit.so" "$REPO"/Sources/BookonDebugKit/*.swift 2>&1 | grep -E "error:" | head -10

# 3) 编译并运行断言驱动。
DRV="$REPO/scripts/verify/debugkit_logic_check.swift"
"$SWIFT_BIN/swiftc" -swift-version 5 -I "$OUT" -L "$OUT" \
  -lBookonDebugKit -lLegadoBookSource -lSwiftSoup \
  -Xlinker -rpath -Xlinker "$OUT" -o /tmp/verify_dk_logic "$DRV" 2>&1 | grep -E "error:" | head -10
LD_LIBRARY_PATH="$OUT" /tmp/verify_dk_logic
STATUS=$?
if [ $STATUS -eq 0 ]; then echo "✅ DebugKit 逻辑校验通过"; else echo "❌ DebugKit 逻辑校验失败"; fi
exit $STATUS

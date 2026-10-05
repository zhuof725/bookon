#!/bin/bash
# Linux 本地类型检查脚手架：先构建带 -enable-testing 的 LegadoBookSource 模块（含 shim），
# 再对 Tests 下的 .swift 文件做 @testable import 类型检查，用于开发期快速发现测试代码错误。
# 真实验收仍以 macOS CI 的 swift test / xcodebuild test 为准。
set -uo pipefail
SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TCDIR="/root/work/tc"
SOUP="$REPO/.build/checkouts/SwiftSoup/Sources"
OUT="$REPO/.build/local-tc"
mkdir -p "$OUT"

if [ ! -f "$OUT/SwiftSoup.swiftmodule" ]; then
  find "$SOUP" -name '*.swift' > "$OUT/soup_files.txt"
  "$SWIFT_BIN/swiftc" -emit-module -emit-library -module-name SwiftSoup -swift-version 5 -O -suppress-warnings \
    -emit-module-path "$OUT/SwiftSoup.swiftmodule" -o "$OUT/libSwiftSoup.so" @"$OUT/soup_files.txt" 2>&1 | head -20 || true
fi

TC_SRC="$OUT/tc_src"
rm -rf "$TC_SRC"; mkdir -p "$TC_SRC"
(cd "$REPO" && find Sources/LegadoBookSource -name '*.swift' -exec cp --parents {} "$TC_SRC" \;)
PATCH_TARGET="$TC_SRC/Sources/LegadoBookSource/RuleEngine/AnalyzeRule+Rules.swift"
[ -f "$PATCH_TARGET" ] && sed -i 's/?? NSRegularExpression()/?? NSRegularExpression.__tcNeverMatch()/g' "$PATCH_TARGET" || true
FILES=($(cd "$TC_SRC" && find Sources/LegadoBookSource -name '*.swift' | sed "s|^|$TC_SRC/|"))
ARGS=("$TCDIR/CryptoKit.swift" "$TCDIR/URLSessionHTTPClientStub.swift" "$TCDIR/js_stub.swift")
for f in "${FILES[@]}"; do
  skip=0
  for ex in "Sources/LegadoBookSource/Network/URLSessionHTTPClient.swift" "Sources/LegadoBookSource/Network/RealAjaxProvider.swift"; do
    [ "$TC_SRC/$ex" = "$f" ] && skip=1
  done
  [ "$skip" -eq 0 ] && ARGS+=("$f")
done

echo "== 构建 LegadoBookSource 模块（-enable-testing）=="
"$SWIFT_BIN/swiftc" -emit-module -module-name LegadoBookSource -swift-version 5 -enable-testing \
  -I "$OUT" -L "$OUT" -lSwiftSoup -emit-module-path "$OUT/LegadoBookSource.swiftmodule" \
  "${ARGS[@]}" 2>&1 | grep -E "error:" | head -30 || true
if [ ! -f "$OUT/LegadoBookSource.swiftmodule" ]; then echo "❌ 模块构建失败"; exit 1; fi

# 收集要检查的测试文件（参数指定，或默认全量 Tests）
if [ $# -gt 0 ]; then
  TEST_FILES=("$@")
else
  TEST_FILES=($(cd "$REPO" && find Tests -name '*.swift' | sed "s|^|$REPO/|"))
fi

echo "== 类型检查 ${#TEST_FILES[@]} 个测试文件 =="
"$SWIFT_BIN/swiftc" -typecheck -swift-version 5 \
  -I "$OUT" -L "$OUT" -lSwiftSoup \
  "${TEST_FILES[@]}" 2>&1 | grep -E "error:|warning:" | grep -v "redundant\|never mutated\|never used\|no calls to throwing\|downcast from" | head -60
STATUS=${PIPESTATUS[0]}
echo "done"

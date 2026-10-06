#!/bin/bash
# 重建 Linux 本地探针所需的 LegadoBookSource 模块 + 动态库（.build/local-tc）。
#
# 为什么需要它：local_typecheck.sh 只做 -typecheck（不产出 .swiftmodule/.so），
# local_typecheck_tests.sh 只产出 .swiftmodule；而 scripts/verify/*.swift 探针
# 需要**链接** libLegadoBookSource.so 才能运行。本脚本把这条链路补齐。
#
# 真实验收仍以 macOS / iOS CI 为准。
set -uo pipefail
SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/.build/local-tc"
TCDIR=/root/work/tc

# 1) 复用 typecheck 脚手架：拷贝 Sources 到 tc_src、编译 SwiftSoup 模块、产出 .swiftmodule。
bash "$REPO/scripts/local_typecheck_tests.sh" /tmp/dummy_probe_test.swift >/dev/null 2>&1 || true

TC_SRC="$OUT/tc_src"
if [ ! -d "$TC_SRC" ]; then echo "❌ 未找到 $TC_SRC（先跑 scripts/local_typecheck_tests.sh）" >&2; exit 1; fi

# 2) 与 typecheck 相同的排除清单（macOS 独有 Foundation 网络 API）。
FILES=($(cd "$TC_SRC" && find Sources/LegadoBookSource -name '*.swift' | sed "s|^|$TC_SRC/|"))
ARGS=()
for f in "${FILES[@]}"; do
  skip=0
  for ex in "Sources/LegadoBookSource/Network/URLSessionHTTPClient.swift" \
            "Sources/LegadoBookSource/Network/RealAjaxProvider.swift"; do
    [ "$TC_SRC/$ex" = "$f" ] && skip=1
  done
  [ "$skip" -eq 0 ] && ARGS+=("$f")
done

echo "== 重建 libLegadoBookSource.so（${#ARGS[@]} 个源文件）=="
"$SWIFT_BIN/swiftc" -emit-library -module-name LegadoBookSource -swift-version 5 -enable-testing \
  -I "$OUT" -L "$OUT" -lSwiftSoup -o "$OUT/libLegadoBookSource.so" \
  "$TCDIR/CryptoKit.swift" "$TCDIR/URLSessionHTTPClientStub.swift" \
  "$TCDIR/js_stub.swift" "${ARGS[@]}" 2>&1 | grep -E "error:" | head -20
[ -f "$OUT/libLegadoBookSource.so" ] && echo "✅ libLegadoBookSource.so 就绪" || { echo "❌ 动态库构建失败" >&2; exit 1; }

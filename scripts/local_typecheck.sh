#!/bin/bash
# Linux 本地类型检查脚手架（开发期快速发现语法/类型错误；真实验收仍以 macOS CI 为准）。
#
# 为什么要排除一批文件：
#   本包原本就是为 macOS 编写的，依赖若干 Linux 上不存在的系统框架/API：
#     - CryptoKit（JsExtensionsCore）
#     - JavaScriptCore（JSEngine / JSJavaBridge / AnalyzeRule+JS 等）
#     - URLSession 的 URLAuthenticationChallenge/protectionSpace、URLCredential
#   这些属**预先存在**的平台差异，与第 7 步改动无关。
#
# 因此本脚本把源码分成两类：
#   A. 核心可检查文件：与第 7 步直接相关的（模型 / 规则引擎 / 网络 / 流程层 / 新增文件）
#      —— 但不含依赖 JS/JSC/URLSession 的文件，用 CryptoKit + URLSessionHTTPClient 垫片补齐。
#   B. 依赖 JS/JSC 的文件：其所需类型由 $TCDIR/js_stub.swift 提供最小签名占位，
#      仅用于让「A + B」联合编译通过类型检查。
#
# 用法：bash scripts/local_typecheck.sh [额外要检查的 .swift 文件...]
set -uo pipefail

SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TCDIR="/root/work/tc"
SOUP="$REPO/.build/checkouts/SwiftSoup/Sources"
OUT="$REPO/.build/local-tc"

if [ ! -x "$SWIFT_BIN/swiftc" ]; then
  echo "未找到 swiftc（$SWIFT_BIN/swiftc）；请先安装 Swift 工具链或设置 SWIFT_BIN" >&2
  exit 127
fi

mkdir -p "$OUT"

# 1) 把 SwiftSoup 编译成模块（只在缺失时）。
if [ ! -f "$OUT/SwiftSoup.swiftmodule" ]; then
  echo "== 编译 SwiftSoup 模块 =="
  find "$SOUP" -name '*.swift' > "$OUT/soup_files.txt"
  "$SWIFT_BIN/swiftc" -emit-module -emit-library -module-name SwiftSoup \
    -swift-version 5 -O -suppress-warnings \
    -emit-module-path "$OUT/SwiftSoup.swiftmodule" \
    -o "$OUT/libSwiftSoup.so" \
    @"$OUT/soup_files.txt" 2>&1 | head -20 || true
fi
if [ ! -f "$OUT/SwiftSoup.swiftmodule" ]; then
  echo "❌ SwiftSoup 模块编译失败" >&2
  exit 1
fi

# 2) 收集要检查的源文件。
#    排除清单：这些文件依赖 macOS 独有的 Foundation 网络 API。
EXCLUDE_FILES=(
  "Sources/LegadoBookSource/Network/URLSessionHTTPClient.swift"
  "Sources/LegadoBookSource/Network/RealAjaxProvider.swift"
)

#    有一个**预先存在**的 macOS-only 写法需要在小副本里做行为等价替换：
#    `?? NSRegularExpression()`（macOS 的 init()，Linux corelibs 没有）。
#    我们在临时副本里把它替换为 NSRegularExpression.__tcNeverMatch（静态方法，
#    定义在 js_stub.swift 里，返回永不匹配的正则），不改任何已发布源码。
TC_SRC="$OUT/tc_src"
rm -rf "$TC_SRC"
mkdir -p "$TC_SRC"
# 复制全部 Sources（保持相对路径）
(cd "$REPO" && find Sources/LegadoBookSource -name '*.swift' -exec cp --parents {} "$TC_SRC" \;)

# 行为等价的临时替换（仅在副本中；该 fallback 为死代码分支）
PATCH_TARGET="$TC_SRC/Sources/LegadoBookSource/RuleEngine/AnalyzeRule+Rules.swift"
if [ -f "$PATCH_TARGET" ]; then
  sed -i 's/?? NSRegularExpression()/?? NSRegularExpression.__tcNeverMatch()/g' "$PATCH_TARGET" || true
fi

FILES=($(cd "$TC_SRC" && find Sources/LegadoBookSource -name '*.swift' | sed "s|^|$TC_SRC/|"))
ARGS=("$TCDIR/CryptoKit.swift" "$TCDIR/URLSessionHTTPClientStub.swift" "$TCDIR/js_stub.swift")
for f in "${FILES[@]}"; do
  skip=0
  for ex in "${EXCLUDE_FILES[@]}"; do
    [ "$TC_SRC/$ex" = "$f" ] && skip=1
  done
  [ "$skip" -eq 0 ] && ARGS+=("$f")
done
for f in "$@"; do [ -n "$f" ] && ARGS+=("$f"); done

echo "== 类型检查 ${#ARGS[@]} 个文件 =="
"$SWIFT_BIN/swiftc" -typecheck -swift-version 5 \
  -I "$OUT" -L "$OUT" -lSwiftSoup \
  "${ARGS[@]}" 2>&1
STATUS=$?
if [ $STATUS -eq 0 ]; then echo "✅ 类型检查通过"; else echo "❌ 类型检查失败"; fi
exit $STATUS

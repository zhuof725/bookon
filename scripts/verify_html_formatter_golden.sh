#!/bin/bash
# 本地离线验证：用 CI 生成的 golden 逐条跑真实 HtmlFormatter，比对期望值。
#
# 为什么需要它：golden 是**唯一**能发现 `\s` 语义差异的手段。
# Java 的 `\s` = [ \t\n\x0B\f\r]；ICU（NSRegularExpression）的 `\s` 额外包含
# 全角空格 U+3000。Kotlin 的 HtmlFormatter 大量用 `\s` 做缩进替换，于是同一个
# 正则串在两边行为不同（细节见 HtmlFormatter.swift 里 javaASCIISpace 的文档）。
# Linux 上无法运行 iOS/macOS 测试，用这个脚本可提前把差异暴露出来。
#
# 前置：
#   1. swiftc 可用（SWIFT_BIN，默认 /tmp/swift-toolchain/usr/bin）
#   2. scripts/golden/out/html_formatter_cases.json 已生成（CI 的 golden job 产物，
#      或本地 `cd scripts/golden && mvn -q package && java -jar target/golden-generator.jar cases out`）
#
# 用法：bash scripts/verify_html_formatter_golden.sh
set -uo pipefail

SWIFT_BIN="${SWIFT_BIN:-/tmp/swift-toolchain/usr/bin}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CASES="$REPO/scripts/golden/cases/html_formatter_cases.json"
GOLD="$REPO/scripts/golden/out/html_formatter_cases.json"
WORK="${TMPDIR:-/tmp}/hf-golden-verify"

if [ ! -f "$GOLD" ]; then
  echo "❌ 缺少 golden 产物：$GOLD"
  echo "   请在 scripts/golden 下执行：mvn -q package && java -jar target/golden-generator.jar cases out"
  exit 1
fi

rm -rf "$WORK"; mkdir -p "$WORK"

# 1) 把「用例输入 + golden 期望值」合并成一份待比对数据
python3 - "$CASES" "$GOLD" "$WORK/verify.json" <<'PY'
import json, sys
cases = json.load(open(sys.argv[1], encoding="utf-8"))["htmlFormatterCases"]
gold = json.load(open(sys.argv[2], encoding="utf-8"))["htmlFormatterResults"]
by_name = {g["name"]: g["result"] for g in gold}
out = [{"name": c["name"], "mode": c.get("mode", "format"),
        "html": c["html"], "expected": by_name.get(c["name"])} for c in cases]
missing = [x["name"] for x in out if x["expected"] is None]
if missing:
    print("❌ golden 缺少这些用例的结果：" + ", ".join(missing))
    sys.exit(1)
json.dump(out, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False)
print(f"待比对用例：{len(out)}")
PY
[ $? -ne 0 ] && exit 1

# 2) 编译「真实 HtmlFormatter + 最小依赖 stub + 比对驱动」
cp "$REPO/Sources/LegadoBookSource/RuleEngine/HtmlFormatter.swift" "$WORK/HtmlFormatter.swift"
cat > "$WORK/stub.swift" <<'EOF'
import Foundation
// 最小依赖替身：HtmlFormatter 只用到这里两个符号。
// getAbsoluteURL 必须与真实实现语义一致，否则 formatKeepImg 的相对地址用例会误报。
final class NSRegularExpressionCache: @unchecked Sendable {
    private let re: NSRegularExpression?
    init(pattern: String, options: NSRegularExpression.Options = []) {
        re = try? NSRegularExpression(pattern: pattern, options: options)
    }
    func stringByReplacingMatches(in s: String, range: NSRange, withTemplate t: String) -> String {
        guard let re = re else { return s }
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: t)
    }
    func matches(in s: String) -> [NSTextCheckingResult] {
        guard let re = re else { return [] }
        return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    func firstMatch(in s: String) -> NSTextCheckingResult? {
        guard let re = re else { return nil }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
}
enum AnalyzeUrl {
    static let paramPattern = NSRegularExpressionCache(pattern: "\\s*,\\s*(?=\\{)")
}
enum NetworkUtils {
    static func getAbsoluteURL(_ base: String?, _ relative: String) -> String {
        let r = relative.trimmingCharacters(in: .whitespaces)
        if r.hasPrefix("data:") { return r }
        guard let base = base, let bu = URL(string: base) else { return r }
        if let u = URL(string: r, relativeTo: bu) { return u.absoluteString }
        return r
    }
}
EOF
cat > "$WORK/main.swift" <<'EOF'
import Foundation
struct Case: Codable { let name: String; let mode: String; let html: String; let expected: String }
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/hf-golden-verify/verify.json"
let cases = try! JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
var pass = 0
var fails: [String] = []
for c in cases {
    let got = c.mode == "formatKeepImg"
        ? HtmlFormatter.formatKeepImg(c.html, redirectUrl: "http://base/dir/page")
        : HtmlFormatter.format(c.html)
    if got == c.expected { pass += 1 } else if fails.count < 8 {
        fails.append("  \(c.name)\n    期望码点: \(c.expected.unicodeScalars.map { $0.value })\n    实际码点: \(got.unicodeScalars.map { $0.value })")
    }
}
print("PASS=\(pass) FAIL=\(cases.count - pass) / \(cases.count)")
for f in fails { print(f) }
exit(pass == cases.count ? 0 : 1)
EOF

"$SWIFT_BIN/swiftc" -O -o "$WORK/verify" \
  "$WORK/HtmlFormatter.swift" "$WORK/stub.swift" "$WORK/main.swift" 2>&1 | grep -E "error" | head -10
if [ ! -x "$WORK/verify" ]; then echo "❌ 编译失败"; exit 1; fi

"$WORK/verify" "$WORK/verify.json"
STATUS=$?
if [ $STATUS -eq 0 ]; then echo "✅ HtmlFormatter golden 全部通过"; else echo "❌ HtmlFormatter golden 存在不匹配"; fi
exit $STATUS

#!/usr/bin/env python3
"""
函数覆盖校验（自动提取，不手打清单）。

从 legado 的三个 Kotlin 源码文件里用正则提取全部 `fun`（含 private / internal），
再到对应的 Swift 源码里检查同名函数存在。

Kotlin 源码路径：默认相对本仓库 reference/kotlin/analyzeRule，
可用第一个命令行参数覆盖为外部 legado 的 analyzeRule 目录。

输出「Kotlin 有但 Swift 没实现的函数」清单，必须为空。
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

DEFAULT_KOTLIN_DIR = os.path.join(REPO, "reference", "kotlin", "analyzeRule")
kotlin_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_KOTLIN_DIR

# Kotlin 文件 -> 对应 Swift 文件
MAPPING = {
    "RuleAnalyzer.kt":     "Sources/LegadoBookSource/RuleEngine/RuleAnalyzer.swift",
    "AnalyzeByRegex.kt":   "Sources/LegadoBookSource/RuleEngine/AnalyzeByRegex.swift",
    "AnalyzeByJSonPath.kt":"Sources/LegadoBookSource/RuleEngine/AnalyzeByJSonPath.swift",
}

# 提取 Kotlin 函数名：匹配 `fun name(` / `fun <T> name(` / `tailrec fun name(` 等。
# 同时忽略 companion object 里的 parse（也是 fun，会被提取，需在 Swift 里有同名）。
KFUN_RE = re.compile(
    r'\bfun\b'                       # fun 关键字
    r'(?:\s*<[^>]*>)?'               # 可选泛型 <T>
    r'\s+'
    r'([A-Za-z_]\w*)'                # 函数名
    r'\s*\('                         # 左括号
)

# Kotlin 里以 `val name = ::xxx` 形式暴露的“函数值”，也纳入（如 chompBalanced）。
KVALFUN_RE = re.compile(r'\bval\s+([A-Za-z_]\w*)\s*=\s*if\s*\(.*::')

def kotlin_functions(path):
    text = open(path).read()
    names = set(KFUN_RE.findall(text))
    names |= set(KVALFUN_RE.findall(text))
    return names

def swift_has_func(swift_text, name):
    # Swift 里函数以 `func name(` 出现（可能前面有 public/private/static/@discardableResult 等）。
    # chompBalanced 在 Swift 里也是 func。
    pat = re.compile(r'\bfunc\s+' + re.escape(name) + r'\s*[\(<]')
    if pat.search(swift_text):
        return True
    # 某些 Kotlin fun（如 companion parse）在 Swift 里可能是 static func，同样被上面的正则覆盖。
    return False

def main():
    missing = {}
    details = {}
    for kfile, swift_rel in MAPPING.items():
        kpath = os.path.join(kotlin_dir, kfile)
        knames = kotlin_functions(kpath)
        swift_text = open(os.path.join(REPO, swift_rel)).read()
        miss = sorted(n for n in knames if not swift_has_func(swift_text, n))
        details[kfile] = sorted(knames)
        if miss:
            missing[kfile] = miss

    print("=== 函数覆盖校验（自动从 Kotlin 源码提取）===")
    print(f"Kotlin 源码目录: {os.path.relpath(kotlin_dir, REPO)}")
    total = 0
    for kfile, names in details.items():
        print(f"  {kfile}: {len(names)} 个 fun -> {names}")
        total += len(names)
    print(f"Kotlin 函数总数: {total}")

    if not missing:
        print("结果: 「Kotlin 有但 Swift 没实现的函数」清单 —— 空。全部覆盖。")
        sys.exit(0)
    else:
        print("结果: 存在未覆盖函数：")
        for k, m in missing.items():
            print(f"  {k}: {m}")
        sys.exit(1)

if __name__ == "__main__":
    main()

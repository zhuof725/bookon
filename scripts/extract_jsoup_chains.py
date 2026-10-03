#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从真实书源配置里提取 org.jsoup.Jsoup 规则链（用于第 5 步 jsoup 替身 golden 用例的来源标注）。

用法:
    python3 scripts/extract_jsoup_chains.py            # 打印所有 jsoup 链 + 方法使用统计
    python3 scripts/extract_jsoup_chains.py --json     # 以 JSON 输出（供其它脚本消费）
    python3 scripts/extract_jsoup_chains.py --check    # 校验 golden 用例的 source 标签都能对上

扫描对象（扫描集合 = 仓库里能找到的全部真实书源配置）:
    Tests/LegadoAnalyzeRuleTests/Resources/配置文件_7个.json   （7 个真实书源）
    Tests/LegadoAnalyzeRuleTests/Resources/taiwan_real_source.json（台湾小说网）

说明：第 4/5 步期间用户还提供过 `配置文件_14个.json`（14 书源合并版）。该文件未随仓库保存
（工作区曾被系统清空），因此本脚本以仓库内实际存在的真实配置为准。两个使用
`org.jsoup.Jsoup` 的书源（爱丽丝书屋、台湾小说网）都在扫描集合内，jsoup 链提取完整。
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [
    ("Tests/LegadoAnalyzeRuleTests/Resources/配置文件_7个.json", "配置文件_7个.json"),
    ("Tests/LegadoAnalyzeRuleTests/Resources/taiwan_real_source.json", "taiwan_real_source.json"),
]

# 关注的方法（真实书源用到的 + 替身对外承诺支持的）
METHODS = ["select", "text", "html", "outerHtml", "attr", "size", "get", "eq", "first", "remove"]


def walk(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk(v, path + "." + str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk(v, path + "[%d]" % i)
    else:
        yield path, obj


def balanced(src, start):
    """src[start] 必须是 '('；返回匹配的 ')' 的下标，找不到返回 -1。"""
    depth = 0
    i = start
    quote = None
    while i < len(src):
        c = src[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


NEXT_CALL = re.compile(r"\s*\.\s*([A-Za-z_$][\w$]*)\s*\(")


def chain_from(src, i):
    """i 指向变量名后的第一个字符；顺着 `.method(args)` 链走到底，返回 [(method, args)]。"""
    out = []
    while True:
        m = NEXT_CALL.match(src, i)
        if not m:
            return out
        name = m.group(1)
        open_paren = m.end() - 1
        close = balanced(src, open_paren)
        if close < 0:
            return out
        if name in METHODS:
            out.append((name, re.sub(r"\s+", " ", src[open_paren + 1:close]).strip()))
        i = close + 1


def method_calls(src, var):
    """提取 `var.method(args)...` 链式调用，返回 [(method, args)]（按出现顺序，去重）。"""
    out = []
    for m in re.finditer(r"\b%s\b" % re.escape(var), src):
        for item in chain_from(src, m.end()):
            if item not in out:
                out.append(item)
    return out


def extract():
    """返回 [(bookSourceName, rulePath, [ (method, args), ... ])]。"""
    out = []
    for rel, _label in SOURCES:
        full = os.path.join(REPO, rel)
        if not os.path.exists(full):
            continue
        data = json.load(open(full, encoding="utf-8"))
        items = data if isinstance(data, list) else [data]
        for src in items:
            name = src.get("bookSourceName", "?")
            for p, v in walk(src):
                if not isinstance(v, str) or "Jsoup.parse" not in v:
                    continue
                # 找出所有 Jsoup.parse 的结果接收变量： var d=...Jsoup.parse(...)
                vars_ = []
                for m in re.finditer(r"\bvar\s+([A-Za-z_$][\w$]*)\s*=", v):
                    seg = v[m.end():m.end() + 400]
                    if "Jsoup.parse" in seg.split(";")[0]:
                        vars_.append(m.group(1))
                # 二级变量（从一级变量链上赋值）： var n=b.select(...) / var es=d.select(...)
                changed = True
                while changed:
                    changed = False
                    for m in re.finditer(r"\bvar\s+([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*)", v):
                        lhs, rhs = m.group(1), m.group(2)
                        if rhs in vars_ and lhs not in vars_:
                            vars_.append(lhs)
                            changed = True
                calls = []
                for var in vars_:
                    for c in method_calls(v, var):
                        if c not in calls:
                            calls.append(c)
                # 即使没有可识别的链式调用（如 ruleContent.title 直接把 parse().select().text()
                # 内联在 java.t2s(...) 里，没有赋值给变量），也要记录该规则路径，
                # 让 --check 能按「书源 + 规则路径」核对用例来源。
                out.append((name, p, vars_, calls))
    return out


def main():
    chains = extract()
    if "--check" in sys.argv:
        cases_path = os.path.join(REPO, "scripts/golden/cases/jsoup_cases.json")
        cases = json.load(open(cases_path, encoding="utf-8"))["jsoupCases"]
        known = set()
        for name, p, vars_, calls in chains:
            for meth, args in calls:
                known.add("%s|%s|%s" % (name, meth, args))
        bad = []
        for c in cases:
            src = c.get("source", "")
            if (not src or src.startswith("合成") or src.startswith("替身")
                    or src.startswith("已知差异")):
                continue
            # source 形如 "📂台湾小说网 ruleToc.nextTocUrl: d.select('h1').text()"
            book = src.split(" ", 1)[0]
            rest = src.split(" ", 1)[1] if " " in src else ""
            rule = rest.split(":", 1)[0].split(" ")[0]
            hit = False
            for name, p, vars_, calls in chains:
                if name == book and rule in p:
                    hit = True
                    break
            if not hit:
                bad.append((c["name"], src))
        if bad:
            print("以下用例的 source 标签在真实书源里找不到对应规则：")
            for n, s in bad:
                print("  - %s: %s" % (n, s))
            return 1
        print("OK: %d 条用例的 source 标签全部命中真实书源规则" % len(cases))
        return 0

    if "--json" in sys.argv:
        print(json.dumps([{"bookSourceName": n, "rulePath": p, "vars": vs,
                           "calls": [{"method": m, "args": a} for m, a in cs]}
                          for n, p, vs, cs in chains], ensure_ascii=False, indent=2))
        return 0

    stats = {}
    for name, p, vars_, calls in chains:
        print("[%s]%s   变量: %s" % (name, p, ", ".join(vars_)))
        for meth, args in calls:
            print("    .%s(%s)" % (meth, args))
            stats[meth] = stats.get(meth, 0) + 1
    print()
    print("共 %d 条 jsoup 规则片段；方法使用统计：" % len(chains))
    for m, n in sorted(stats.items(), key=lambda kv: (-kv[1], kv[0])):
        print("    %-12s %d" % (m, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())

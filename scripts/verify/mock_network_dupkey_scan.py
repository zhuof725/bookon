# -*- coding: utf-8 -*-
#
# mock_network_dupkey_scan.py
#
# 静态扫描：找出测试里 `MockWebBookNetwork([...])` **字典字面量**中重复的变量 key。
#
# 背景（CI run 37449176865 的真实崩溃）：
#   Swift/Dictionary.swift:830: Fatal error: Dictionary literal contains duplicate keys
# 得奇小说网的详情页与目录页是同一个 URL（bookURL == tocURL），两个变量被当作
# 同一个字典 key 写进字面量，运行时直接终止整个测试进程
# （Linux 上同样可复现，实测 exit 132 / Signal 4）。
#
# 本脚本在工作区内扫描，发现潜在重复 key 即非 0 退出。
# 说明：只做「同一字面量内变量名重复」的保守检查；更精确的语义需要运行时，
# 故仅作为防回归的第一道闸（现网代码已统一改为 set(_:_:) 逐个写入，不再用字面量）。
#

import re
import sys
import pathlib

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

LIT = re.compile(r"MockWebBookNetwork\(\[(.*?)\]\)", re.S)
ENTRY = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+?),?\s*$", re.M)

problems = []
scanned = 0
for path in sorted(ROOT.rglob("*.swift")):
    if ".build" in path.parts:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        continue
    for m in LIT.finditer(text):
        scanned += 1
        body = m.group(1)
        keys = [e.group(1) for e in ENTRY.finditer(body)]
        dup = sorted({k for k in keys if keys.count(k) > 1})
        if dup:
            line = text[: m.start()].count("\n") + 1
            problems.append((path, line, dup))

print("扫描 MockWebBookNetwork 字典字面量：%d 处" % scanned)
if problems:
    print("\n[X] 发现重复 key：")
    for path, line, dup in problems:
        print("  %s:%d  重复 key = %s" % (path, line, dup))
    sys.exit(1)

print("[OK] 未发现字典字面量重复 key")

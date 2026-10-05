#!/usr/bin/env python3
"""静态检查：源码中是否误用了「只在某一个平台存在」的 Foundation API。

背景
====
本地开发用 Linux + swiftc 做语法/类型检查，但 Linux 的 corelibs-foundation
与 Apple 的 Foundation **不是同一套实现**。若某段代码被 `#if os(macOS)`
包起来，Linux 侧走 `#else` 分支，那么 Darwin 专属 API 的使用**在本地完全
不会被编译到**——本地全绿，CI 的 macOS `swift build` 直接报错。

真实缺陷（CI run 37281507318，test-macos job 的 Build 步骤）：
    Sources/LegadoBookSource/WebBook/WebBookNetwork.swift:156:29:
        error: type 'String.Encoding' has no member 'gbk'
    ...gb18030 / big5 同理
`String.Encoding` 是 Foundation 的 Swift 封装，**只有** utf8 / utf16 /
isoLatin1 / ascii 等少数成员；`gbk` / `gb18030` / `big5` / `shiftJIS` /
`eucJP` / `eucKR` / `windowsCP1251` 这些只存在于 CoreFoundation 的
`CFStringEncoding` 层面，必须经
`CFStringConvertEncodingToNSStringEncoding(_:)` 转换后再包成
`String.Encoding(rawValue:)`。

本脚本把这类「Darwin 才编译得到、且成员名不存在」的用法挡在提交之前。

退出码：0 = 通过，1 = 发现违规。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "Sources"

# `String.Encoding` 在 Apple 平台上**确实存在**的成员（白名单）。
# 依据：Foundation 的 String.Encoding 静态属性。
VALID_STRING_ENCODING_MEMBERS = {
    "ascii",
    "nextstep",
    "japaneseEUC",
    "utf8",
    "isoLatin1",
    "symbol",
    "nonLossyASCII",
    "shiftJIS",
    "isoLatin2",
    "unicode",
    "windowsCP1251",
    "windowsCP1252",
    "windowsCP1253",
    "windowsCP1254",
    "windowsCP1250",
    "iso2022JP",
    "macOSRoman",
    "utf16",
    "utf16BigEndian",
    "utf16LittleEndian",
    "utf32",
    "utf32BigEndian",
    "utf32LittleEndian",
}

# 已知被误用为 String.Encoding 成员的编码名 -> 正确的 CFStringEncodings 常量。
KNOWN_BAD_AS_STRING_ENCODING = {
    "gbk": "CFStringEncodings.GB_18030_2000",
    "gb2312": "CFStringEncodings.GB_18030_2000",
    "gb18030": "CFStringEncodings.GB_18030_2000",
    "big5": "CFStringEncodings.big5",
    "eucJP": "CFStringEncodings.EUC_JP",
    "eucKR": "CFStringEncodings.EUC_KR",
    "koi8R": "CFStringEncodings.KOI8_R",
    "isoLatin5": "CFStringEncodings.isoLatin5",
}

# 匹配 `String.Encoding` 上下文中的 `.member`，以及 `self = .member` 这类
# 出现在 `extension String.Encoding` 里的赋值。
PATTERNS = [
    # 显式 `String.Encoding.<member>`
    re.compile(r"\bString\.Encoding\.([A-Za-z_][A-Za-z0-9_]*)"),
    # `extension String.Encoding` 块内的 `self = .<member>` / `return .<member>`
    re.compile(r"\bself\s*=\s*\.([A-Za-z_][A-Za-z0-9_]*)"),
]


def find_extension_blocks(text: str) -> list[tuple[int, int]]:
    """粗略定位 `extension String.Encoding { ... }` 的行号区间（含 `private extension`）。"""
    blocks: list[tuple[int, int]] = []
    lines = text.splitlines()
    depth = 0
    start = -1
    for idx, line in enumerate(lines):
        if start < 0 and re.search(r"extension\s+String\.Encoding\b", line):
            start = idx
            depth = 0
        if start >= 0:
            depth += line.count("{") - line.count("}")
            if depth <= 0 and "{" in "".join(lines[start : idx + 1]):
                blocks.append((start, idx))
                start = -1
                depth = 0
    return blocks


def check_file(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return errors

    rel = path.relative_to(REPO)
    ext_blocks = find_extension_blocks(text)

    for lineno, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue

        members: list[tuple[str, str]] = []
        for pat in PATTERNS[:1]:
            for m in pat.finditer(line):
                members.append((m.group(1), "String.Encoding.<member>"))

        # extension 块内的 `self = .x` / `return .x`
        in_ext_block = any(s <= lineno - 1 <= e for s, e in ext_blocks)
        if in_ext_block:
            for m in PATTERNS[1].finditer(line):
                members.append((m.group(1), "extension String.Encoding 内的 .<member>"))

        for member, how in members:
            if member in VALID_STRING_ENCODING_MEMBERS:
                continue
            hint = KNOWN_BAD_AS_STRING_ENCODING.get(member)
            msg = f"{rel}:{lineno}: String.Encoding 没有成员 '{member}'（来自 {how}）"
            if hint:
                msg += f"\n    该编码在 Foundation 里不存在，应改用 {hint} + "
                msg += "CFStringConvertEncodingToNSStringEncoding(_:)"
            errors.append(msg)

    return errors


def main() -> int:
    if not SRC.is_dir():
        print(f"❌ 找不到源码目录：{SRC}")
        return 1

    all_errors: list[str] = []
    for path in sorted(SRC.rglob("*.swift")):
        all_errors.extend(check_file(path))

    if all_errors:
        print("❌ 发现平台专有 API 误用：\n")
        for e in all_errors:
            print(f"  {e}")
        print(f"\n共 {len(all_errors)} 处。")
        return 1

    print("结果：未发现「String.Encoding 成员名不存在」类误用 —— 空。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

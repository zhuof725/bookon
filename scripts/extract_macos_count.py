#!/usr/bin/env python3
"""从 `swift test` 的输出里提取 macOS 「All tests」执行总数。

用法: python3 scripts/extract_macos_count.py <swift_test_output.log>
输出: 把总数打印到 stdout（单独一行整数）。找不到则以非零码退出。

第 4 步收尾新增：macOS job 用它把测试总数写进 artifact，供 iOS job 做 iOS==macOS 核对。
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("用法: extract_macos_count.py <swift_test_output.log>", file=sys.stderr)
        return 2
    lines = open(sys.argv[1], encoding="utf-8", errors="ignore").read().splitlines()
    total = None
    for i, ln in enumerate(lines):
        if "Test Suite 'All tests' passed" in ln:
            for j in range(i + 1, min(i + 3, len(lines))):
                m = re.search(r"Executed (\d+) test", lines[j])
                if m:
                    total = int(m.group(1))
                    break
    if total is None:
        print("ERROR: 未能在 swift test 输出中找到 'All tests' 的 Executed 总数", file=sys.stderr)
        return 1
    print(total)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""从 `swift test` 的输出里提取 macOS 「All tests」执行总数。

用法: python3 scripts/extract_macos_count.py <swift_test_output.log>
输出: 把总数打印到 stdout（单独一行整数）。找不到时打印 `0` 并**成功退出**。

第 4 步收尾新增：macOS job 用它把测试总数写进 artifact，供 iOS job 做 iOS==macOS 核对。

⚠️ **宁可返回 0 也不让 job 额外失败**：
本脚本只是「统计数字」的辅助步骤。若它因测试本身失败（`All tests' failed`、
编译错误、日志被截断）而找不到 `Executed` 行，返回非零码会让 `swift test`
**已经**失败的信息被这个二级失败盖掉，日志里出现两条互相干扰的 error。
因此**匹配 `All tests` 时同时接受 passed / failed**，实在找不到就输出 `0` 并以 0 退出；
真正「测试是否通过」的判据始终由 `swift test` 自己的退出码承担。
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("用法: extract_macos_count.py <swift_test_output.log>", file=sys.stderr)
        return 2
    lines = open(sys.argv[1], encoding="utf-8", errors="ignore").read().splitlines()
    total = None
    # ① 优先：`All tests` 那一节（passed / failed 都接受）。
    for i, ln in enumerate(lines):
        if re.match(r"\s*Test Suite 'All tests' (passed|failed)", ln):
            for j in range(i + 1, min(i + 4, len(lines))):
                m = re.search(r"Executed (\d+) test", lines[j])
                if m:
                    total = int(m.group(1))
                    break
            if total is not None:
                break
    # ② 兜底：拿所有「Test Suite '.xctest'」节里最大的 Executed 数
    #    （即使 `All tests` 汇总行缺失，也能给一个可用于比对的量级数字）。
    if total is None:
        counts = [int(m.group(1))
                  for ln in lines
                  for m in [re.search(r"Executed (\d+) test", ln)] if m]
        if counts:
            total = max(counts)
    if total is None:
        print("WARN: 未能在 swift test 输出中找到任何 'Executed N test' 行，"
              "输出 0（不影响 job 成败判定）", file=sys.stderr)
        total = 0
    print(total)
    return 0


if __name__ == "__main__":
    sys.exit(main())

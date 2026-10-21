#!/usr/bin/env python3
"""合并各分片的批量校验结果，产出 passed-sources.json / failed-sources.json / 汇总报告。

用法:
    python3 Tools/CICheck/merge_check_results.py <分片结果目录> [输出目录]

输入目录里应包含各分片的：
    passed-sources.json / failed-sources.json / check-results.json / batch-check.log
输出：
    passed-sources.json  通过校验的书源
    failed-sources.json  失败的书源（含失败原因）
    check-results.json   全部明细
    check-summary.md     Markdown 汇总
    batch-check-all.log  合并后的完整日志
"""
import json
import os
import sys


def load(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: merge_check_results.py <shards-dir> [outdir]", file=sys.stderr)
        return 2
    src = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else "results"
    os.makedirs(outdir, exist_ok=True)

    passed, failed, details = [], [], []
    logs = []
    for root, _dirs, files in os.walk(src):
        for fn in sorted(files):
            full = os.path.join(root, fn)
            if fn == "passed-sources.json":
                passed.extend(load(full, []))
            elif fn == "failed-sources.json":
                failed.extend(load(full, []))
            elif fn == "check-results.json":
                details.extend(load(full, []))
            elif fn.endswith(".log"):
                try:
                    with open(full, "r", encoding="utf-8", errors="replace") as f:
                        logs.append("===== %s =====\n%s" % (os.path.relpath(full, src), f.read()))
                except Exception:
                    pass

    def dump(name, obj):
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1)

    dump("passed-sources.json", passed)
    dump("failed-sources.json", failed)
    dump("check-results.json", details)
    with open(os.path.join(outdir, "batch-check-all.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(logs))

    # 失败原因统计
    reason_count = {}
    group_count = {}
    for item in failed:
        reason = item.get("checkReason") or item.get("checkMessage") or "未知原因"
        reason_count[reason] = reason_count.get(reason, 0) + 1
        for g in item.get("checkGroups") or []:
            group_count[g] = group_count.get(g, 0) + 1

    total = len(passed) + len(failed)
    lines = []
    lines.append("# 书源批量校验汇总\n")
    lines.append("- 通过：**%d**" % len(passed))
    lines.append("- 失败：**%d**" % len(failed))
    lines.append("- 合计：**%d**\n" % total)
    if reason_count:
        lines.append("## 失败原因统计\n")
        lines.append("| 原因 | 数量 |")
        lines.append("| --- | --- |")
        for k, v in sorted(reason_count.items(), key=lambda kv: -kv[1]):
            lines.append("| %s | %d |" % (k.replace("|", "/"), v))
        lines.append("")
    if group_count:
        lines.append("## 失效分组统计\n")
        lines.append("| 分组 | 数量 |")
        lines.append("| --- | --- |")
        for k, v in sorted(group_count.items(), key=lambda kv: -kv[1]):
            lines.append("| %s | %d |" % (k.replace("|", "/"), v))
        lines.append("")
    if failed:
        lines.append("## 失败明细\n")
        lines.append("| 书源 | 地址 | 原因 | 失效分组 |")
        lines.append("| --- | --- | --- | --- |")
        for item in failed:
            name = str(item.get("bookSourceName", "")).replace("|", "/")
            url = str(item.get("bookSourceUrl", "")).replace("|", "/")
            reason = str(item.get("checkReason") or item.get("checkMessage") or "").replace("|", "/")
            groups = ",".join(item.get("checkGroups") or [])
            lines.append("| %s | %s | %s | %s |" % (name, url, reason, groups))
        lines.append("")
    with open(os.path.join(outdir, "check-summary.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print("合并完成：通过 %d / 失败 %d / 合计 %d" % (len(passed), len(failed), total))
    for k, v in sorted(reason_count.items(), key=lambda kv: -kv[1]):
        print("  %s: %d" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main())

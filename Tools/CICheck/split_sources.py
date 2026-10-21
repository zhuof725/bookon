#!/usr/bin/env python3
"""把书源 JSON 切成多个分片，供 GitHub Actions 并行校验。

用法:
    python3 Tools/CICheck/split_sources.py <sources.json> <outdir> [每片数量]

输出:
    <outdir>/shard-<i>.json   每个分片一个 JSON 数组
    stdout: 分片数
    写入 $GITHUB_OUTPUT: shards=["0","1",...]
"""
import json
import os
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: split_sources.py <sources.json> <outdir> [shard-size]", file=sys.stderr)
        return 2
    src = sys.argv[1]
    outdir = sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    if size <= 0:
        size = 60

    with open(src, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        # 兼容 {"sources": [...]} 包装
        for key in ("sources", "data", "list"):
            if isinstance(data.get(key), list):
                data = data[key]
                break
    if not isinstance(data, list):
        print("输入不是 JSON 数组", file=sys.stderr)
        return 2

    os.makedirs(outdir, exist_ok=True)
    shards = []
    if not data:
        # 空输入也要产出一个空分片，避免 matrix 为空导致 workflow 报错
        with open(os.path.join(outdir, "shard-0.json"), "w", encoding="utf-8") as f:
            json.dump([], f)
        shards.append("0")
    for i in range(0, len(data), size):
        chunk = data[i:i + size]
        path = os.path.join(outdir, "shard-%d.json" % (i // size))
        with open(path, "w", encoding="utf-8") as f:
            json.dump(chunk, f, ensure_ascii=False, indent=1)
        shards.append(str(i // size))

    print("共 %d 个书源，切成 %d 片（每片最多 %d 个）" % (len(data), len(shards), size))
    for s in shards:
        p = os.path.join(outdir, "shard-%s.json" % s)
        print("  %s  %d 个 -> %s" % (s, len(json.load(open(p, encoding="utf-8"))), p))

    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write("shards=%s\n" % json.dumps(shards))
    return 0


if __name__ == "__main__":
    sys.exit(main())

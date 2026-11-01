# 书源快照（data/sources）

这里只放**被代码或 CI 直接引用**的 Legado 书源 JSON。原先它们堆在仓库根目录，
既挡视线又容易被误当成工程配置；其余调试快照已清理（需要时从 Actions 的
artifact 或历史提交里取）。

| 文件 | 用途 | 引用方 |
| --- | --- | --- |
| `screened-sources.json` | 主书源池，批量校验的默认输入 | `user-source-test.yml` |
| `user-sources.json` | 用户自建书源，探针类任务的默认输入 | `user-source-test.yml` |
| `gy.json` | `--probe-search` 的默认样例 | `Tools/SourceTest/main.swift` |
| `mowan.json` | `--probe-toc` 的默认样例 | `Tools/SourceTest/main.swift` |

约定：

- **临时导出不要提交**，用 `/tmp` 或带 `local-` 前缀命名（已被 `.gitignore` 忽略）。
- CI 里的路径是 `data/sources/<文件名>`；workflow 的 `file` 输入填文件名或完整路径都可以。
- 单站点的精简 fixture 放 `Tools/SourceTest/Fixtures/`，只有需要整池校验的大文件才放这里。

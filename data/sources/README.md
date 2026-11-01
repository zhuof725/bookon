# 书源快照（data/sources）

这里放**需要长期留档**的 Legado 书源 JSON 快照，供 `Tools/SourceTest` 与
`.github/workflows/user-source-test.yml` 使用。原先它们堆在仓库根目录，
既挡视线又容易被误当成工程配置。

| 文件 | 用途 |
| --- | --- |
| `screened-sources.json` | 主书源池，批量校验（校验书源）默认输入 |
| `user-sources.json` | 用户自建书源，探针类任务默认输入 |
| `failed-sources-2026-10-21.json` | 某次全量校验的失败快照，用于回溯 |
| `shushan-test.json` / `qimo-test.json` / `fanqie-test.json` | 单站点定向回归 |
| `gy.json` / `mowan*.json` | `SourceTest --probe-toc` / `--probe-search` 的默认样例 |
| `thirteen-sources.json` | 小样本合集，跑得快 |

约定：

- **临时导出不要提交**，用 `/tmp` 或带 `local-` 前缀命名（已被 `.gitignore` 忽略）。
- CI 里的路径是 `data/sources/<文件名>`；workflow 的 `file` 输入只需填文件名。
- 单站点的精简 fixture 优先放 `Tools/SourceTest/Fixtures/`，只有需要整池校验的大文件才放这里。

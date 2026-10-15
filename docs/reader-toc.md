# 阅读器目录页

入口：阅读时点底部工具栏「目录」打开 `ReaderTocSheet`。目录页同时承载书源时间、已缓存标识与预缓存进度。

## ① 章节时间（书源 updateTime）

每行章节标题右侧显示书源 `ruleToc.updateTime` 解析出的时间文本（小字、次要色）。例如书山聚合的 `tag`、柒默的 `Info`、番茄的 `$.pyfqUpdate`。引擎（`WebBook.parseChapterNodes`）在抓目录时已解析进 `BookChapter.updateTime`；旧版本落盘的目录缓存缺该字段时宽松解码为空，不丢缓存，时间行不显示。没有时间字段的章节不显示时间，不虚构。

## ④ 已缓存标识

打开目录时后台逐章调用 `ChapterContentCache.hasCached(for:)`（只查内存/磁盘存在性，不读取正文、不占用内存 LRU），已缓存的章节在标题右侧显示 `arrow.down.circle.fill`，行无障碍值为「已缓存」。预缓存完成的章节会实时获得标识。

## ③ 预缓存进度条

右上角「预缓存」按钮（本地书籍或找不到书源时隐藏）。点按后从当前章之后取 20 个可读章节（`ChapterNavigation.prefetchIndices`，跳过卷标题，越界截断）逐章预取：

- 进度条 `ProgressView(done/total)` 与状态文案显示在目录列表上方。状态：`正在预缓存 X/N` / `预缓存完成：共 N 章` / `已停止：已缓存 X/N` / `预缓存中断：<原因>`。
- 已缓存的章节直接计入完成数、不重复请求书源。
- 预缓存走与阅读/预读同一条链路（`ChapterContentLoader` → `ChapterContentCache`），共享在途任务合并，不会对同章重复抓取。
- 失败即停并保留已完成进度，提供「重试」从失败章节续跑（已缓存章节仍跳过）。可「停止」主动中止。
- 离开阅读器时取消在途预缓存并清除进度条；阅读期间关闭目录页不影响后台继续预缓存，下次打开目录页可见进度。

## 测试

- `Tools/SourceTest/ChapterContentCacheRegression`：`hasCached` 未缓存/已缓存/磁盘识别/不占内存/清空后消失（source-test / cache-management 套件）。
- `Tools/ReaderInteractionTest/Tests/TocSheetTests`（`reader-toc` 套件，macos-26）：行时间与缓存标识、预缓存完成窗口并跳过已缓存（loads=17）、失败即停并重试续跑（loads=17）、停止与关闭。

# 漫画（图片源）支持

对齐原版 legado 的漫画阅读：`bookSourceType == 2` 的书源（如「武芊漫画」）在阅读时
进入漫画阅读器，而不是文字排版。

## 书源识别

- `MangaBook.isManga(source:)`：书源类型为 2 即漫画源（与原版按 bookSourceType 进入
  ReadMangaActivity 一致）。
- 阅读器启动时判定（`ReaderView.start()`），漫画书源跳过文字正文加载，交给 `MangaSession`。

## 正文与图片提取（`Sources/Engine/MangaBook.swift`)

- 漫画源的正文规则输出是一组 `<img>` 标签（「武芊漫画」用 JS 把 `$.data[*].image`
  的地址逐行包成 `<img src="…">`）。
- `MangaBook.imageURLs(in:baseURL:)` 对应原版 `BookHelp.flowImages`：
  - 宽松匹配 `<img … src="…">`（双引号为主，兼容单引号/无引号）；
  - 相对地址相对章节地址转绝对（`NetworkUtils.getAbsoluteURL`）；
  - `javascript:` 丢弃、`data:` 保留；
  - 相邻重复地址只保留一个（原版 `distinctUntilChanged`）。
- 正文缓存与文字书共用（`ChapterContentCache`），但不做段落归一化。

## 阅读器（`Sources/App/MangaReader.swift` + `MangaScrollView.swift` + `MangaPagedView.swift`）

对应原版 ReadManga / ReadMangaActivity：

- **阅读方式**：更多菜单 →「阅读方式」，四种可选，记在 `reader.manga.mode.v1`：
  - 从右到左（默认漫画手感）：整页横滑，`MangaPaging` 把整章倒序铺开，第 0 页在最右，
    手指向右滑进入下一页，点按左/右分别为下一页/上一页；
  - 从左到右：整页横滑，向左滑进入下一页；
  - 纵向翻页：一页一屏纵向吸附，向上滑进入下一页；
  - 条漫：纵向连续滚动（默认）。
  分页模式拖过章末/章首回弹会切到相邻章（往回翻落在上一章最后一页）。
- **三章窗口**：`MangaSession` 维护「上一章 / 当前章 / 下一章」的图片列表
  （原版 prev/cur/next MangaChapter 与 loadContent ±1），滚动到章尾/章头前自动补齐；
  相邻章加载失败后显示「点按重试」，自动重试只做一次。
- **连续滚动**：UICollectionView（对应原版 RecyclerView）竖向滚动全部图片，
  图片按屏幕宽度降采样、单元格复用以控制内存；未加载图片按常见条漫比例占位，
  加载完成后按真实宽高比排版并保持当前可见内容位置不动。
- **章节无缝相接**：不再插入「阅读 X / 已读完 X」分章标记（那会撑出两屏白带），
  章节之间直接接上；换章时顶部短暂浮出一下章节名，不占布局。
  最后一章末尾显示「暂无章节了！」。
- **点击分区**：面板隐藏时，条漫按左下/右下翻一屏、其余任意位置呼出面板；
  分页模式左/右（纵向为上/下）翻页、中间呼出面板。面板显示时点任意位置收起（无震动反馈）。
- **浮动面板**（对齐参考图）：左上圆形「关闭 / 目录」按钮、居中章节名、右上「更多」
  （阅读方式、上一章、下一章、刷新目录、清除本话缓存并重载、书籍操作、阅读设置）；
  底部玻璃胶囊按参考图重做：奶白淡染（固定白色 tint，不随背景变黑）+ 细轨道、
  白色药丸滑块，下一行居中「当前页 / 总页数」、右侧「剩余 N 页」。
- 图片未加载时按常见条漫比例（1.42）占位，避免一屏高度占位导致图片上下留白。
- **进度**：`durChapterPos` 存「本章第几张图」（原版 durChapterPos 语义），
  章节切换 / 页变化时经 `AppStore.updateMangaProgress` 落盘；目录跳转走 `jump(to:)`
  会重置章节窗口。
- 图片加载失败显示「图片加载失败，点按重试」；当前章加载失败有整屏重试。

## 旧目录缓存修复

- 旧版本缓存的目录可能把 `@get:{comic_id}` 原样存进章节地址（或变量为空），
  正文接口会返回「漫画标识不能为空」，表现为「本章没有图片」。
- `MangaBook.isUnresolvedChapterURL` 识别残留模板；阅读器启动时发现即重抓目录。
- `WebBook.tocRuleUsesVariables`：目录规则含 `@get:` 时，重抓目录前先跑一次详情页，
  把 `@put` 变量（comic_id）写进当前会话。
- 漫画阅读器第一次遇到「本章没有图片」会自动刷新一次目录；错误覆盖层也提供「刷新目录」按钮，
  刷新后按标题重定位当前章（修复后的章节地址会变化）。

## 未做（与真机验证项）

- 双指缩放 / 双击放大（原版 WebtoonRecyclerView 的缩放手势）。
- 灰度 / 墨水屏 / 色彩滤镜、自动翻页 / 自动滚动、横屏滚动、图片保存长按菜单。
- 真机观感与流量（图片按需加载，无磁盘缓存）。

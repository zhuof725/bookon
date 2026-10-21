# 书山聚合 v5.63 适配

## 已修复（应用端）
1. 书源 `header` 支持 `@js:` / `<js>` / `{{key}}`：此前该源每个请求都发不出 `X-Api-Key`，实测改为真实字段后搜索接口才返回数据。
2. 规则脚本用块级作用域执行：源里 `let source = ...` 与桥接全局 `var source` 冲突，JavaScriptCore 会抛 SyntaxError，导致 892 条结果全部解析失败。现在局部变量与函数库全局绑定互不影响。
3. `book.getVariable/putVariable` 接入独立存储（与 `java.put/get` 分离、按书籍隔离），源用于持久化段评开关。
4. 补齐 `ContentRule.subContent/payAction/callBackJs`、`TocRule.isPay`，导入不再静默丢字段；`source.loginUi`、`book.type` 对脚本可见。

## 实测结论（CI，无账号）
- 搜索：892 条，892 个不同书籍地址（修复前全部回退成搜索页地址）。
- 详情：名称与目录地址正常；目录：712 章。
- 正文：返回内容仍是编码态，未验证为可读中文。另有一类「无换行、句末标点 + 全角空格」的文本形式会缺少段落边界；该恢复**已对所有书源生效**（见 `docs/reader-layout.md` 的段落边界一节），不再按源名判断。规则有离线合成断言，尚未取得用户当前章节的解码后原文作真机目视确认。

## 登录跳转
- 登录相关的跳转（loginUrl 为网址时的「打开登录页面」、loginUi 按钮配置的网址、登录脚本里 `java.startBrowser/showBrowser/startBrowserAwait` 请求的网址）改为在应用内浏览器打开，不再跳出到系统浏览器；关闭时按书源开关回流该主机 Cookie。
- 只有真正需要跳转的 http(s) 网址进入内置浏览器：`javascript:`、`file:`、`mailto:`、相对路径、缺主机名、含空白或换行、超长输入都会被拒绝并提示。
- 内置浏览器提供后退/前进/刷新/完成/取消；未登录状态下打开的是书源自己的登录页。

## 书源运行时字段（2026-10-21 接入）
- `concurrentRate`：请求前按「次数/毫秒」限速（`SourceRateLimiter`），`1500` 表示每 1.5 秒最多 1 次。
- `loginCheckJs`：每次书源请求拿到响应后执行一次；`result` 是响应对象（`code`/`body`/`headers()`），
  返回响应对象可改写响应，抛错时按原版语义再求值一次（返回非 500 才采用），否则保留原响应。
- `coverDecodeJs`：封面下载后执行脚本解密（`result` 是字节数组），解密失败保留原图；由
  `CoverDecodeRuntime` 注入，未配置该字段的书源仍走系统图片加载。
- `callBackJs` + `eventListener`：接入 `addBookShelf` / `delBookShelf` / `startRead` / `saveRead` /
  `endRead` / `clickCustomButton` 六个事件，脚本可用 `event` 变量取事件名。
- `customButton`：阅读页快捷面板出现「书源按钮」，点击触发 `clickCustomButton` 回调。

## 未解决
- 正文：源内 `decode()` 使用 17 字节 AES 密钥，任何 AES 实现（含 Hutool）都会拒绝；未猜密钥、未把乱码当成功。需账号登录后的返回格式或源作者修正。
- 听书/短剧/下载类型（`book.type`）：未实现（`bookSourceType = 1` 的音频书源已可正常搜索与朗读）。
- 未登录时 `X-Api-Key` 为空，部分接口会提示登录。

## 发现页
- 应用已有「发现」页（底栏第 2 个标签，`DiscoverView`）：按分组列出可探索的书源 → 点进书源看它的
  分类（`exploreUrl`）→ 分类下再取书单。见 `docs/discover.md`。
- 书山聚合这类源若要出现在发现页，需满足：书源已启用、`enabledExplore` 不为 false、`exploreUrl` 非空。

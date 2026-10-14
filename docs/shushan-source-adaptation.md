# 书山聚合 v5.63 适配

## 已修复（应用端）
1. 书源 `header` 支持 `@js:` / `<js>` / `{{key}}`：此前该源每个请求都发不出 `X-Api-Key`，实测改为真实字段后搜索接口才返回数据。
2. 规则脚本用块级作用域执行：源里 `let source = ...` 与桥接全局 `var source` 冲突，JavaScriptCore 会抛 SyntaxError，导致 892 条结果全部解析失败。现在局部变量与函数库全局绑定互不影响。
3. `book.getVariable/putVariable` 接入独立存储（与 `java.put/get` 分离、按书籍隔离），源用于持久化段评开关。
4. 补齐 `ContentRule.subContent/payAction/callBackJs`、`TocRule.isPay`，导入不再静默丢字段；`source.loginUi`、`book.type` 对脚本可见。

## 实测结论（CI，无账号）
- 搜索：892 条，892 个不同书籍地址（修复前全部回退成搜索页地址）。
- 详情：名称与目录地址正常；目录：712 章。
- 正文：返回内容仍是编码态，未验证为可读中文。

## 登录跳转
- 登录相关的跳转（loginUrl 为网址时的「打开登录页面」、loginUi 按钮配置的网址、登录脚本里 `java.startBrowser/showBrowser/startBrowserAwait` 请求的网址）改为在应用内浏览器打开，不再跳出到系统浏览器；关闭时按书源开关回流该主机 Cookie。
- 只有真正需要跳转的 http(s) 网址进入内置浏览器：`javascript:`、`file:`、`mailto:`、相对路径、缺主机名、含空白或换行、超长输入都会被拒绝并提示。
- 内置浏览器提供后退/前进/刷新/完成/取消；未登录状态下打开的是书源自己的登录页。

## 未解决
- 正文：源内 `decode()` 使用 17 字节 AES 密钥，任何 AES 实现（含 Hutool）都会拒绝；未猜密钥、未把乱码当成功。需账号登录后的返回格式或源作者修正。
- 发现入口：本应用暂无发现页，`exploreUrl` 已完整保留但无入口。
- 书架同步 `callBackJs`、`customButton`：字段已保留，未接入事件。
- 听书/短剧/下载类型（`book.type`）：未实现。
- 未登录时 `X-Api-Key` 为空，部分接口会提示登录。

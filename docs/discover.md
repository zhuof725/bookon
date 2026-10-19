# 发现（书源浏览）

底栏新增「发现」标签（书架 / 发现 / 统计 / 我的 + 搜索），按分组浏览书源的发现内容。

## 结构

1. **分组**：可发现的书源按分组列出（与书源管理同一规则：取第一个分组名归类，无分组归「默认分组」并放最后），每行显示首字头像、分组名与书源数。
2. **书源**：点进分组后显示该组书源卡片（首字头像、名称、类型标签、域名）。
3. **分类**：点进书源后读取它的发现规则（`exploreUrl`，支持 `@js:` / `<js>`）；规则里没有网址的项作为小节标题（对应原版的 flexGroup 分组，如「推荐」「最热」「最新」），其余为可点分类。脚本失败时显示错误并可重试。
4. **书单**：点进分类后加载书籍列表（`ruleExplore`，缺省回退搜索规则）；分类地址含 `{{page}}` 时底部提供「加载更多」，翻页按 `bookUrl` 去重；点书籍进入原有详情页。

## 参与条件

- 书源启用（`enabled`）且「启用发现」（`enabledExplore`，缺省开启）
- 配置了非空的 `exploreUrl`

## 入口与显示顺序

`LibraryTab.discover`（rawValue 固定为 4，不影响已存序号）；显示顺序由 `LibraryTab.displayOrder` 决定，搜索固定在底栏最右。iOS 26 使用系统 TabView，旧版 iOS 使用 `LibraryDock`。

## 代码

- 整理逻辑：`Sources/Engine/DiscoverCatalog.swift`（过滤、分组、域名、分类切节、头像色）
- 界面：`Sources/App/DiscoverView.swift`（发现 → 分组 → 书源 → 分类 → 书单）
- 回归：`Tools/SourceTest/DiscoverRegression.swift`（离线夹具：武芊漫画的 74 项发现分类与 4 段切节）

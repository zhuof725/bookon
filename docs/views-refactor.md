# ReaderView.body 类型推断问题

## 症状

`Sources/App/Views.swift` 的 `ReaderView.body` 编译报：

```
error: the compiler is unable to type-check this expression in reasonable time;
       try breaking up the expression into distinct sub-expressions
```

改 `body` 里任何一处（哪怕只是把 `.onChange(of:) { _ in }` 写成 `{ }`）
都可能触发，看起来像「改 A 报 B」，很难定位。

## 根因

不是某一处写法的问题，是**整个 ViewBuilder 表达式的规模**。Swift 对 ViewBuilder
的类型推断是组合爆炸的：body 里出现的每个 identifier（`@State`、计算属性、方法名）
都要参与重载决议。

`ReaderView` 有 100 多个成员：40 多个 `@State`、20 多个计算属性、60 多个月方法。
body 一条链上曾串着 31 个 `onChange` + 13 个 sheet/fullScreenCover。

## 已解决的问题（build 120，警告 151 → 89）

**合并观察点是关键**。原先 14 个 `settings.xxx` 各挂一个 onChange，都只做
`scheduleRepaginate()`：

```swift
.onChange(of: settings.fontSize) { scheduleRepaginate() }
.onChange(of: settings.lineSpacing) { scheduleRepaginate() }
.onChange(of: settings.paragraphSpacing) { scheduleRepaginate() }
// ... 共 14 个
```

改为 `ReadSettings.paginationSignature`（项目里已有 `paperSignature` /
`chapterTitleSignature` 的先例）：

```swift
var paginationSignature: String {
    ["\(fontSize)", "\(lineSpacing)", ..., paperSignature].joined(separator: "|")
}
```

body 里只剩一行：

```swift
.onChange(of: settings.paginationSignature) { scheduleRepaginate() }
```

同理，`geo.size` + `geo.safeAreaInsets` 合并成 `viewportKey(geo)`。

配合这步，剩余的旧写法迁移才陆续通过。**先减少 identifier 数量，再改写法。**

## 走过的弯路（不要重复）

| 尝试 | 结果 |
| --- | --- |
| `{ _ in }` 改 `{ }`（零参） | **更慢**。iOS 17 的零参重载需要枚举更多候选，反而加剧推断 |
| 把 sheet 抽成计算属性 | 只减少一层嵌套，body 里其余 identifier 数量不变，仍然超时 |
| 抽成独立 ViewModifier（闭合 27 个 onChange） | 同上，结构对了但没解决规模问题 |
| 给 `ChapterTitleLayout` / `ReaderPaginator` / `ReaderTextLayout` 加 `@MainActor` | 把整条 TextKit 调用链拖进隔离检查，`Measurer.rows` 等连锁报错 |
| 拆分 `SearchView` 到独立文件 | 这步本身对了（Swift 按文件做类型检查），但救不了 `ReaderView` |
| 把 5 个 onChange 的闭包体抽成方法，只留一行调用 | **仍然超时**。编译器解析的是整条 modifier 链的表达式类型，闭包体大小不是主因 |

**余量是有限的**：合并到 17 个 onChange 后再迁移 7 处能过；再多 3 处就超时。
不要假设「上次改成功了这次也能」。

## 已经做成的部分（build 150 时的状态）

警告 151 → 10。`@MainActor` 那批是**逐个方法标注、每步等 CI 验证**才走通的：

| 文件 | 标注内容 |
| --- | --- |
| `ReaderTextLayout` | `configure` / `height(of:)` / `rows(of:)` / 整个 `Measurer` 类 |
| `ReaderPaginator` | `paginate` / `textLineEnds` / `measured` / `nonTextHeight` |
| `ChapterTitleLayout` | `textHeight` / `height` / `label` |
| `Configuration.headerHeight` | 用 `MainActor.assumeIsolated`（它是 Equatable 值类型，不能整体隔离） |
| `ReaderScrollBoundaryObserver` | KVO 回调里 `assumeIsolated` |
| `PhotosPicker` label 闭包 | 先取局部值，不捕获 `@ObservedObject` |

关键教训：**一次只改 1~2 处**。一次改 8 处只会得到一堆连锁错误，
分不清哪条是根因。

## 剩余工作

还剩 5 处 `onChange`（`Views.swift` 约 504 / 528 / 546 / 553 / 559 行）
和 4 处 `ReaderTextLayoutManager.drawBackground`。

**onChange**：要彻底解决，需要把 `ReaderView` 的 40 多个 `@State` 收进
`@Observable final class ReaderModel`，body 里只出现 `model.xxx`。

**drawBackground（已解决）**：做法是让 nonisolated 的 override 只读
**值类型状态**，不碰 UITextView：

1. `CommentTextView.highlightedRange` / `highlightColor` 标 `nonisolated(unsafe)`
   （UIKit 只在主线程绘制，读它们安全）
2. 绘制矩形改用 `NSLayoutManager` 自己的 `textContainers.first`，
   不再访问 `view.textContainer`（UITextView 的主 actor 属性）

试过但失败的：override 上加 `@MainActor`（与 nonisolated 基类冲突）、
`assumeIsolated { self.xxx }`（捕获 self 报 data races）、
类级 `@MainActor` + nonisolated override（同样在 assumeIsolated 处报错）。

**5 处 onChange（硬边界）**：`ReaderView.body` 里**哪怕只改 1 处**也会超时。
试过的顺序：合并 14 个为 1 个后改 7 处通过 → 再改 3 处超时 → 抽闭包体后改 5 处超时
→ 只改 1 处仍超时。余量确实耗尽，只能靠 ReaderModel 重构。

两项都是重构级别的改动，需要本地 Xcode 环境反复迭代——CI 每轮 5~10 分钟，
盲改成本太高。

## 验证方式

沙箱没有 Swift 工具链，只能靠 CI：

```sh
# 看最近一次构建
gh run list --workflow=build.yml --limit 3

# 编译错误在 artifact 的 build.log 里
gh run download <run-id> -n build-log
grep ': error:' build.log
```

注意 `build.yml` 用 xcpretty 过滤输出，`The following build commands failed`
之前的 `⚠️` 行里可能混着真正的 error，别只看最后几行。

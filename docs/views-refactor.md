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

**余量是有限的**：合并到 17 个 onChange 后再迁移 7 处能过；再多 3 处就超时。
不要假设「上次改成功了这次也能」。

## 剩余工作

还剩 6 处带参 `onChange` 在 `Views.swift`（约 504 / 528 / 546 / 553 / 559 / 1561 行）。
要彻底解决，需要：

1. 把 `ReaderView` 的 40 多个 `@State` 收进 `@Observable final class ReaderModel`
2. body 里只出现 `model.xxx`，identifier 数量降到可控
3. 之后再迁移剩余写法

这是重构级别的改动，需要本地 Xcode 环境反复迭代——CI 每轮 5~10 分钟，
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

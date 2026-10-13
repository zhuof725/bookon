# 自定义主题设置：离线回归说明

## 运行范围

手动工作流 `reader-interaction.yml` 的 `theme-customization` 选择：

- `ThemeCustomizationTests`：完整设置模型、图片安全/清理、真实 surface 像素、保存/应用/取消/进程重启及真实 dock/书架交互。
- `CustomThemeTests`：原有色值、主题存储、颜色独立性、删除回退、外观首页和详情截图回归；创建流程已改为直接进入设置。
- `AppearanceTests`、`ShelfTests`：保留原有外观/书架/导航按钮回归。

保持 20 分钟工作流上限，不新增网络请求、CI dispatch、提交或推送。该选择不是整个 `full` 套件，也没有重复选择 DetailTests；原有 CustomThemeTests 仍覆盖生产详情的深色窄屏截图。

```sh
cd Tools/ReaderInteractionTest
xcodegen generate
xcodebuild -project ReaderInteraction.xcodeproj -scheme ReaderHarness \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -parallel-testing-enabled NO \
  -only-testing:ReaderInteractionTests/ThemeCustomizationTests \
  -only-testing:ReaderInteractionTests/CustomThemeTests \
  -only-testing:ReaderInteractionTests/AppearanceTests \
  -only-testing:ReaderInteractionTests/ShelfTests \
  -resultBundlePath theme-customization.xcresult CODE_SIGNING_ALLOWED=NO test
```

工程显式添加生产 `ThemeCustomization.swift`、`ThemeAssetStore.swift`、`ThemeCustomizationEditor.swift`、`ThemeImagePicker.swift`，不是用测试替身重写生产实现。图片/模型探针运行于 ReaderHarness，XCUITest 要求必需检查键存在且结果为 true；缺键、fixture 抛错都失败。

## 模型与存储断言

- 字面量旧 JSON 缺 customization 时保持 nil；内置主题保持 nil；不以新编码器伪造旧数据。
- `AppTheme.custom()` 唯一 UUID、非内置、经典黑白中性配色、solid 及完整默认设置。
- 默认值：iconsAndText / 3 列 / 112 pt / 三图 nil / 字体 nil / transparent / cardBackground=true。
- `{}` customization 向后兼容；未知 enum、错误 JSON 类型拒绝。
- 列数 2...5、封面宽度 60...180 端点及全部枚举组合编码与仓库重读。
- 1/6 列、59.99/180.01 pt、负数、极值、NaN、正负无穷拒绝；失败保存不改已持久化字节及选择。
- 字体 nil（跟随全局）、空串（系统）、有效/不可用字体名分别保持；超过 128 字及控制字符拒绝。
- save 不隐式 apply，apply 后新仓库实例恢复；阅读字号、行距、阅读主题、外观模式及书籍哨兵字节保持。独立 ReadingFontManager 不被改选。

## 图片安全与清理断言

全部图片为 UIGraphicsImageRenderer 生成的离线数据，使用注入的 UUID 临时目录 `ThemeAssetStore(directory:)` 和独立 defaults。绝不导入或删除 shared 用户图片。

- importFile/importData 得到合法 ID、可解码图片；源文件字节不变；删除源后新 asset-store 实例仍能读取副本。
- 三图片字段 assetIDs 去重及 Codable 往返；图片 ID 不是任意路径。
- 空值、非 ID、绝对路径、file/https URL、`../`、编码遍历、反斜杠、NUL 拒绝；remove 不能影响目录外哨兵文件。
- 非图片、空数据、缺失文件、带合法 PNG 前缀但超过上限的数据/文件拒绝；失败无残留文件，源大文件保持。
- 2400×1200 输入落盘后新实例解码为 2000×1000；检验实际 CGImage 尺寸。
- 文件 symlink 不读、不删目标；作为存储根的 symlink 不允许读/写/删；真实根及哨兵保持。
- 重复 remove 安全且持久；旧图片替换后仅移除已无引用者。
- 两个仓库实例先后保存 A/B 共用图片，A 的旧编辑器保存时须保留 B 引用；apply 不清理；无效 save 不清理；最后引用删除后才删除图片。
- 未被任何已保存主题引用的 fixture 图片不能被仓库批量误删。

## UI 与运行时断言

稳定入口：`theme.add` 直接进入编辑器；不存在 `theme.template.*` 按钮。

设置摘要行：

| ID 后缀 | 含义 |
| --- | --- |
| `tab` | Tab 栏 |
| `shelf` | 书架列数与封面宽度 |
| `cover` | 默认封面 |
| `launch` | 启动图 |
| `colors` | 颜色与字体 |
| `background` | 页面背景 |
| `effect` | 界面效果 |
| `cards` | 卡片背景 |

完整 ID 为 `theme.editor.row.<后缀>`，详情为 `theme.editor.page.<后缀>`。保留 `theme.editor.name/save/cancel/discard`。

新增主要测试：

1. `ThemeCustomizationTests/testProductionModelAssetsCleanupAndRenderedEffects`：强制要求模型/资源探针键全部存在；真实 ThemeSurface 的 transparent/opaque/card-off/降低透明度中心像素断言，字体不可用 UIKit fallback，生产 ThemeShelfMetrics 窄屏限幅。
2. `ThemeCustomizationTests/testSettingsSaveApplyRuntimeDockShelfCancelAndRelaunch`：用真实按钮、Stepper、Slider、Toggle 设置 text / 2 列 / 60 pt / opaque / 无卡片底 / 系统字体；保存后检查完整 JSON，先不应用；应用后测量真实 BookshelfScreen，点击真实 LibraryDock 和书籍触发回调；随后修改草稿取消、终止进程、无 seed 重开，验证设置与所选 ID 不变。

控制 ID：`theme.editor.tab.text/icons/iconsAndText`、`theme.editor.shelf.columns/width`、`theme.editor.effect.*`、`theme.editor.cards.enabled`、`theme.editor.font.follow/system`；原有 hex、mode、cardRadius、cardBorder 均在对应详情中使用。

运行时 ID：`theme.preview.shelf/back`、`library.tab.0/1/2`、`shelf.book.customization-0...5`、`theme.runtime.callbacks`。回调报告证明实际点击动作发生，不能只读配置报告冒充执行。

320 pt 结论只适用于实测 width=320 的生产书架/首页及原有详情。外层 frame 不保证 fullScreenCover 编辑器为 320；摘要/深色编辑器截图明确标注 native presentation，不宣称 320 编辑器已通过。

## 证据与当前边界

- XCUITest 附件保留摘要、深色颜色详情、应用后的 320 书架，以及原有色值/首页/详情截图；`customization-model-assets-render-evidence` 保存必需检查结果。工作流导出 `custom-theme-screenshots` 及既有 xcresult/log。
- 本地 Linux 环境没有 Swift/Xcode/iOS Simulator。仅执行了全部 harness Swift 的 tree-sitter 语法解析、YAML/source 路径及工作流选择检查、git diff --check；这些不等同 Swift 编译或模拟器通过。实际总耗时及 20 分钟预算需首次 CI 实测。
- 原生图片文件选择器的打开/取消已由 `ThemeCustomizationTests/testNativeImagePickerCancelPreservesDraftAndSavedStore` 覆盖：确认 Cancel 可操作、回到封面详情、无图片移除按钮、名称草稿保留、最终取消后仓库字节不变。成功挑选文件、取消已导入图片的草稿清理及 shared runtime 图片注入仍非此 suite 的 E2E。临时资产持久化覆盖新实例重读，不冒充应用重启后的图片 UI 验证。
- 默认封面只在无效/缺失封面时兜底、已有封面不被覆盖，以及页面照片合成/磨砂材质最终像素尚未新增完整 E2E；原有 CoverPersistenceTests 不在 focused 选择内，仍保留可单独运行。
- 启动图冷启动仅一次/前后台不重现/跳过、真正 320 编辑器、VoiceOver、大字体与真实设备照片权限仍须进一步系统级验证。不能将保存 launchImage 字段等同启动体验已验证。
- UIKit 字体 fallback 探针不是整个阅读分页管线的端到端验证；已有字体/分页 suites 保持独立。

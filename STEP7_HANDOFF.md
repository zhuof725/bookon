# 第 7 步 交付说明（STEP7_HANDOFF）

> 本文件为第 7 步（A/B/C 段）最终交付状态说明。CI 三 job 全绿 + build-ipa artifact 需推送
> GitHub 后由 Actions 运行产出（本地沙箱无法触发），其余交付物均已就绪并经本地校验。

## 一、交付内容总览

| 段落 | 内容 | 状态 |
|---|---|---|
| A | WebBook 流程层源码移植（搜索/详情/目录/正文/发现/调试） | ✅ 完成，typecheck 通过 |
| A | 流程层测试（154 @testable + 5 public）+ 端到端（7 真实规则） | ✅ 完成 |
| A | golden：HtmlFormatter 85 条 + wordCountFormat 35 条（手工 Java 移植） | ✅ 完成，本地已生成验证 |
| B | BookonDebugKit（@Observable：仓库/会话/日志/设置/清 Cookie 缓存） | ✅ 完成 |
| B | BookonDebugKitTests（82 用例） | ✅ 完成 |
| C | SwiftUI App「书源调试」+ project.yml + Info.plist | ✅ 完成 |
| C | build-ipa CI job + build_ipa.sh + test-ios-simulator 构建 App target | ✅ 完成（配置就绪） |
| D | README 差异表 / 不做清单 / 手机使用说明 / FUNCTION_MAPPING | ✅ 完成 |

## 二、本地校验结果（Linux 沙箱，可复现）

```
scripts/local_typecheck.sh          -> ✅ 类型检查通过（源码，含 shim）
scripts/local_typecheck_tests.sh    -> 流程层测试 typecheck 通过
scripts/local_typecheck_bookon.sh   -> BookonDebugKit 测试 typecheck 通过
python3 scripts/verify_functions.py -> 「Kotlin 有但 Swift 没实现的函数」清单：空
python3 scripts/verify_fields.py    -> 「Kotlin 有但 Swift 没实现的字段」清单：空
scripts/golden (mvn package + run)  -> HtmlFormatter 85 条 + wordCountFormat 35 条
```

测试用例数（XCTest 方法计数）：

| target | 用例数 |
|---|---|
| LegadoWebBookTests（流程层，@testable） | 154 |
| LegadoWebBookPublicAPITests（流程层，非 @testable） | 5 |
| BookonDebugKitTests（B 段） | 82 |

> 说明：以上为**本地 typecheck + 逻辑推演 + golden 本地生成**验证。154/5/82 个测试的
> **运行时通过**、iOS==macOS 用例数相等、golden 逐条比对，需 macOS CI 执行确认。

## 三、CI 三 job + build-ipa（需推送 GitHub 触发）

`.github/workflows/test.yml` 现有 4 个 job：

1. **golden**（ubuntu-latest）：Maven 构建 golden 生成器 → 生成全部 golden JSON → upload-artifact。
2. **test-macos**（macos-14，needs golden）：`swift test` + 提取测试总数 → upload-artifact。
3. **test-ios-simulator**（macos-14，needs golden+test-macos）：`xcodebuild test`（iOS 17 模拟器）
   + **构建 App target** + iOS==macOS 用例数核对。
4. **build-ipa**（macos-14，needs golden+test-macos）：`xcodegen generate` → `xcodebuild archive`
   （Release、无签名、注入 `GIT_COMMIT`/`CI_RUN_ID`）→ 校验 `MinimumOSVersion == 17.0` →
   `Payload/BookonDebug.app` zip 成 `BookonDebug.ipa` → upload-artifact `bookon-debug-ipa`。

**验收需在 GitHub 上**：
- 推送本仓库到远端（`git push`），观察 4 个 job 全绿。
- 下载 `bookon-debug-ipa` artifact 与 golden artifact。
- 把真实日志留存到 `ci_logs/step7_final_*.log`（golden / macOS swift test / iOS xcodebuild test）。

## 四、关键文件清单（本次新增/修改）

**源码**
- `Sources/LegadoBookSource/WebBook/`（9 个文件：WebBook/BookList/BookInfo/BookChapterList/BookContent/Debug/WebBookSupport/WebBookNetwork/WebBookOptions）
- `Sources/LegadoBookSource/RuleEngine/DebugLogger.swift`、`HtmlFormatter.swift`、`StringUtils.swift`
- `Sources/LegadoBookSource/Network/CacheManager.swift`（新增 `clearAll()`）

**B 段**
- `Sources/BookonDebugKit/`（5 个文件：BookSourceRepository/DebugSession/DebugLogStore/DebugSettings/DebugEnvironment）

**C 段**
- `App/`（5 个 SwiftUI 文件 + Info.plist）
- `project.yml`、`scripts/build_ipa.sh`

**测试**
- `Tests/LegadoWebBookTests/`（16 个文件，154 用例）
- `Tests/LegadoWebBookPublicAPITests/`（1 个文件，5 用例）
- `Tests/BookonDebugKitTests/`（8 个文件，82 用例）+ `Resources/{配置文件_14个,malformed_sources}.json`
- `Tests/LegadoWebBookTests/Resources/{配置文件_14个,synthetic_flow_pages}.json`

**验收/文档/CI**
- `scripts/verify_functions.py`（扩展 webBook/*.kt + Debug.kt）
- `scripts/local_typecheck.sh`、`scripts/local_typecheck_tests.sh`、`scripts/local_typecheck_bookon.sh`
- `scripts/golden/src/main/java/golden/{HtmlFormatterGen,WordCountGen}.java` + `Main.java`
- `scripts/golden/cases/{html_formatter_cases,word_count_cases}.json`
- `reference/kotlin/analyzeRule/webBook/*.kt`、`reference/kotlin/analyzeRule/Debug.kt`
- `.github/workflows/test.yml`、`Package.swift`、`README.md`、`FUNCTION_MAPPING.md`、`.gitignore`

## 五、未完成 / 需人工

- CI 四 job 实际运行与日志留存（需 GitHub Actions）。
- `build-ipa` 运行链接 / artifact 确认（需 GitHub）。
- App 的 SwiftUI 界面运行时验证（Linux 无法编译 SwiftUI，需 macOS/iOS）。
- 书源编辑/分享等 UI 细节（README「不做」清单已声明）。

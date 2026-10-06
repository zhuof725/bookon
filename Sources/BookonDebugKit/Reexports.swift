//
//  Reexports.swift
//  BookonDebugKit
//
//  第 7 步 C 段返工：**重新导出 LegadoBookSource**。
//
//  为什么需要这个文件：
//      BookonDebugKit 的公开 API 里直接暴露了 LegadoBookSource 的类型，例如
//        - `DebugSettings.verbosity: DebugVerbosity`（public 属性）
//        - `DebugSettings.apply(to logger: DebugLogger)`
//        - `DebugSession.logger: DebugLogger`（public 属性）
//      Swift 不会把「成员类型所属的模块」沿着属性访问链透传给调用方：
//      App 里写 `settings.verbosity` 时，`DebugVerbosity` 这个**名字**在 App 的
//      作用域里并不存在，于是报
//        `cannot find 'DebugVerbosity' in scope`
//      （CI run 37467005822 的 build-ipa job，App/SettingsView.swift:36/37）。
//
//      但这**不是** App 的错：只要 App 用了 `DebugSettings`，就必然会碰到
//      `DebugVerbosity`。所以正确的修法是在提供方把依赖**重新导出**，
//      让「import BookonDebugKit」即可拿到它公开 API 所引用的一切类型。
//
//  为什么用 `@_exported` 而不是让 App 再 import 一次：
//      后者要求每一个用到 `DebugSettings.verbosity` / `DebugLogger` 的文件都
//      记得额外写一行 import，漏一个就编译不过（`LogHistoryView.swift`
//      就是这么漏的）。依赖重新导出把这条约束收口到一处，与 SwiftPM 中
//      「公开 API 引用了某模块的类型 → 该模块应被 re-export」的通行做法一致。
//
//  ⚠️ 本文件必须只有这一行 import，不要放其他代码。
//

@_exported import LegadoBookSource

// reexport_verbosity_probe.swift
//
// 复现并验证 CI run 37467005822 `build-ipa` 的编译错误：
//     App/SettingsView.swift:36:44: error: cannot find 'DebugVerbosity' in scope
//
// 当时 App/SettingsView.swift 只写了 `import BookonDebugKit`，却直接引用
// `DebugVerbosity.normal` —— 而该枚举定义在 LegadoBookSource 模块里。
// Swift 不会把成员类型所属模块沿属性访问链透传，故编译失败。
//
// 本探针的判据：
//   **只 import BookonDebugKit**（刻意不 import LegadoBookSource），
//   仍然能写出 `DebugVerbosity` 这个名字并成功用 `settings.verbosity`。
//   只有当 BookonDebugKit 用 `@_exported import LegadoBookSource` 重新导出时
//   才会 PASS；否则会编译失败（正是我们要防的回归）。
//
// 同时验证 `DebugLogger`（原本同样只在 LegadoBookSource 里）也能透出，
// 因为 DebugSession.logger 是 public 且类型为 DebugLogger。

import Foundation
import BookonDebugKit   // ← 只有这一行（不 import LegadoBookSource）

var pass = 0
var fail = 0
func check(_ ok: Bool, _ what: String) {
    if ok { pass += 1; print("  ✅ \(what)") }
    else  { fail += 1; print("  ❌ \(what)") }
}

let defaults = UserDefaults(suiteName: "com.bookon.reexport.probe")!
defaults.removePersistentDomain(forName: "com.bookon.reexport.probe")

let settings = DebugSettings(defaults: defaults)

// ── 1. DebugVerbosity 这个名字在「只 import BookonDebugKit」时必须可用 ──
//        （这两行就是 SettingsView.swift:36/37 的等价写法）
let normalTag: DebugVerbosity = DebugVerbosity.normal
let errorTag: DebugVerbosity = DebugVerbosity.errorsOnly
check(normalTag == .normal, "DebugVerbosity.normal 可用（无需 import LegadoBookSource）")
check(errorTag == .errorsOnly, "DebugVerbosity.errorsOnly 可用（无需 import LegadoBookSource）")
check(DebugVerbosity.allCases.count == 2, "DebugVerbosity.allCases == 2（普通/仅错误）")

// ── 2. 通过 DebugSettings.verbosity 读写（Picker 绑定的实际路径） ──
check(settings.verbosity == .normal, "DebugSettings.verbosity 默认 .normal")
settings.verbosity = .errorsOnly
check(settings.verbosity == .errorsOnly, "写入 .errorsOnly 后读回一致")
settings.verbosity = .normal

// ── 3. 同一属性可挂到 SwiftUI Picker 的 selection（语义等价检查，不用 SwiftUI） ──
//      Picker 要求 selection 的 tag 类型与绑定类型一致；
//      这里断言 tag 字面量与属性类型是同一类型，等价于编译期约束。
let tags: [DebugVerbosity] = [.normal, .errorsOnly]
check(tags.contains(settings.verbosity), "selection 的 tag 集合包含当前值（Picker 语义）")

// ── 4. DebugLogger 也必须能透出（DebugSession.logger 是 public DebugLogger） ──
let logger = DebugLogger()
logger.verbosity = .errorsOnly
check(logger.verbosity == .errorsOnly, "DebugLogger.verbosity 可写可读（同模块 re-export）")

// ── 5. DebugSettings.apply(to:) 的签名里就有 DebugLogger，必须能调用 ──
settings.apply(to: logger)
check(logger.verbosity == .normal, "apply(to:) 把 settings.verbosity 同步给 logger")

// ── 6. DebugTextLimit 来自 BookonDebugKit 本身，顺带确认未被破坏 ──
check(DebugTextLimit.displayDefault == 30000, "DebugTextLimit.displayDefault == 30000")
check(DebugTextLimit.exportDefault == 5000, "DebugTextLimit.exportDefault == 5000")
check(DebugTextLimit.displayRange == 1000...500000, "displayRange == 1000...500000")
check(DebugTextLimit.exportRange == 0...100000, "exportRange == 0...100000")

print("")
print("PASS=\(pass) FAIL=\(fail)")
if fail > 0 { exit(1) }

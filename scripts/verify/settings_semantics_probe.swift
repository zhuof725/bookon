//
//  settings_semantics_probe.swift
//
//  本地（Linux）探针：用与 DebugSettings 相同的读值语义，验证 6 个 CI 失败用例的期望行为。
//  Linux 无 XCTest/UserDefaults，所以这里用字典模拟存储并逐条打印 PASS/FAIL。
//  真实验收仍以 macOS / iOS CI 的 swift test 为准。
//

import Foundation

#if canImport(Foundation)
let displayDefault = 30000
let displayRange = 1000...500000
let exportDefault = 5000
let exportRange = 0...100000

func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }

/// 与 DebugSettings.readInt 等价的实现。
func readInt(_ store: inout [String: Any], key: String, initialValue: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
    guard let obj = store[key] else {
        let value = clamp(initialValue, range)
        store[key] = value
        return value
    }
    let raw: Int
    if let i = obj as? Int {
        raw = i
    } else if let s = obj as? String, let i = Int(s) {
        raw = i
    } else {
        store[key] = fallback
        return fallback
    }
    let c = clamp(raw, range)
    if c != raw { store[key] = c }
    return c
}

/// 与 DebugSettings.init 等价的实现。
struct Settings {
    var sourceDisplayLimit: Int
    var exportSourceLimit: Int
    init(sourceDisplayLimit: Int = displayDefault,
         exportSourceLimit: Int = exportDefault,
         store: inout [String: Any]) {
        self.sourceDisplayLimit = clamp(sourceDisplayLimit, displayRange)
        self.exportSourceLimit = clamp(exportSourceLimit, exportRange)
        self.sourceDisplayLimit = readInt(&store, key: "sourceDisplayLimit",
                                          initialValue: self.sourceDisplayLimit,
                                          fallback: displayDefault, range: displayRange)
        self.exportSourceLimit = readInt(&store, key: "exportSourceLimit",
                                         initialValue: self.exportSourceLimit,
                                         fallback: exportDefault, range: exportRange)
    }
}

var pass = 0
var fail = 0
func check(_ ok: Bool, _ label: String, _ detail: String = "") {
    if ok { pass += 1; print("PASS  \(label)") }
    else { fail += 1; print("FAIL  \(label)  \(detail)") }
}

// 1. 默认值
do {
    var store: [String: Any] = [:]
    let s = Settings(store: &store)
    check(s.sourceDisplayLimit == displayDefault && s.exportSourceLimit == exportDefault,
          "testDefaultLimits", "got \(s.sourceDisplayLimit)/\(s.exportSourceLimit)")
}

// 2. 上界越界钳位（CI: :410/:411）
do {
    var store: [String: Any] = [:]
    let s = Settings(sourceDisplayLimit: 999_999_999, exportSourceLimit: 999_999_999, store: &store)
    check(s.sourceDisplayLimit == displayRange.upperBound && s.exportSourceLimit == exportRange.upperBound,
          "testClampOverUpperBoundOnInit",
          "got \(s.sourceDisplayLimit)/\(s.exportSourceLimit) want \(displayRange.upperBound)/\(exportRange.upperBound)")
}

// 3. 负数钳位（CI: :418/:419）
do {
    var store: [String: Any] = [:]
    let s = Settings(sourceDisplayLimit: -5, exportSourceLimit: -5, store: &store)
    check(s.sourceDisplayLimit == displayRange.lowerBound && s.exportSourceLimit == exportRange.lowerBound,
          "testClampNegativeOnInit",
          "got \(s.sourceDisplayLimit)/\(s.exportSourceLimit) want \(displayRange.lowerBound)/\(exportRange.lowerBound)")
}

// 4. 跨实例持久化（CI: :428/:429）
do {
    var store: [String: Any] = [:]
    let s1 = Settings(sourceDisplayLimit: 12345, exportSourceLimit: 678, store: &store)
    // save() 等价的显式回写（构造期已写回，这里再写一次以匹配测试流程）
    store["sourceDisplayLimit"] = s1.sourceDisplayLimit
    store["exportSourceLimit"] = s1.exportSourceLimit
    let s2 = Settings(store: &store)
    check(s2.sourceDisplayLimit == 12345 && s2.exportSourceLimit == 678,
          "testLimitsPersistAcrossInstances",
          "got \(s2.sourceDisplayLimit)/\(s2.exportSourceLimit) want 12345/678")
}

// 5. 存储里已是越界值 → 加载时钳位并回写
do {
    var store: [String: Any] = ["sourceDisplayLimit": 99_999_999, "exportSourceLimit": -1000]
    let s = Settings(store: &store)
    check(s.sourceDisplayLimit == displayRange.upperBound && s.exportSourceLimit == exportRange.lowerBound,
          "testOutOfRangeStoredValueIsClampedOnLoad",
          "got \(s.sourceDisplayLimit)/\(s.exportSourceLimit)")
    check((store["sourceDisplayLimit"] as? Int) == displayRange.upperBound
          && (store["exportSourceLimit"] as? Int) == exportRange.lowerBound,
          "testOutOfRangeStoredValueIsClampedOnLoad.writeBack",
          "store=\(store)")
}

// 6. 类型不对 → 回退默认值并回写
do {
    var store: [String: Any] = ["sourceDisplayLimit": "not-a-number"]
    let s = Settings(store: &store)
    check(s.sourceDisplayLimit == displayDefault, "testWrongTypeStoredValueFallsBackToDefault",
          "got \(s.sourceDisplayLimit)")
    check((store["sourceDisplayLimit"] as? Int) == displayDefault,
          "testWrongTypeStoredValueFallsBackToDefault.writeBack", "store=\(store)")
}

// 7. 字符串数字 → 正常读取
do {
    var store: [String: Any] = ["sourceDisplayLimit": "25000"]
    let s = Settings(store: &store)
    check(s.sourceDisplayLimit == 25000, "testStringNumberStoredValueIsRead", "got \(s.sourceDisplayLimit)")
}

// 8. 存储里的值优先于构造参数
do {
    var store: [String: Any] = ["sourceDisplayLimit": 42000]
    let s = Settings(sourceDisplayLimit: 11111, store: &store)
    check(s.sourceDisplayLimit == 42000, "storedBeatsInitArgument", "got \(s.sourceDisplayLimit)")
}

// 9. 构造参数生效且立即写回（无 key 时）
do {
    var store: [String: Any] = [:]
    let s = Settings(sourceDisplayLimit: 200000, exportSourceLimit: 90000, store: &store)
    check(s.sourceDisplayLimit == 200000 && s.exportSourceLimit == 90000,
          "initArgumentPersistsWhenStoreEmpty", "got \(s.sourceDisplayLimit)/\(s.exportSourceLimit)")
    check((store["sourceDisplayLimit"] as? Int) == 200000 && (store["exportSourceLimit"] as? Int) == 90000,
          "initArgumentWrittenBack", "store=\(store)")
}

// 10. 恢复默认（模拟 restoreDefaultTextLimits）
do {
    var store: [String: Any] = [:]
    _ = Settings(sourceDisplayLimit: 200000, exportSourceLimit: 90000, store: &store)
    store["sourceDisplayLimit"] = displayDefault
    store["exportSourceLimit"] = exportDefault
    let s2 = Settings(store: &store)
    check(s2.sourceDisplayLimit == displayDefault && s2.exportSourceLimit == exportDefault,
          "testRestoreDefaultTextLimits", "got \(s2.sourceDisplayLimit)/\(s2.exportSourceLimit)")
}

print("\nPASS=\(pass) FAIL=\(fail)")
exit(fail == 0 ? 0 : 1)
#endif

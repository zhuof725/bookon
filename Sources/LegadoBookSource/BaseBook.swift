//
//  BaseBook.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/BaseBook.kt
//
//  Kotlin 里 BaseBook 是一个 interface : RuleDataInterface，声明公共字段并提供
//  变量存取（putVariable/getCustomVariable 等，依赖 GSON + RuleBigDataHelp）与
//  getKindList()。本步骤只做数据模型，故只移植「字段声明」与纯数据方法 getKindList()。
//
//  TODO(后续步骤): 移植 RuleDataInterface / 变量存取运行时逻辑
//    - putVariable() / getVariable() / putBigVariable() / getBigVariable()
//    - putCustomVariable() / getCustomVariable()
//    - variableMap 的懒加载（依赖 GSON 解析 variable 字段）
//    这些依赖缓存与 JSON 运行时，属于后续步骤。
//

import Foundation

/// 书籍基类协议，声明公共字段。
/// 对应 Kotlin `interface BaseBook : RuleDataInterface`。
public protocol BaseBook {
    var name: String { get set }
    var author: String { get set }
    var bookUrl: String { get set }
    var kind: String? { get set }
    var wordCount: String? { get set }
    var variable: String? { get set }

    // 以下两个字段在 Kotlin 里是 @Ignore（不持久化）的运行时状态。
    var infoHtml: String? { get set }
    var tocHtml: String? { get set }
}

public extension BaseBook {
    /// 对应 Kotlin getKindList()：把 wordCount 与逗号/换行分隔的 kind 合并成列表。
    func getKindList() -> [String] {
        var kindList: [String] = []
        if let wc = wordCount, !wc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kindList.append(wc)
        }
        if let k = kind {
            // 对应 Kotlin splitNotBlank(",", "\n")：按 , 和换行拆分并去空白。
            let parts = k
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            kindList.append(contentsOf: parts)
        }
        return kindList
    }
}

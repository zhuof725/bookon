//
//  RuleValue.swift
//  LegadoBookSource
//
//  对应 Kotlin AnalyzeRule 里到处出现的 `Any?` 动态中间结果类型。
//  Kotlin 在调度过程中 content/result 可能是 String、List<String>、org.jsoup 的
//  Element/Elements、JsoupXpath 的 JXNode、Jayway 读到的 JSON 对象、Rhino 的
//  NativeObject / LinkedTreeMap、null 等。Swift 用本枚举表达这一动态类型。
//
//  Kotlin 类型 → RuleValue 映射（详见 README）：
//   String                          -> .string
//   List<String> / ArrayList<String>-> .stringList
//   org.jsoup Element               -> .element
//   org.jsoup Elements / List<Node> -> .elements
//   JsoupXpath JXNode / List<JXNode>-> .xpathNodes
//   Jayway JSON 读取结果(对象/数组/标量) -> .json
//   Rhino NativeObject / JS 对象     -> .jsObject（键值 map）
//   Gson LinkedTreeMap<*,*>          -> .jsonObject（键值 map，直接按键取值）
//   null                            -> .null
//

import Foundation
import SwiftSoup

/// 规则调度过程中的动态中间值（对应 Kotlin 的 Any?）。
public enum RuleValue {
    case string(String)
    case stringList([String])
    case element(Element)
    case elements([Element])
    case xpathNodes([XPathNode])
    case json(JSONValue)
    /// 一组 JSON 元素（对应 Kotlin `getElements` 在 json 模式下返回的 `List<Any>`，
    /// 元素仍是**结构化 JSON**，可被后续 `@js:` 规则按字段取值，如 `result.chapterId`）。
    case jsonList([JSONValue])
    /// Rhino NativeObject / JS 求值得到的对象（键值访问）。
    case jsObject([String: RuleValue])
    /// Gson LinkedTreeMap：直接按键取值（Kotlin `result[rule]`）。
    case jsonObject([String: RuleValue])
    /// 任意 JS 标量（数字/布尔），其字符串化走 jsStringValue。
    case number(Double)
    case bool(Bool)
    case null

    /// 是否为 null（对应 Kotlin `result == null`）。
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// 对齐 Kotlin `result.toString()` 的字符串化。
    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .stringList(let l): return l.description    // Kotlin List.toString() = [a, b]
        case .element(let e): return (try? e.outerHtml()) ?? ""
        case .elements(let es): return es.map { (try? $0.outerHtml()) ?? "" }.description
        case .xpathNodes(let ns): return ns.map { $0.asString() }.description
        case .json(let j): return j.stringValue
        case .jsonList(let l): return l.map { $0.stringValue }.description
        case .jsObject: return "[object Object]" // Rhino NativeObject.toString()
        case .jsonObject(let m): return String(describing: m)
        case .number(let d):
            // 对齐 Rhino 返回 Java Double 后，Kotlin `result.toString()` 的 Java 格式。
            // inline {{}} 的整数去 .0 由 SourceRule.makeUpRule 的 Locale.ROOT "%.0f" 另行处理。
            return JavaDoubleFormat.string(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    /// 取字符串列表（若本身是列表返回之，否则按换行切分字符串）。
    public var asStringList: [String]? {
        switch self {
        case .stringList(let l): return l
        case .jsonList(let l): return l.map { $0.stringValue }
        case .string(let s): return s.components(separatedBy: "\n")
        default: return nil
        }
    }
}

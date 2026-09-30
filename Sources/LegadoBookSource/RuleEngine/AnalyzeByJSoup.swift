//
//  AnalyzeByJSoup.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/analyzeRule/AnalyzeByJSoup.kt（524 行，逐函数、逐分支对照移植）
//
//  CSS/DOM 后端。Kotlin 用 Jsoup 1.16.2；Swift 用 SwiftSoup（选型理由见 README）。
//  规则切分复用第 2 步的 RuleAnalyzer（不重写）。
//
//  错误策略（对齐前两步）：Kotlin 里会抛异常处 → 抛 RuleEngineError（.invalidSelector/.invalidHTML）；
//  public 方法标 throws；Kotlin 里被吞掉处保持吞掉并写入可选的 RuleEngineDiagnostics（默认关闭）。
//  无 fatalError / try! / 强制解包 / as! / 越界数组访问。
//

import Foundation
import SwiftSoup

public final class AnalyzeByJSoup {

    // 对应 Kotlin companion: private val nullSet = setOf(null)（Swift 用标记删除实现，无需该常量）
    // internal（非 private）以便同模块的扩展文件访问。
    let element: Element
    let diagnostics: RuleEngineDiagnostics?
    var diagnosticsRef: RuleEngineDiagnostics? { diagnostics }

    /// 用任意输入构造（Element / JSON 字符串形式的 HTML / <?xml 文本）。
    /// - Parameter doc: `SwiftSoup.Element` 或可 `String(describing:)` 的 HTML 文本。
    /// - Throws: RuleEngineError.invalidHTML（HTML 解析失败）。
    public init(_ doc: Any, diagnostics: RuleEngineDiagnostics? = nil) throws {
        self.diagnostics = diagnostics
        self.element = try AnalyzeByJSoup.parse(doc)
    }

    /// 对应 Kotlin: private fun parse(doc: Any): Element
    private static func parse(_ doc: Any) throws -> Element {
        if let el = doc as? Element {
            return el
        }
        // Kotlin 还处理 JXNode 入参（来自 XPath 结果）；本移植 XPath 结果为 XPathNode，
        // 若传入 XPathNode 则取其底层 Element 或其 HTML 文本。
        if let node = doc as? XPathNode {
            if let el = node.asElement() {
                return el
            }
            return try parseHTML(node.stringForParse())
        }
        let s = String(describing: doc)
        return try parseHTML(s)
    }

    /// 解析 HTML 文本：`<?xml` 开头走 XML 解析器（对齐 Kotlin runCatching + Parser.xmlParser）。
    private static func parseHTML(_ s: String) throws -> Element {
        // runCatching：xml 解析失败不抛，退回普通 HTML 解析。
        if s.range(of: "<?xml", options: [.caseInsensitive, .anchored]) != nil
            || s.hasPrefix("<?xml") || s.lowercased().hasPrefix("<?xml") {
            if let xml = try? SwiftSoup.parse(s, "", Parser.xmlParser()) {
                return xml
            }
        }
        do {
            return try SwiftSoup.parse(s)
        } catch {
            throw RuleEngineError.invalidHTML(String(s.prefix(120)))
        }
    }

    // MARK: - getElements

    /// 对应 Kotlin: internal fun getElements(rule) = getElements(element, rule)
    /// - Throws: RuleEngineError（选择器无效 / 切分器错误）。
    public func getElements(_ rule: String) throws -> Elements {
        return try getElements(element, rule)
    }

    // MARK: - getString / getString0

    /// 对应 Kotlin: internal fun getString(ruleStr): String?
    public func getString(_ ruleStr: String) throws -> String? {
        if ruleStr.isEmpty { return nil }
        let list = try getStringList(ruleStr)
        if list.isEmpty { return nil }
        if list.count == 1 { return list.first }
        return list.joined(separator: "\n")
    }

    /// 对应 Kotlin: internal fun getString0(ruleStr) = getStringList(...).let { if empty "" else it[0] }
    public func getString0(_ ruleStr: String) throws -> String {
        let list = try getStringList(ruleStr)
        return list.isEmpty ? "" : list[0]
    }

    // MARK: - getStringList

    /// 对应 Kotlin: internal fun getStringList(ruleStr): List<String>
    public func getStringList(_ ruleStr: String) throws -> [String] {
        var textS: [String] = []
        if ruleStr.isEmpty { return textS }

        // 拆分规则
        let sourceRule = SourceRule(ruleStr)

        if sourceRule.elementsRule.isEmpty {
            // Kotlin: textS.add(element.data() ?: "")；SwiftSoup data() 非 throwing。
            textS.append(element.data())
        } else {
            let ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule)
            let ruleStrS = try ruleAnalyzes.splitRule("&&", "||", "%%")

            var results: [[String]] = []
            for ruleStrX in ruleStrS {
                let temp: [String]?
                if sourceRule.isCss {
                    // Kotlin: lastIndexOf('@')，@ 前是选择器，@ 后是结果类型
                    let u = Array(ruleStrX.utf16)
                    let lastIndex = lastIndexOfAt(u)
                    if lastIndex < 0 {
                        // 无 '@'：整体当选择器，结果类型为空 -> getResultLast 走 else(属性) 分支取空属性
                        let sel = ruleStrX
                        temp = try getResultLast(try select(element, sel), "")
                    } else {
                        let selStr = utf16Substring(u, 0, lastIndex)
                        let lastRule = utf16Substring(u, lastIndex + 1, u.count)
                        temp = try getResultLast(try select(element, selStr), lastRule)
                    }
                } else {
                    temp = try getResultList(ruleStrX)
                }

                if let temp = temp, !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzes.elementsType == "||" { break }
                }
            }
            if !results.isEmpty {
                if ruleAnalyzes.elementsType == "%%" {
                    for i in results[0].indices {
                        for temp in results where i < temp.count {
                            textS.append(temp[i])
                        }
                    }
                } else {
                    for temp in results { textS.append(contentsOf: temp) }
                }
            }
        }
        return textS
    }

    // MARK: - select 包装（SwiftSoup select 抛错 -> RuleEngineError.invalidSelector）

    private func select(_ el: Element, _ css: String) throws -> Elements {
        do {
            return try el.select(css)
        } catch {
            diagnostics?.record(source: "AnalyzeByJSoup.select", rule: css, message: "选择器解析失败")
            throw RuleEngineError.invalidSelector(css)
        }
    }

    // MARK: - UTF-16 辅助（对齐 Kotlin 的 lastIndexOf / substring 语义，避免中文/emoji 错位）

    private let atUnit: UInt16 = 0x40  // '@'

    private func lastIndexOfAt(_ u: [UInt16]) -> Int {
        var i = u.count - 1
        while i >= 0 {
            if u[i] == atUnit { return i }
            i -= 1
        }
        return -1
    }

    private func utf16Substring(_ u: [UInt16], _ from: Int, _ to: Int) -> String {
        if from >= to || from < 0 || to > u.count { return "" }
        return String(utf16CodeUnits: Array(u[from..<to]), count: to - from)
    }
}

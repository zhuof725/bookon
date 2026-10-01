//
//  AnalyzeByXPath.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/analyzeRule/AnalyzeByXPath.kt（155 行）
//
//  XPath 后端。底层通过 XPathEvaluator 协议注入，默认 SwiftSoupXPathEvaluator。
//  规则切分复用第 2 步的 RuleAnalyzer。
//
//  错误策略：切分器错误 / XPath 无效 -> 抛 RuleEngineError；public 方法标 throws。
//

import Foundation
import SwiftSoup

public final class AnalyzeByXPath {

    // 求值上下文：一组根元素（对应 Kotlin 的 JXDocument / JXNode）。
    private let evaluator: XPathEvaluator
    private let diagnostics: RuleEngineDiagnostics?

    /// 用任意输入构造（Element / Elements / XPathNode / HTML 文本）。
    /// - Throws: RuleEngineError.invalidHTML（HTML 解析失败）。
    public init(_ doc: Any,
                evaluatorType: XPathEvaluator.Type = SwiftSoupXPathEvaluator.self,
                diagnostics: RuleEngineDiagnostics? = nil) throws {
        self.diagnostics = diagnostics
        let roots = try AnalyzeByXPath.parse(doc)
        self.evaluator = evaluatorType.init(roots: roots)
    }

    /// 对应 Kotlin: private fun parse(doc): Any
    /// （Kotlin 返回单个 JXNode/JXDocument；Swift 用「根元素数组」表达同样的求值上下文。）
    private static func parse(_ doc: Any) throws -> [Element] {
        if let node = doc as? XPathNode {
            if let el = node.asElement() { return [el] }
            return try strToJXDocument(node.stringForParse())
        }
        if let e = doc as? Element {
            return [e]
        }
        if let es = doc as? Elements {
            return es.array()
        }
        return try strToJXDocument(String(describing: doc))
    }

    /// 对应 Kotlin: private fun strToJXDocument(html: String)（末尾补全 + <?xml 走 XML 解析）。
    private static func strToJXDocument(_ html: String) throws -> [Element] {
        var html1 = html
        if html1.hasSuffix("</td>") {
            html1 = "<tr>\(html1)</tr>"
        }
        if html1.hasSuffix("</tr>") || html1.hasSuffix("</tbody>") {
            html1 = "<table>\(html1)</table>"
        }
        let trimmed = html1.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("<?xml") {
            if let xml = try? SwiftSoup.parse(html1, "", Parser.xmlParser()) {
                return [xml]
            }
        }
        do {
            let doc = try SwiftSoup.parse(html1)
            return [doc]
        } catch {
            throw RuleEngineError.invalidHTML(String(html1.prefix(120)))
        }
    }

    /// 对应 Kotlin: private fun getResult(xPath): List<JXNode>?
    private func getResult(_ xPath: String) throws -> [XPathNode] {
        return try evaluator.evaluate(xPath)
    }

    // MARK: - getElements

    /// 对应 Kotlin: internal fun getElements(xPath): List<JXNode>?
    public func getElements(_ xPath: String) throws -> [XPathNode]? {
        if xPath.isEmpty { return nil }

        var jxNodes: [XPathNode] = []
        let ruleAnalyzes = RuleAnalyzer(xPath)
        let rules = try ruleAnalyzes.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            return try getResult(rules[0])
        } else {
            var results: [[XPathNode]] = []
            for rl in rules {
                let temp = try getElements(rl)
                if let temp = temp, !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzes.elementsType == "||" { break }
                }
            }
            if !results.isEmpty {
                if ruleAnalyzes.elementsType == "%%" {
                    for i in results[0].indices {
                        for temp in results where i < temp.count {
                            jxNodes.append(temp[i])
                        }
                    }
                } else {
                    for temp in results { jxNodes.append(contentsOf: temp) }
                }
            }
        }
        return jxNodes
    }

    // MARK: - getStringList

    /// 对应 Kotlin: internal fun getStringList(xPath): List<String>
    public func getStringList(_ xPath: String) throws -> [String] {
        var result: [String] = []
        let ruleAnalyzes = RuleAnalyzer(xPath)
        let rules = try ruleAnalyzes.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            // Kotlin: getResult(xPath)?.map { result.add(it.asString()) }
            // 注意：Kotlin 的 `?.`（安全调用）只处理 null，不捕获异常——如果 getResult
            // 内部抛异常（如 JsoupXpath 解析失败），它会直接向上传播，不会被这里吞掉。
            // 之前误用 `try?` 吞掉了异常，与 Kotlin 真实行为不符，这里改为 `try` 传播。
            let nodes = try self.getResult(xPath)
            for n in nodes { result.append(n.asString()) }
            return result
        } else {
            var results: [[String]] = []
            for rl in rules {
                let temp = try getStringList(rl)
                if !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzes.elementsType == "||" { break }
                }
            }
            if results.count > 0 {
                if ruleAnalyzes.elementsType == "%%" {
                    for i in results[0].indices {
                        for temp in results where i < temp.count {
                            result.append(temp[i])
                        }
                    }
                } else {
                    for temp in results { result.append(contentsOf: temp) }
                }
            }
        }
        return result
    }

    // MARK: - getString

    /// 对应 Kotlin: fun getString(rule): String?
    public func getString(_ rule: String) throws -> String? {
        let ruleAnalyzes = RuleAnalyzer(rule)
        let rules = try ruleAnalyzes.splitRule("&&", "||")
        if rules.count == 1 {
            // Kotlin: getResult(rule)?.let { return TextUtils.join("\n", it) }
            // 注意：`?.let` 只处理 null，不捕获异常；之前误用 `try?` 吞掉异常，
            // 与 Kotlin 真实行为不符，这里改为 `try` 传播（见上面 getStringList 的同类修正）。
            do {
                let nodes = try self.getResult(rule)
                return nodes.map { $0.toStringValue() }.joined(separator: "\n")
            } catch {
                // ⚠️ 与 Kotlin 已知差异的精确对齐（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
                // `getString` 的 Kotlin 原始签名只识别 `&&`/`||` 两种组合符，不识别 `%%`；
                // 若规则里混入字面 `%%`（本不该出现在 XPath 的 getString 调用场景），
                // 残留文本会被当作一段无法识别的路径文本交给 XPath 引擎。真实 JsoupXpath
                // 的 ANTLR 解析器对此有自己的容错路径，最终返回空字符串 `""`，而不是
                // 抛异常。本项目的解析器会在这类"路径文本含无法识别字符"的情况下抛
                // `invalidXPath`；这里只在"确实是 %% 导致的遗留文本"这一具体场景下，
                // 把错误降级为空字符串，对齐真实库的观测结果，不扩大到其它真正的语法错误
                // （如 string()/normalize-space() 等——那些场景不含 %%，不会走这个分支）。
                if rule.contains("%%"), case RuleEngineError.invalidXPath = error {
                    diagnostics?.record(source: "AnalyzeByXPath.getString", rule: rule,
                                        message: "规则含 %% 导致 XPath 解析残留文本，对齐真实库返回空串")
                    return ""
                }
                throw error
            }
        } else {
            var textList: [String] = []
            for rl in rules {
                let temp = try getString(rl)
                if let temp = temp, !temp.isEmpty {
                    textList.append(temp)
                    if ruleAnalyzes.elementsType == "||" { break }
                }
            }
            return textList.joined(separator: "\n")
        }
    }
}

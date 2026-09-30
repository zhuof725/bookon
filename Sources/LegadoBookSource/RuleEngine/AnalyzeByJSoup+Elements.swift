//
//  AnalyzeByJSoup+Elements.swift
//  LegadoBookSource
//
//  AnalyzeByJSoup 的元素选择与结果提取（对照 Kotlin 同名私有方法）。
//

import Foundation
import SwiftSoup

extension AnalyzeByJSoup {

    /// 对应 Kotlin: private fun getElements(temp: Element?, rule: String): Elements
    func getElements(_ temp: Element?, _ rule: String) throws -> Elements {
        guard let temp = temp, !rule.isEmpty else { return Elements() }

        let elements = Elements()

        let sourceRule = SourceRule(rule)
        let ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule)
        let ruleStrS = try ruleAnalyzes.splitRule("&&", "||", "%%")

        var elementsList: [Elements] = []
        if sourceRule.isCss {
            for ruleStr in ruleStrS {
                let tempS = try selectThrowing(temp, ruleStr)
                elementsList.append(tempS)
                if tempS.size() > 0 && ruleAnalyzes.elementsType == "||" { break }
            }
        } else {
            for ruleStr in ruleStrS {
                let rsRule = RuleAnalyzer(ruleStr)
                try rsRule.trim()  // 修剪当前规则之前的"@"或者空白符
                let rs = try rsRule.splitRule("@")

                let el: Elements
                if rs.count > 1 {
                    let acc = Elements()
                    acc.add(temp)
                    for rl in rs {
                        let es = Elements()
                        for et in acc.array() {
                            es.addElements(try getElements(et, rl))
                        }
                        acc.clearAll()
                        acc.addElements(es)
                    }
                    el = acc
                } else {
                    el = try ElementsSingle().getElementsSingle(temp, ruleStr, host: self)
                }

                elementsList.append(el)
                if el.size() > 0 && ruleAnalyzes.elementsType == "||" { break }
            }
        }

        if !elementsList.isEmpty {
            if ruleAnalyzes.elementsType == "%%" {
                let first = elementsList[0]
                for i in 0..<first.size() {
                    for es in elementsList where i < es.size() {
                        if let e = es.getOrNil(i) { elements.add(e) }
                    }
                }
            } else {
                for es in elementsList {
                    elements.addElements(es)
                }
            }
        }
        return elements
    }

    /// 对应 Kotlin: private fun getResultList(ruleStr): ArrayList<String>?
    func getResultList(_ ruleStr: String) throws -> [String]? {
        if ruleStr.isEmpty { return nil }

        var elements = Elements()
        elements.add(element)

        let rule = RuleAnalyzer(ruleStr)   // 创建解析
        try rule.trim()                    // 修剪前置赘余符号
        let rules = try rule.splitRule("@")  // 切割成列表

        let last = rules.count - 1
        if last < 0 { return nil }
        for i in 0..<last {
            let es = Elements()
            for elt in elements.array() {
                es.addElements(try ElementsSingle().getElementsSingle(elt, rules[i], host: self))
            }
            elements.clearAll()
            elements = es
        }
        if elements.isEmpty() { return nil }
        return try getResultLast(elements, rules[last])
    }

    /// 对应 Kotlin: private fun getResultLast(elements, lastRule): ArrayList<String>
    func getResultLast(_ elements: Elements, _ lastRule: String) throws -> [String] {
        var textS: [String] = []
        switch lastRule {
        case "text":
            for element in elements.array() {
                let text = (try? element.text()) ?? ""
                if !text.isEmpty { textS.append(text) }
            }
        case "textNodes":
            for element in elements.array() {
                var tn: [String] = []
                let contentEs = element.textNodes()
                for item in contentEs {
                    let text = item.text().trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r").union(.whitespacesAndNewlines))
                    if !text.isEmpty { tn.append(text) }
                }
                if !tn.isEmpty { textS.append(tn.joined(separator: "\n")) }
            }
        case "ownText":
            for element in elements.array() {
                let text = element.ownText()  // SwiftSoup: 非 throwing
                if !text.isEmpty { textS.append(text) }
            }
        case "html":
            // 先移除 script/style，再取 outerHtml
            _ = try? elements.select("script").remove()
            _ = try? elements.select("style").remove()
            let html = (try? elements.outerHtml()) ?? ""
            if !html.isEmpty { textS.append(html) }
        case "all":
            let html = (try? elements.outerHtml()) ?? ""
            textS.append(html)
        default:
            for element in elements.array() {
                let url = (try? element.attr(lastRule)) ?? ""
                // Kotlin: if (url.isBlank() || textS.contains(url)) continue
                if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                if textS.contains(url) { continue }
                textS.append(url)
            }
        }
        return textS
    }

    /// select 包装（内部使用；抛错 -> RuleEngineError.invalidSelector，记诊断）。
    func selectThrowing(_ el: Element, _ css: String) throws -> Elements {
        do {
            return try el.select(css)
        } catch {
            diagnosticsRef?.record(source: "AnalyzeByJSoup.select", rule: css, message: "选择器解析失败")
            throw RuleEngineError.invalidSelector(css)
        }
    }
}

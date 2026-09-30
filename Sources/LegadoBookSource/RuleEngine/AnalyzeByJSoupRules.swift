//
//  AnalyzeByJSoupRules.swift
//  LegadoBookSource
//
//  AnalyzeByJSoup 的规则语法处理：SourceRule（@CSS: 前缀）与 ElementsSingle
//  （findIndexSet 索引/排除语法、区间/步长/反转）。对照 Kotlin 逐分支移植。
//
//  ⚠️ 索引解析在 UTF-16 code unit 上进行（对齐 Kotlin String 下标；含中文/emoji 不错位）。
//

import Foundation
import SwiftSoup

extension AnalyzeByJSoup {

    /// 对应 Kotlin: internal inner class SourceRule(ruleStr)
    struct SourceRule {
        let isCss: Bool
        let elementsRule: String

        init(_ ruleStr: String) {
            // Kotlin: startsWith("@CSS:", true) 大小写不敏感
            if ruleStr.count >= 5,
               ruleStr.prefix(5).lowercased() == "@css:" {
                isCss = true
                elementsRule = String(ruleStr.dropFirst(5))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r").union(.whitespacesAndNewlines))
            } else {
                isCss = false
                elementsRule = ruleStr
            }
        }
    }

    /// 对应 Kotlin: data class ElementsSingle
    final class ElementsSingle {
        // 索引区间的内部表示（对齐 Kotlin Triple<Int?, Int?, Int>）。
        enum IndexItem {
            case single(Int)
            case range(start: Int?, end: Int?, step: Int)
        }

        var split: Character = "."
        var beforeRule: String = ""
        var indexDefault: [Int] = []
        var indexes: [IndexItem] = []

        /// 对应 Kotlin: fun getElementsSingle(temp: Element, rule: String): Elements
        func getElementsSingle(_ temp: Element, _ rule: String, host: AnalyzeByJSoup) throws -> Elements {
            try findIndexSet(rule)  // 执行索引列表处理器

            // 获取所有元素
            var elements: Elements
            if beforeRule.isEmpty {
                elements = temp.children()  // 允许索引直接作为根元素
            } else {
                let rules = beforeRule.components(separatedBy: ".")
                let head = rules.isEmpty ? "" : rules[0]
                switch head {
                case "children":
                    elements = temp.children()
                case "class":
                    elements = rules.count > 1 ? try temp.getElementsByClass(rules[1]) : Elements()
                case "tag":
                    elements = rules.count > 1 ? try temp.getElementsByTag(rules[1]) : Elements()
                case "id":
                    if rules.count > 1 {
                        elements = try Collector.collect(Evaluator.Id(rules[1]), temp)
                    } else {
                        elements = Elements()
                    }
                case "text":
                    elements = rules.count > 1 ? try temp.getElementsContainingOwnText(rules[1]) : Elements()
                default:
                    do {
                        elements = try temp.select(beforeRule)
                    } catch {
                        host.diagnosticsRef?.record(source: "AnalyzeByJSoup.ElementsSingle",
                                                    rule: beforeRule, message: "选择器解析失败")
                        throw RuleEngineError.invalidSelector(beforeRule)
                    }
                }
            }

            let len = elements.size()
            // Kotlin: (indexDefault.size - 1).takeIf { it != -1 } ?: (indexes.size - 1)
            let lastIndexes = (indexDefault.count - 1) != -1 ? (indexDefault.count - 1) : (indexes.count - 1)
            var indexSet: [Int] = []          // 保持插入顺序 + 去重
            var seen = Set<Int>()
            func addIndex(_ v: Int) { if seen.insert(v).inserted { indexSet.append(v) } }

            if indexes.isEmpty {
                // 非 [] 式索引，逆向遍历还原顺序
                if lastIndexes >= 0 {
                    for ix in stride(from: lastIndexes, through: 0, by: -1) {
                        let it = indexDefault[ix]
                        if it >= 0 && it < len { addIndex(it) }
                        else if it < 0 && len >= -it { addIndex(it + len) }
                    }
                }
            } else {
                if lastIndexes >= 0 {
                    for ix in stride(from: lastIndexes, through: 0, by: -1) {
                        switch indexes[ix] {
                        case .range(let startX, let endX, let stepX):
                            var start = startX ?? 0
                            if start < 0 { start += len }
                            var end = endX ?? (len - 1)
                            if end < 0 { end += len }

                            if (start < 0 && end < 0) || (start >= len && end >= len) {
                                continue  // 同侧越界，无效
                            }
                            if start >= len { start = len - 1 } else if start < 0 { start = 0 }
                            if end >= len { end = len - 1 } else if end < 0 { end = 0 }

                            if start == end || stepX >= len {
                                addIndex(start)
                                continue
                            }
                            let step = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1)  // 最小正数间隔为 1
                            if end > start {
                                var v = start
                                while v <= end { addIndex(v); v += step }
                            } else {
                                // start downTo end step step（step 为正，向下走）
                                var v = start
                                while v >= end { addIndex(v); v -= step }
                            }
                        case .single(let it):
                            if it >= 0 && it < len { addIndex(it) }
                            else if it < 0 && len >= -it { addIndex(it + len) }
                        }
                    }
                }
            }

            // 根据索引集合筛选
            if split == "!" {
                // 排除：标记删除
                let keep = elements.array().enumerated().filter { !seen.contains($0.offset) }.map { $0.element }
                let es = Elements()
                try es.add(contentsOf: keep)
                elements = es
            } else if split == "." {
                let es = Elements()
                for pcInt in indexSet {
                    if pcInt >= 0 && pcInt < elements.size(), let e = try? elements.get(pcInt) {
                        try es.add(e)
                    }
                }
                elements = es
            }
            return elements
        }

        /// 对应 Kotlin: private fun findIndexSet(rule: String)
        /// 在 UTF-16 code unit 上处理（对齐 Kotlin String 下标）。
        func findIndexSet(_ rule: String) throws {
            let trimmed = rule.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r").union(.whitespacesAndNewlines))
            let rus = Array(trimmed.utf16)
            var len = rus.count
            var curInt: Int?
            var curMinus = false
            var curList: [Int?] = []
            var l = ""   // 暂存数字字符串

            let head = (rus.last == u("]"))  // 是否为常规索引写法 [ ... ]

            if head {
                len -= 1  // 跳过尾部 ']'
                // Kotlin: while (len-- >= 0) —— 先判断 len>=0 再自减
                while true {
                    let cond = (len >= 0); let idx = len; len -= 1
                    if !cond { break }
                    var rl = rus[idx]
                    if rl == u(" ") { continue }

                    if isDigit(rl) { l = ch(rl) + l }
                    else if rl == u("-") { curMinus = true }
                    else {
                        curInt = l.isEmpty ? nil : (curMinus ? -(Int(l) ?? 0) : (Int(l) ?? 0))
                        if rl == u(":") {
                            curList.append(curInt)
                        } else {
                            if curList.isEmpty {
                                if curInt == nil { break }  // 是 jsoup 选择器而非索引列表
                                indexes.append(.single(curInt ?? 0))
                            } else {
                                let step = (curList.count == 2 ? (curList.first ?? nil) : nil) ?? 1
                                indexes.append(.range(start: curInt, end: curList.last ?? nil, step: step))
                                curList.removeAll()
                            }
                            if rl == u("!") {
                                split = "!"
                                repeat {
                                    len -= 1
                                    if len < 0 { break }
                                    rl = rus[len]
                                } while len > 0 && rl == u(" ")
                            }
                            if rl == u("[") {
                                beforeRule = utf16Sub(rus, 0, max(len, 0))
                                return
                            }
                            if rl != u(",") { break }
                        }
                        l = ""
                        curMinus = false
                    }
                }
            } else {
                // 阅读原本写法，逆向遍历
                while true {
                    let cond = (len >= 0); let idx = len; len -= 1
                    if !cond { break }
                    let rl = rus[idx]
                    if rl == u(" ") { continue }

                    if isDigit(rl) { l = ch(rl) + l }
                    else if rl == u("-") { curMinus = true }
                    else {
                        if rl == u("!") || rl == u(".") || rl == u(":") {
                            indexDefault.append(curMinus ? -(Int(l) ?? 0) : (Int(l) ?? 0))
                            if rl != u(":") {
                                split = Character(UnicodeScalar(rl) ?? " ")
                                beforeRule = utf16Sub(rus, 0, idx)
                                return
                            }
                        } else { break }
                        l = ""
                        curMinus = false
                    }
                }
            }

            split = " "
            beforeRule = trimmed
        }

        // MARK: UTF-16 小工具
        private func u(_ c: Character) -> UInt16 { Array(String(c).utf16)[0] }
        private func isDigit(_ x: UInt16) -> Bool { x >= 0x30 && x <= 0x39 }
        private func ch(_ x: UInt16) -> String { String(utf16CodeUnits: [x], count: 1) }
        private func utf16Sub(_ u: [UInt16], _ from: Int, _ to: Int) -> String {
            if from >= to || from < 0 || to > u.count { return "" }
            return String(utf16CodeUnits: Array(u[from..<to]), count: to - from)
        }
    }
}

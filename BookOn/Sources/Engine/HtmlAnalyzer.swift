import Foundation
import SwiftSoup

/// 移植自 Legado AnalyzeByJSoup：支持 class.x.0 / tag.a / id.x / text.x / children、[索引]、!排除、@ 链式、
/// 末段 text / textNodes / ownText / html / all / 属性名，以及 && || %% 组合。
final class HtmlAnalyzer {
    private let root: Element

    init(_ doc: Any) {
        if let e = doc as? Element { root = e }
        else if let s = doc as? String {
            if s.lowercased().hasPrefix("<?xml"), let d = try? SwiftSoup.parse(s, "", Parser.xmlParser()) { root = d }
            else { root = (try? SwiftSoup.parse(s)) ?? Document("") }
        } else { root = (try? SwiftSoup.parse("\(doc)")) ?? Document("") }
    }

    // MARK: public

    func getString(_ rule: String) -> String? {
        if rule.isEmpty { return nil }
        let list = getStringList(rule)
        if list.isEmpty { return nil }
        return list.count == 1 ? list[0] : list.joined(separator: "\n")
    }

    func getString0(_ rule: String) -> String { getStringList(rule).first ?? "" }

    func getStringList(_ ruleStr: String) -> [String] {
        if ruleStr.isEmpty { return [] }
        let src = SourceRule(ruleStr)
        if src.elementsRule.isEmpty { return [(try? root.data()) ?? ""] }
        var ra = RuleAnalyzer(src.elementsRule)
        let parts = ra.splitRule(["&&", "||", "%%"])
        var results: [[String]] = []
        for p in parts {
            var temp: [String]?
            if src.isCss {
                if let at = p.lastIndex(of: "@") {
                    let sel = String(p[..<at]), last = String(p[p.index(after: at)...])
                    if let els = try? root.select(sel) { temp = resultLast(Array(els), last) }
                } else if let els = try? root.select(p) { temp = resultLast(Array(els), "text") }
            } else {
                temp = resultList(p)
            }
            if let t = temp, !t.isEmpty {
                results.append(t)
                if ra.elementsType == "||" { break }
            }
        }
        return merge(results, ra.elementsType)
    }

    func getElements(_ rule: String) -> [Element] { elements(root, rule) }

    // MARK: internals

    private func merge<T>(_ lists: [[T]], _ type: String) -> [T] {
        guard !lists.isEmpty else { return [] }
        if type == "%%" {
            var out: [T] = []
            for i in 0..<lists[0].count { for l in lists where i < l.count { out.append(l[i]) } }
            return out
        }
        return lists.flatMap { $0 }
    }

    private func elements(_ temp: Element?, _ rule: String) -> [Element] {
        guard let temp = temp, !rule.isEmpty else { return [] }
        let src = SourceRule(rule)
        var ra = RuleAnalyzer(src.elementsRule)
        let parts = ra.splitRule(["&&", "||", "%%"])
        var lists: [[Element]] = []
        for p in parts {
            var el: [Element]
            if src.isCss {
                el = (try? temp.select(p)).map(Array.init) ?? []
            } else {
                let trimmed = RuleAnalyzer.trimLeading(p)
                var inner = RuleAnalyzer(trimmed)
                let rs = inner.splitRule(["@"])
                if rs.count > 1 {
                    el = [temp]
                    for r in rs {
                        var next: [Element] = []
                        for e in el { next += elements(e, r) }
                        el = next
                    }
                } else {
                    el = ElementsSingle().get(temp, trimmed)
                }
            }
            lists.append(el)
            if !el.isEmpty && ra.elementsType == "||" { break }
        }
        return merge(lists, ra.elementsType)
    }

    private func resultList(_ ruleStr: String) -> [String]? {
        if ruleStr.isEmpty { return nil }
        var els: [Element] = [root]
        var ra = RuleAnalyzer(RuleAnalyzer.trimLeading(ruleStr))
        let rules = ra.splitRule(["@"])
        for i in 0..<(rules.count - 1) {
            var next: [Element] = []
            for e in els { next += ElementsSingle().get(e, rules[i]) }
            els = next
        }
        return els.isEmpty ? nil : resultLast(els, rules[rules.count - 1])
    }

    private func resultLast(_ els: [Element], _ last: String) -> [String] {
        var out: [String] = []
        switch last {
        case "text":
            for e in els { if let t = try? e.text(), !t.isEmpty { out.append(t) } }
        case "textNodes":
            for e in els {
                let tn = e.textNodes().map { $0.text().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !tn.isEmpty { out.append(tn.joined(separator: "\n")) }
            }
        case "ownText":
            for e in els { let t = e.ownText(); if !t.isEmpty { out.append(t) } }
        case "html":
            for e in els {
                try? e.select("script").remove()
                try? e.select("style").remove()
            }
            let h = els.compactMap { try? $0.outerHtml() }.joined(separator: "\n")
            if !h.isEmpty { out.append(h) }
        case "all":
            out.append(els.compactMap { try? $0.outerHtml() }.joined(separator: "\n"))
        default:
            for e in els {
                guard let v = try? e.attr(last), !v.trimmingCharacters(in: .whitespaces).isEmpty, !out.contains(v) else { continue }
                out.append(v)
            }
        }
        return out
    }

    // MARK: SourceRule (@CSS: 前缀)

    private struct SourceRule {
        var isCss = false
        var elementsRule: String
        init(_ rule: String) {
            if rule.lowercased().hasPrefix("@css:") {
                isCss = true
                elementsRule = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else {
                elementsRule = rule
            }
        }
    }

    // MARK: ElementsSingle：单段规则 + 索引

    private struct ElementsSingle {
        enum Idx { case single(Int); case range(Int?, Int?, Int) }
        var split: Character = "."
        var beforeRule = ""
        var indexDefault: [Int] = []
        var indexes: [Idx] = []

        mutating func get(_ temp: Element, _ rule: String) -> [Element] {
            findIndexSet(rule)
            var els: [Element]
            if beforeRule.isEmpty {
                els = Array(temp.children())
            } else {
                let rules = beforeRule.components(separatedBy: ".")
                let arg = rules.count > 1 ? rules[1...].joined(separator: ".") : ""
                switch rules[0] {
                case "children": els = Array(temp.children())
                case "class": els = (try? temp.getElementsByClass(arg)).map(Array.init) ?? []
                case "tag": els = (try? temp.getElementsByTag(arg)).map(Array.init) ?? []
                case "id": els = (try? temp.getElementById(arg)).flatMap { $0 }.map { [$0] } ?? []
                case "text": els = (try? temp.getElementsContainingOwnText(arg)).map(Array.init) ?? []
                default: els = (try? temp.select(beforeRule)).map(Array.init) ?? []
                }
            }
            let len = els.count
            var set: [Int] = []
            func add(_ i: Int) { if !set.contains(i) { set.append(i) } }
            if indexes.isEmpty {
                for it in indexDefault.reversed() {
                    if it >= 0 && it < len { add(it) } else if it < 0 && len >= -it { add(it + len) }
                }
            } else {
                for ix in indexes.reversed() {
                    switch ix {
                    case .single(let it):
                        if it >= 0 && it < len { add(it) } else if it < 0 && len >= -it { add(it + len) }
                    case .range(let s0, let e0, let stepX):
                        var start = s0 ?? 0; if start < 0 { start += len }
                        var end = e0 ?? (len - 1); if end < 0 { end += len }
                        if (start < 0 && end < 0) || (start >= len && end >= len) { continue }
                        start = min(max(start, 0), len - 1); end = min(max(end, 0), len - 1)
                        if start == end || stepX >= len { add(start); continue }
                        let step = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1)
                        if end > start { var i = start; while i <= end { add(i); i += step } }
                        else { var i = start; while i >= end { add(i); i -= step } }
                    }
                }
            }
            if split == "!" {
                let ex = Set(set)
                return els.enumerated().filter { !ex.contains($0.offset) }.map { $0.element }
            } else if split == "." {
                return set.compactMap { $0 < len ? els[$0] : nil }
            }
            return els
        }

        private mutating func findIndexSet(_ rule: String) {
            let rus = Array(rule.trimmingCharacters(in: .whitespaces))
            guard !rus.isEmpty else { beforeRule = ""; split = " "; return }
            var len = rus.count
            var curMinus = false
            var curList: [Int?] = []
            var l = ""
            if rus.last == "]" {
                len -= 1
                var pos = len - 1
                while pos >= 0 {
                    var rl = rus[pos]
                    if rl == " " { pos -= 1; continue }
                    if rl.isNumber { l = String(rl) + l }
                    else if rl == "-" { curMinus = true }
                    else {
                        let curInt: Int? = l.isEmpty ? nil : (curMinus ? -Int(l)! : Int(l)!)
                        if rl == ":" { curList.append(curInt) }
                        else {
                            if curList.isEmpty {
                                guard let c = curInt else { break }
                                indexes.append(.single(c))
                            } else {
                                indexes.append(.range(curInt, curList.last!, curList.count == 2 ? (curList.first! ?? 1) : 1))
                                curList.removeAll()
                            }
                            if rl == "!" {
                                split = "!"
                                repeat { pos -= 1; rl = rus[pos] } while pos > 0 && rl == " "
                            }
                            if rl == "[" { beforeRule = String(rus[0..<pos]); return }
                            if rl != "," { break }
                        }
                        l = ""; curMinus = false
                    }
                    pos -= 1
                }
                indexes.removeAll()
            } else {
                var pos = len - 1
                while pos >= 0 {
                    let rl = rus[pos]
                    if rl == " " { pos -= 1; continue }
                    if rl.isNumber { l = String(rl) + l }
                    else if rl == "-" { curMinus = true }
                    else {
                        if rl == "!" || rl == "." || rl == ":" {
                            guard let v = Int(l) else { break }
                            indexDefault.append(curMinus ? -v : v)
                            if rl != ":" { split = rl; beforeRule = String(rus[0..<pos]); return }
                        } else { break }
                        l = ""; curMinus = false
                    }
                    pos -= 1
                }
                indexDefault.removeAll()
            }
            split = " "
            beforeRule = String(rus)
        }
    }
}

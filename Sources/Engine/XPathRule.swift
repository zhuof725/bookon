import Foundation
import Kanna
import SwiftSoup

/// Legado XPath 规则：必须以 @XPath: 或 // 开头（教程「语法说明 - XPath」）。
/// 兼容 JsoupXpath 的扩展函数：/text()、/html()、/allText()、/textNodes()、/@attr。
enum XPathRule {
    static func isXPath(_ rule: String) -> Bool {
        let t = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("@xpath:") { return true }
        // 与原版一致：以 `/` 开头就是 XPath（`/text()`、`/@value` 是相对当前节点的路径）。
        return t.hasPrefix("/")
    }

    /// 单个 `/` 开头：相对当前节点的 XPath（JsoupXpath 的 JXDocument 把节点当成文档根）。
    static func isRelative(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasPrefix("//")
    }

    static func strip(_ rule: String) -> String {
        let t = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.lowercased().hasPrefix("@xpath:") ? String(t.dropFirst(7)) : t
    }

    /// 把当前对象转成可供 XPath 解析的 HTML
    static func html(of obj: Any) -> String {
        var s: String
        if let e = obj as? Element { s = (try? e.outerHtml()) ?? "" }
        else if let str = obj as? String { s = str }
        else { s = AnalyzeRule.asString(obj) }
        let head = s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4).lowercased()
        // 表格片段脱离 <table> 会被 HTML 解析器丢弃
        if head.hasPrefix("<tr") || head.hasPrefix("<td") || head.hasPrefix("<th") || head.hasPrefix("<tb") {
            s = "<table>" + s + "</table>"
        }
        return s
    }

    private enum Output { case node, text, html }

    private static func split(_ raw: String) -> (String, Output) {
        var p = strip(raw)
        for (suffix, out) in [("/html()", Output.html), ("/allText()", .text), ("/textNodes()", .text), ("/ownText()", .text)] {
            if p.hasSuffix(suffix) { p = String(p.dropLast(suffix.count)); return (p, out) }
        }
        // 相对路径 ./xxx 视为在整个片段内查找
        if p.hasPrefix("./") { p = "/" + p.dropFirst() }
        return (p, .node)
    }

    private static func query(_ obj: Any, _ path: String) -> XPathObject? {
        guard let doc = try? HTML(html: html(of: obj), encoding: .utf8) else { return nil }
        return doc.xpath(path)
    }

    /// 相对路径求值：以当前节点为根，交给 Kanna（libxml2 XPath 1.0）执行。
    /// 旧实现手写把 `/tag[n]`、`[@class='x']` 转成 CSS，覆盖不了 `[last()]`、`contains()`、
    /// 多谓词、属性轴等写法。这里把节点序列化成带唯一标记的片段，再拼成
    /// `//*[@data-legado-root='…']` + 原路径求值。
    /// JsoupXpath 对「当前节点」有两种常见写法：`/@attr`、`/span[1]` 把当前节点当根（取它的属性/子节点），
    /// 而片段只有一个元素时（`<option value="v1">一</option>` + `/option[1]/text()`）又把该元素
    /// 当成结果集里的一项。先按「节点即根」求值，取不到再把节点包一层容器当根重试。
    private static func relativeValues(_ obj: Any, _ path: String, output: Output) -> [String] {
        guard let root = fragmentRoot(obj) else { return [] }
        guard var outer = try? root.outerHtml(),
              let gt = outer.firstIndex(of: ">") else { return [] }
        let marker = "r\(abs(path.hashValue))"
        outer.insert(contentsOf: " data-legado-root=\"\(marker)\"", at: gt)
        let tag = root.tagName().lowercased()
        let container = parentTag(for: tag)
        // ① 节点自己带标记：`/@attr`、`/子元素` 这类写法。
        let direct = container.map { "<\($0)>" + outer + "</\($0)>" } ?? outer
        let values = evaluate(html: direct, marker: marker, path: path, output: output)
        if !values.isEmpty { return values }
        // ② 标记放在容器上：路径第一步就是该节点本身（`/option[1]`）。
        let wrapperTag = container ?? "div"
        guard let plain = try? root.outerHtml() else { return values }
        let wrapped = "<\(wrapperTag) data-legado-root=\"\(marker)\">" + plain + "</\(wrapperTag)>"
        return evaluate(html: wrapped, marker: marker, path: path, output: output)
    }

    /// 片段必须放进合法父元素里，libxml2 才不会把它丢掉（`<option>` 必须在 `<select>` 内等）。
    private static func parentTag(for tag: String) -> String? {
        switch tag {
        case "tr", "td", "th", "tbody", "thead", "tfoot": return "table"
        case "option": return "select"
        case "li": return "ul"
        default: return nil
        }
    }

    private static func evaluate(html: String, marker: String, path: String, output: Output) -> [String] {
        guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
        let result = doc.xpath("//*[@data-legado-root='\(marker)']" + path)
        let isAttribute = path.contains("/@")
        switch result {
        case .NodeSet(let nodes):
            var values: [String] = []
            for i in 0..<nodes.count {
                let node = nodes[i]
                let raw: String? = (output == .html && !isAttribute) ? node.innerHTML : node.text
                if let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { values.append(v) }
            }
            return values
        case .String(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case .Number(let value): return ["\(value)"]
        case .Bool(let value): return [value ? "true" : "false"]
        default: return []
        }
    }

    /// 当前对象对应的节点：元素直接返回；字符串片段（如 `<option value="…">`）包一层 div 后取首个元素。
    /// 内容字符串在进入规则前已被解析成 Document，相对路径要作用在文档的实际内容节点上，
    /// 否则 `/@value` 会去读 `<html>` 的属性（耽美小说目录）。
    private static func fragmentRoot(_ obj: Any) -> Element? {
        if let e = obj as? Element {
            if let doc = e as? Document {
                if let body = doc.body(), body.children().size() == 1, let only = body.children().first() {
                    return only
                }
                return doc.body() ?? doc
            }
            return e
        }
        guard let s = obj as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let head = t.prefix(9).lowercased()
        if head.hasPrefix("<!doctype") || head.hasPrefix("<html") {
            return (try? SwiftSoup.parse(t))?.body()
        }
        guard let doc = try? SwiftSoup.parse("<div id=\"__legado_fragment__\">" + t + "</div>"),
              let holder = try? doc.getElementById("__legado_fragment__") else { return nil }
        return holder.children().first()
    }

    /// 列表规则：返回每个匹配节点的 HTML（属性/文本节点返回文本）
    static func elements(_ obj: Any, _ rule: String) -> [Any] {
        let (path, output) = split(rule)
        if isRelative(path) {
            return relativeValues(obj, path, output: output)
        }
        guard let res = query(obj, path) else { return [] }
        switch res {
        case .String(let value): return value.isEmpty ? [] : [value]
        case .Number(let value): return [value]
        case .Bool(let value): return [value]
        case .NodeSet(let nodes):
            var out: [Any] = []
            for i in 0..<nodes.count {
                let n = nodes[i]
                if let h = n.toHTML, h.hasPrefix("<") { out.append(h) }
                else if let t = n.text { out.append(t) }
            }
            if out.isEmpty {
                let s = fallbackString(obj, path)
                return s.isEmpty ? [] : s.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
            return out
        default: return []
        }
    }

    private static func fallbackString(_ obj: Any, _ path: String) -> String {
        guard let root = try? SwiftSoup.parse(html(of: obj)) else { return "" }
        var selector = path
        var attr: String?
        if let slash = selector.range(of: "/@", options: .backwards) {
            attr = String(selector[slash.upperBound...])
            selector = String(selector[..<slash.lowerBound])
        } else if selector.hasSuffix("/text()") {
            selector = String(selector.dropLast(7)); attr = "text"
        }
        selector = selector.replacingOccurrences(of: "//", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        let classPattern = RegexLog.compile("(div|ul|li|a|p)\\[@class=['\\\"]([^'\\\"]+)['\\\"]\\]")
        if let re = classPattern, let m = re.firstMatch(in: selector, range: NSRange(location: 0, length: (selector as NSString).length)) {
            let tag = (selector as NSString).substring(with: m.range(at: 1))
            let cls = (selector as NSString).substring(with: m.range(at: 2))
            selector = selector.replacingCharacters(in: Range(m.range, in: selector)!, with: "\(tag).\(cls.replacingOccurrences(of: " ", with: "."))")
        }
        if let re = RegexLog.compile("\\[contains\\(text\\(\\),\\s*['\"]([^'\"]+)['\"]\\)\\]") {
            let ns = selector as NSString
            for m in re.matches(in: selector, range: NSRange(location: 0, length: ns.length)).reversed() {
                let text = ns.substring(with: m.range(at: 1))
                selector = (selector as NSString).replacingCharacters(in: m.range, with: ":contains(\(text))")
            }
        }
        selector = selector.trimmingCharacters(in: .whitespaces)
        let elements = (try? root.select(selector).array()) ?? []
        return elements.compactMap { e in
            if attr == "text" { return try? e.text() }
            if let attr { return try? e.attr(attr) }
            return try? e.text()
        }.joined(separator: "\n")
    }

    /// 文本规则：多个结果用换行连接
    static func string(_ obj: Any, _ rule: String) -> String {
        let (path, output) = split(rule)
        if isRelative(path) {
            return relativeValues(obj, path, output: output).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let res = query(obj, path) else { return fallbackString(obj, path) }
        switch res {
        case .none: return fallbackString(obj, path)
        case .String(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .Number(let value): return "\(value)"
        case .Bool(let value): return value ? "true" : "false"
        case .NodeSet(let nodes):
            var list: [String] = []
            for i in 0..<nodes.count {
                let n = nodes[i]
                let v: String? = output == .html ? n.innerHTML : n.text
                if let s = v?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { list.append(s) }
            }
            return list.isEmpty ? fallbackString(obj, path) : list.joined(separator: "\n")
        default: return ""
        }
    }
}

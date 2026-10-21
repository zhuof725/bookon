import Foundation
import JavaScriptCore
import SwiftSoup

/// JavaScriptCore wrapper for the Jsoup Element/Elements objects exposed by Legado.
@objc protocol JSNodeExports: JSExport {
    func attr(_ name: String) -> String
    func text() -> String
    func ownText() -> String
    func html() -> String
    func outerHtml() -> String
    func select(_ selector: String) -> JSNodeListBridge
    func children() -> JSNodeListBridge
    func toArray() -> [Any]
    func toString() -> String
    // jQuery 风格的常用方法（书源脚本里普遍写 `J.select('.note').eq(0).text()`）。
    func eq(_ index: Int) -> JSNodeBridge?
    func first() -> JSNodeBridge?
    func last() -> JSNodeBridge?
    func each(_ handler: @convention(block) (JSNodeBridge, Int) -> Void)
    func hasClass(_ name: String) -> Bool
    func parent() -> JSNodeBridge?
    func next() -> JSNodeBridge?
    func prev() -> JSNodeBridge?
    // DOM 变更（书源正文规则常用：`box.select("script").remove()`、`.addClass(...)`）
    func remove()
    func empty()
    func append(_ html: String)
    func prepend(_ html: String)
    func before(_ html: String)
    func after(_ html: String)
    func addClass(_ name: String)
    func removeClass(_ name: String)
}

@objc protocol JSNodeListExports: JSExport {
    var length: Int { get }
    func size() -> Int
    func get(_ index: Int) -> JSNodeBridge?
    func toArray() -> [Any]
    func select(_ selector: String) -> JSNodeListBridge
    func attr(_ name: String) -> String
    func text() -> String
    func ownText() -> String
    func html() -> String
    func outerHtml() -> String
    func toString() -> String
    // jQuery 风格的常用方法。
    func eq(_ index: Int) -> JSNodeBridge?
    func first() -> JSNodeBridge?
    func last() -> JSNodeBridge?
    func each(_ handler: @convention(block) (JSNodeBridge, Int) -> Void)
    func hasClass(_ name: String) -> Bool
    func parent() -> JSNodeListBridge
    func next() -> JSNodeBridge?
    func prev() -> JSNodeBridge?
    // DOM 变更：对集合里每个元素依次执行
    func remove()
    func empty()
    func append(_ html: String)
    func prepend(_ html: String)
    func before(_ html: String)
    func after(_ html: String)
    func addClass(_ name: String)
    func removeClass(_ name: String)
}

@objc final class JSNodeBridge: NSObject, JSNodeExports {
    let element: Element
    init(_ element: Element) { self.element = element; super.init() }

    /// Restore native nodes at the JS/AnalyzeRule boundary, including node arrays.
    static func unwrap(_ value: Any) -> Any {
        if let node = value as? JSNodeBridge { return node.element }
        if let list = value as? JSNodeListBridge { return list.elements }
        if let array = value as? [Any] { return array.map { unwrap($0) } }
        if let object = value as? [String: Any] {
            return object.mapValues { unwrap($0) }
        }
        return value
    }

    func attr(_ name: String) -> String { (try? element.attr(name)) ?? "" }
    func text() -> String { (try? element.text()) ?? "" }
    func ownText() -> String { element.ownText() }
    func html() -> String { (try? element.html()) ?? "" }
    func outerHtml() -> String { (try? element.outerHtml()) ?? "" }
    func select(_ selector: String) -> JSNodeListBridge {
        JSNodeListBridge((try? element.select(selector).array()) ?? [])
    }
    func children() -> JSNodeListBridge { JSNodeListBridge(element.children().array()) }
    func toArray() -> [Any] { [self] }
    func toString() -> String { outerHtml() }

    func eq(_ index: Int) -> JSNodeBridge? { nil }
    func first() -> JSNodeBridge? { self }
    func last() -> JSNodeBridge? { self }
    func each(_ handler: @convention(block) (JSNodeBridge, Int) -> Void) { handler(self, 0) }
    func hasClass(_ name: String) -> Bool { (try? element.hasClass(name)) ?? false }
    func parent() -> JSNodeBridge? {
        guard let p = element.parent() else { return nil }
        return JSNodeBridge(p)
    }
    func next() -> JSNodeBridge? {
        guard let s = try? element.nextElementSibling() else { return nil }
        return JSNodeBridge(s)
    }
    func prev() -> JSNodeBridge? {
        guard let s = try? element.previousElementSibling() else { return nil }
        return JSNodeBridge(s)
    }
    func remove() { try? element.remove() }
    func empty() { try? element.empty() }
    func append(_ html: String) { try? element.append(html) }
    func prepend(_ html: String) { try? element.prepend(html) }
    func before(_ html: String) { try? element.before(html) }
    func after(_ html: String) { try? element.after(html) }
    func addClass(_ name: String) { try? element.addClass(name) }
    func removeClass(_ name: String) { try? element.removeClass(name) }
}

@objc final class JSNodeListBridge: NSObject, JSNodeListExports {
    let elements: [Element]
    init(_ elements: [Element]) { self.elements = elements; super.init() }

    var length: Int { elements.count }
    func size() -> Int { elements.count }
    func get(_ index: Int) -> JSNodeBridge? {
        guard elements.indices.contains(index) else { return nil }
        return JSNodeBridge(elements[index])
    }
    func toArray() -> [Any] { elements.map(JSNodeBridge.init) }
    /// Jsoup Elements.select：在每个元素内部再查一次（群小说 searchUrl 依赖
    /// `Jsoup.parse(html).select('form').select('[name=_token]')`）。
    func select(_ selector: String) -> JSNodeListBridge {
        var found: [Element] = []
        for element in elements {
            found.append(contentsOf: (try? element.select(selector).array()) ?? [])
        }
        return JSNodeListBridge(found)
    }
    private var firstElement: Element? { elements.first }
    func attr(_ name: String) -> String { firstElement.map { (try? $0.attr(name)) ?? "" } ?? "" }
    func text() -> String { firstElement.map { (try? $0.text()) ?? "" } ?? "" }
    func ownText() -> String { firstElement?.ownText() ?? "" }
    func html() -> String { firstElement.map { (try? $0.html()) ?? "" } ?? "" }
    func outerHtml() -> String { firstElement.map { (try? $0.outerHtml()) ?? "" } ?? "" }
    func toString() -> String { elements.map { (try? $0.outerHtml()) ?? "" }.joined() }

    func eq(_ index: Int) -> JSNodeBridge? { get(index) }
    func first() -> JSNodeBridge? { get(0) }
    func last() -> JSNodeBridge? { get(elements.count - 1) }
    func each(_ handler: @convention(block) (JSNodeBridge, Int) -> Void) {
        for (index, element) in elements.enumerated() { handler(JSNodeBridge(element), index) }
    }
    func hasClass(_ name: String) -> Bool { firstElement.map { (try? $0.hasClass(name)) ?? false } ?? false }
    func parent() -> JSNodeListBridge {
        var found: [Element] = []
        for element in elements {
            if let p = element.parent() { found.append(p) }
        }
        return JSNodeListBridge(found)
    }
    func next() -> JSNodeBridge? {
        guard let s = try? elements.first?.nextElementSibling() else { return nil }
        return JSNodeBridge(s)
    }
    func prev() -> JSNodeBridge? {
        guard let s = try? elements.first?.previousElementSibling() else { return nil }
        return JSNodeBridge(s)
    }
    func remove() { for element in elements { try? element.remove() } }
    func empty() { for element in elements { try? element.empty() } }
    func append(_ html: String) { for element in elements { try? element.append(html) } }
    func prepend(_ html: String) { for element in elements { try? element.prepend(html) } }
    func before(_ html: String) { for element in elements { try? element.before(html) } }
    func after(_ html: String) { for element in elements { try? element.after(html) } }
    func addClass(_ name: String) { for element in elements { try? element.addClass(name) } }
    func removeClass(_ name: String) { for element in elements { try? element.removeClass(name) } }
}

/// 元素列表在规则 JS 里的形态：既能当数组用（select/toArray/下标/length），
/// 又能当字符串用（match/split/replace）。
/// 书源里两种写法都有：`result.select('a').toArray()` 与 `result.match(/\\d+/)`。
struct JSNodeListWithText {
    let items: [Any]
    let text: String
}

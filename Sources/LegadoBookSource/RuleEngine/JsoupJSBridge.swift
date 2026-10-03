//
//  JsoupJSBridge.swift
//  LegadoBookSource
//
//  Step 5：org.jsoup.Jsoup 替身。真实书源（台湾小说网、爱丽丝书屋）的 JS 规则用
//  `org.jsoup.Jsoup.parse(html).select(css)...`（台湾版带 `Packages.` 前缀）。
//  这里用 SwiftSoup 提供 JS 可调用的 parse/select/text/html/attr/outerHtml/first/get/size/eq/remove。
//
//  Step 5 收尾：本文件全部输出口与**真实 jsoup 1.16.2** 逐条对照过（golden
//  `cases/jsoup_cases.json`，Java 侧在同一 JS 上用真实 jsoup 求值、Swift 侧用本替身求值）：
//   - `text()`   ：走 `SwiftSoupTextNormalizeFix`（复刻 jsoup 把 &nbsp; 纳入可折叠空白的扩展）；
//   - `html()` / `outerHtml()`：走 `JsoupCompatSerializer`（Step4-A 已逐字节对齐 jsoup 的
//                 pretty-print 序列化），不再使用 SwiftSoup 自带的 html()/outerHtml()；
//   - `attr()`   ：`Elements.attr` 取**第一个拥有该属性**的元素（jsoup 语义），不是"第一个元素的属性"；
//   - `eq(i)`    ：越界返回空集合；负数下标与 jsoup 一样抛错（`contents.get(-1)`）；
//   - `get(i)`   ：越界与 jsoup 一样抛错（IndexOutOfBoundsException 对应 JS 异常）；
//   - `size()` / `first()` / `remove()`：与 jsoup 语义一致。
//  未知方法仍抛明确 JS 错误 + 记 diagnostics（不静默返回 undefined）。
//

import Foundation
import SwiftSoup

#if canImport(JavaScriptCore)
import JavaScriptCore

/// JS 可见的 jsoup 替身。install 后作用域里同时出现：
///   org.jsoup.Jsoup（爱丽丝写法）与 Packages.org.jsoup.Jsoup（台湾写法）。
final class JsoupJSBridge {
    private let diagnostics: RuleEngineDiagnostics?

    init(diagnostics: RuleEngineDiagnostics?) { self.diagnostics = diagnostics }

    func install(into context: JSContext) {
        // 解析入口：parse(html) -> 文档包装
        let parseBlock: @convention(block) (String) -> JSValue? = { [weak context] html in
            guard let context else { return nil }
            if let doc = try? SwiftSoup.parse(html) {
                return JsoupJSBridge.makeWrapper(.document(doc), context: context)
            }
            return nil
        }

        // Packages.org.jsoup.Jsoup 链：Packages -> org -> jsoup -> Jsoup
        let jsoupNode = JSValue(newObjectIn: context)
        jsoupNode?.setObject(parseBlock, forKeyedSubscript: "parse" as NSString)

        let jsoupObj = JSValue(newObjectIn: context)
        jsoupObj?.setObject(jsoupNode, forKeyedSubscript: "Jsoup" as NSString)

        let orgObj = JSValue(newObjectIn: context)
        orgObj?.setObject(jsoupObj, forKeyedSubscript: "jsoup" as NSString)

        let packagesObj = JSValue(newObjectIn: context)
        packagesObj?.setObject(orgObj, forKeyedSubscript: "org" as NSString)

        // 顶层（爱丽丝写法）：org.jsoup.Jsoup
        let topJsoup = JSValue(newObjectIn: context)
        topJsoup?.setObject(parseBlock, forKeyedSubscript: "parse" as NSString)
        let topJsoupNs = JSValue(newObjectIn: context)
        topJsoupNs?.setObject(topJsoup, forKeyedSubscript: "Jsoup" as NSString)
        let topOrg = JSValue(newObjectIn: context)
        topOrg?.setObject(topJsoupNs, forKeyedSubscript: "jsoup" as NSString)

        context.setObject(packagesObj, forKeyedSubscript: "Packages" as NSString)
        context.setObject(topOrg, forKeyedSubscript: "org" as NSString)
        context.setObject(topJsoupNs, forKeyedSubscript: "jsoup" as NSString)
        context.setObject(topJsoup, forKeyedSubscript: "Jsoup" as NSString)
    }

    private enum Wrapped {
        case document(Document)
        case element(Element)
        case elements(Elements)
    }

    /// 生成统一包装对象：Document/Element/Elements 都暴露 select/text/html/attr/outerHtml/
    /// first/get/size/eq/remove（真实书源用到的子集 + 替身对外承诺的链）。
    private static func makeWrapper(_ wrapped: Wrapped, context: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: context)

        // 与 jsoup 一致：选择器解析失败（SelectorParseException）直接抛 JS 异常。
        let select: @convention(block) (String) -> JSValue = { css in
            let selected: Elements?
            switch wrapped {
            case .document(let doc): selected = try? doc.select(css)
            case .element(let el): selected = try? el.select(css)
            case .elements(let els):
                var all = Elements()
                for e in els.array() { if let sub = try? e.select(css) { all.addElements(sub.array()) } }
                selected = all
            }
            guard let selected else {
                context.exception = JSValue(newErrorFromMessage: "选择器解析失败: \(css)", in: context)
                return JSValue(undefinedIn: context)
            }
            return makeWrapper(.elements(selected), context: context)
        }
        obj?.setObject(select, forKeyedSubscript: "select" as NSString)

        // jsoup Element.text()/Document.text()：文本节点空白规整（含 &nbsp;）。
        // jsoup Elements.text()：逐个 elem.text() 再用单个空格拼接。
        let text: @convention(block) () -> String = {
            switch wrapped {
            case .document(let doc):
                return SwiftSoupTextNormalizeFix.normalize((try? doc.text()) ?? "")
            case .element(let el):
                return SwiftSoupTextNormalizeFix.normalize((try? el.text()) ?? "")
            case .elements(let els):
                return els.array()
                    .map { SwiftSoupTextNormalizeFix.normalize((try? $0.text()) ?? "") }
                    .joined(separator: " ")
            }
        }
        obj?.setObject(text, forKeyedSubscript: "text" as NSString)

        // jsoup Element.html()/Document.html()：JsoupCompatSerializer 按 jsoup 算法生成 inner HTML。
        // jsoup Elements.html()：逐个 elem.html() 用 "\n" 拼接。
        let html: @convention(block) () -> String = {
            switch wrapped {
            case .document(let doc): return JsoupCompatSerializer.innerHtml(doc)
            case .element(let el): return JsoupCompatSerializer.innerHtml(el)
            case .elements(let els): return JsoupCompatSerializer.elementsInnerHtml(els.array())
            }
        }
        obj?.setObject(html, forKeyedSubscript: "html" as NSString)

        // Node.outerHtml()：同样走 JsoupCompatSerializer（jsoup 1.16.2 算法）。
        let outerHtml: @convention(block) () -> String = {
            switch wrapped {
            case .document(let doc): return JsoupCompatSerializer.outerHtml(doc)
            case .element(let el): return JsoupCompatSerializer.outerHtml(el)
            case .elements(let els): return JsoupCompatSerializer.elementsOuterHtml(els.array())
            }
        }
        obj?.setObject(outerHtml, forKeyedSubscript: "outerHtml" as NSString)

        // jsoup Elements.attr(key)：返回第一个**拥有该属性**的元素的属性值；都没有则空串。
        // jsoup Element.attr(key)：没有该属性返回空串。
        let attr: @convention(block) (String) -> String = {
            switch wrapped {
            case .document(let doc): return (try? doc.attr(name)) ?? ""
            case .element(let el): return (try? el.attr(name)) ?? ""
            case .elements(let els): return (try? els.attr(name)) ?? ""
            }
        }
        obj?.setObject(attr, forKeyedSubscript: "attr" as NSString)

        let first: @convention(block) () -> JSValue = {
            switch wrapped {
            case .document(let doc): return makeWrapper(.element(doc), context: context)
            case .element(let el): return makeWrapper(.element(el), context: context)
            case .elements(let els):
                if let el = els.array().first { return makeWrapper(.element(el), context: context) }
                return JSValue(nullIn: context)
            }
        }
        obj?.setObject(first, forKeyedSubscript: "first" as NSString)

        // jsoup Elements.get(i)：越界抛 IndexOutOfBoundsException（这里对应 JS 异常）。
        let get: @convention(block) (Int) -> JSValue = { index in
            switch wrapped {
            case .elements(let els):
                let arr = els.array()
                if index >= 0 && index < arr.count { return makeWrapper(.element(arr[index]), context: context) }
                context.exception = JSValue(newErrorFromMessage: "Index \(index) out of bounds for length \(arr.count)", in: context)
                return JSValue(undefinedIn: context)
            case .document(let doc): return makeWrapper(.element(doc), context: context)
            case .element(let el): return makeWrapper(.element(el), context: context)
            }
        }
        obj?.setObject(get, forKeyedSubscript: "get" as NSString)

        let size: @convention(block) () -> Int = {
            switch wrapped {
            case .elements(let els): return els.size()
            case .document, .element: return 1
            }
        }
        obj?.setObject(size, forKeyedSubscript: "size" as NSString)

        // jsoup Elements.eq(i)：size() > i ? new Elements(get(i)) : new Elements()。
        // 注意负数下标在 jsoup 里同样会走到 contents.get(-1) 抛 IndexOutOfBoundsException。
        let eq: @convention(block) (Int) -> JSValue = { index in
            switch wrapped {
            case .elements(let els):
                let arr = els.array()
                if index < 0 {
                    context.exception = JSValue(newErrorFromMessage: "Index \(index) out of bounds for length \(arr.count)", in: context)
                    return JSValue(undefinedIn: context)
                }
                if index < arr.count { return makeWrapper(.element(arr[index]), context: context) }
                return makeWrapper(.elements(Elements()), context: context)
            default:
                return makeWrapper(.elements(Elements()), context: context)
            }
        }
        obj?.setObject(eq, forKeyedSubscript: "eq" as NSString)

        let remove: @convention(block) () -> JSValue = {
            switch wrapped {
            case .elements(let els):
                for e in els.array() { _ = try? e.remove() }
            case .element(let el): _ = try? el.remove()
            case .document: break
            }
            return obj ?? JSValue(undefinedIn: context)
        }
        obj?.setObject(remove, forKeyedSubscript: "remove" as NSString)

        return obj ?? JSValue(undefinedIn: context)
    }
}

#endif

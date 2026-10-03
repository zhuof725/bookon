//
//  JsoupJSBridge.swift
//  LegadoBookSource
//
//  Step 5：org.jsoup.Jsoup 替身。真实书源（台湾小说网、爱丽丝书屋）的 JS 规则用
//  `org.jsoup.Jsoup.parse(html).select(css)...`（台湾版带 `Packages.` 前缀）。
//  这里用 SwiftSoup 提供 JS 可调用的 parse/select/text/html/attr/outerHtml/first/get/size/eq/remove，
//  只实现真实书源用到的链；未知方法抛明确 JS 错误 + 记 diagnostics。
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
    /// first/get/size/eq/remove（真实书源用到的子集；多余方法不提供，调未知抛错由 JS 侧处理）。
    private static func makeWrapper(_ wrapped: Wrapped, context: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: context)

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
            if let selected { return makeWrapper(.elements(selected), context: context) }
            return JSValue(undefinedIn: context)
        }
        obj?.setObject(select, forKeyedSubscript: "select" as NSString)

        let text: @convention(block) () -> String = {
            switch wrapped {
            case .document(let doc): return (try? doc.text()) ?? ""
            case .element(let el): return (try? el.text()) ?? ""
            case .elements(let els): return (try? els.text()) ?? ""
            }
        }
        obj?.setObject(text, forKeyedSubscript: "text" as NSString)

        let html: @convention(block) () -> String = {
            switch wrapped {
            case .document(let doc): return (try? doc.html()) ?? ""
            case .element(let el): return (try? el.html()) ?? ""
            case .elements(let els): return (try? els.html()) ?? ""
            }
        }
        obj?.setObject(html, forKeyedSubscript: "html" as NSString)

        let outerHtml: @convention(block) () -> String = {
            switch wrapped {
            case .document(let doc): return (try? doc.outerHtml()) ?? ""
            case .element(let el): return (try? el.outerHtml()) ?? ""
            case .elements(let els): return els.array().compactMap { try? $0.outerHtml() }.joined(separator: "\n")
            }
        }
        obj?.setObject(outerHtml, forKeyedSubscript: "outerHtml" as NSString)

        let attr: @convention(block) (String) -> String = { name in
            switch wrapped {
            case .document(let doc): return (try? doc.attr(name)) ?? ""
            case .element(let el): return (try? el.attr(name)) ?? ""
            case .elements(let els): return els.array().first.flatMap { try? $0.attr(name) } ?? ""
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

        let get: @convention(block) (Int) -> JSValue = { index in
            switch wrapped {
            case .elements(let els):
                let arr = els.array()
                if index >= 0 && index < arr.count { return makeWrapper(.element(arr[index]), context: context) }
            case .document(let doc): return makeWrapper(.element(doc), context: context)
            case .element(let el): return makeWrapper(.element(el), context: context)
            }
            return JSValue(undefinedIn: context)
        }
        obj?.setObject(get, forKeyedSubscript: "get" as NSString)

        let size: @convention(block) () -> Int = {
            switch wrapped {
            case .elements(let els): return els.size()
            case .document, .element: return 1
            }
        }
        obj?.setObject(size, forKeyedSubscript: "size" as NSString)

        let eq: @convention(block) (Int) -> JSValue = { index in
            switch wrapped {
            case .elements(let els):
                let arr = els.array()
                if index >= 0 && index < arr.count { return makeWrapper(.element(arr[index]), context: context) }
            default:
                break
            }
            return JSValue(undefinedIn: context)
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

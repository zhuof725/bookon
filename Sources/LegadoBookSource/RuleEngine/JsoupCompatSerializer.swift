//
//  JsoupCompatSerializer.swift
//  LegadoBookSource
//
//  Step4-A：彻底重写 HTML 序列化，替代原先的字符串级后处理（SwiftSoupVoidElementFix /
//  SwiftSoupBrIndentFix）。本文件从零遍历 SwiftSoup 解析出的 DOM 树（Node/Element/
//  TextNode/Comment/DataNode/DocumentType），按真实 jsoup 1.16.2 的算法重新生成字符串，
//  不调用 SwiftSoup 自带的 `outerHtml()`/`html()`。
//
//  复刻来源（已逐一对照 jsoup 1.16.2 官方源码确认，而非凭记忆）：
//  - org.jsoup.nodes.Node：outerHtml() / indent() / NodeTraversor 深度计算
//  - org.jsoup.nodes.Element：outerHtmlHead() / outerHtmlTail() / shouldIndent() /
//    isFormatAsBlock() / isInlineable()
//  - org.jsoup.nodes.TextNode：outerHtmlHead()（含 "<br> 后文本换行" 特判）
//  - org.jsoup.nodes.Comment / DataNode / DocumentType：outerHtmlHead()
//  - org.jsoup.nodes.Entities：escape()（base 模式转义规则，含 nbsp、非 BMP 字符处理）
//  - org.jsoup.nodes.Attribute / Attributes：html()（布尔属性折叠、属性值转义）
//  - org.jsoup.parser.Tag：各标签分类清单（block/inline/empty/formatAsInline/
//    preserveWhitespace）
//  - org.jsoup.internal.StringUtil：padding() / isActuallyWhitespace() /
//    appendNormalisedWhitespace()
//
//  OutputSettings 固定为 jsoup 默认值：prettyPrint=true, indentAmount=1, outline=false,
//  charset=UTF-8, escapeMode=base, syntax=html —— 这是本项目唯一需要支持的组合
//  （legado 书源规则引擎不会修改这些设置）。
//

import Foundation
import SwiftSoup

/// 按 jsoup 1.16.2 真实算法重新序列化 SwiftSoup DOM 节点为 HTML 字符串。
enum JsoupCompatSerializer {

    // MARK: - Tag 分类表（原样抄自 jsoup 1.16.2 Tag.java 的静态初始化清单）

    /// block 标签：默认 isBlock=true, formatAsBlock=true。
    static let blockTagNames: Set<String> = [
        "html", "head", "body", "frameset", "script", "noscript", "style", "meta", "link", "title", "frame",
        "noframes", "section", "nav", "aside", "hgroup", "header", "footer", "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "pre", "div", "blockquote", "hr", "address", "figure", "figcaption", "form", "fieldset", "ins",
        "del", "dl", "dt", "dd", "li", "table", "caption", "thead", "tfoot", "tbody", "colgroup", "col", "tr", "th",
        "td", "video", "audio", "canvas", "details", "menu", "plaintext", "template", "article", "main",
        "svg", "math", "center",
        "dir", "applet", "marquee", "listing"
    ]

    /// inline 标签：isBlock=false, formatAsBlock=false。
    static let inlineTagNames: Set<String> = [
        "object", "base", "font", "tt", "i", "b", "u", "big", "small", "em", "strong", "dfn", "code", "samp", "kbd",
        "var", "cite", "abbr", "time", "acronym", "mark", "ruby", "rt", "rp", "rtc", "a", "img", "br", "wbr", "map", "q",
        "sub", "sup", "bdo", "iframe", "embed", "span", "input", "select", "textarea", "label", "button", "optgroup",
        "option", "legend", "datalist", "keygen", "output", "progress", "meter", "area", "param", "source", "track",
        "summary", "command", "device", "basefont", "bgsound", "menuitem",
        "data", "bdi", "s", "strike", "nobr",
        "rb", "text", "mi", "mo", "msup", "mn", "mtext"
    ]

    /// 空（void）标签：isEmpty=true（isSelfClosing 也为 true）。
    static let emptyTagNames: Set<String> = [
        "meta", "link", "base", "frame", "img", "br", "wbr", "embed", "hr", "input", "keygen", "col", "command",
        "device", "area", "basefont", "bgsound", "menuitem", "param", "source", "track"
    ]

    /// formatAsInline：覆盖块标签的 formatAsBlock，强制设为 false（如 <p>/<li> 内容按内联排版）。
    static let formatAsInlineTagNames: Set<String> = [
        "title", "a", "p", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "address", "li", "th", "td", "script", "style",
        "ins", "del", "s"
    ]

    /// preserveWhitespace：pre/plaintext/title/textarea（script 不在此列，因为 script 走 DataNode，本身总是保留空白）。
    static let preserveWhitespaceTagNames: Set<String> = [
        "pre", "plaintext", "title", "textarea"
    ]

    /// jsoup Attribute.isBooleanAttribute() 的清单。
    static let booleanAttributeNames: Set<String> = [
        "allowfullscreen", "async", "autofocus", "checked", "compact", "declare", "default", "defer", "disabled",
        "formnovalidate", "hidden", "inert", "ismap", "itemscope", "multiple", "muted", "nohref", "noresize",
        "noshade", "novalidate", "nowrap", "open", "readonly", "required", "reversed", "seamless", "selected",
        "sortable", "truespeed", "typemustmatch"
    ]

    // MARK: - Tag 属性查询（给定标签名，返回 jsoup Tag 的各项布尔属性）

    struct TagInfo {
        let isBlock: Bool
        let formatAsBlock: Bool
        let isEmpty: Bool
        let preserveWhitespace: Bool

        var isSelfClosing: Bool { isEmpty }
        var isInline: Bool { !isBlock }
    }

    /// 等价于 jsoup `Tag.valueOf(name)`：已知标签按清单取属性；未知标签默认
    /// isBlock=false（jsoup `Tag.valueOf` 对未注册的新建 tag 设置 `isBlock=false`，
    /// 其余字段保持 Tag 构造函数默认值：formatAsBlock=true, empty=false,
    /// preserveWhitespace=false）。
    static func tagInfo(for rawName: String) -> TagInfo {
        let name = rawName.lowercased()
        if blockTagNames.contains(name) {
            var formatAsBlock = true
            if formatAsInlineTagNames.contains(name) { formatAsBlock = false }
            let isEmpty = emptyTagNames.contains(name)
            let preserveWhitespace = preserveWhitespaceTagNames.contains(name)
            return TagInfo(isBlock: true, formatAsBlock: formatAsBlock, isEmpty: isEmpty, preserveWhitespace: preserveWhitespace)
        }
        if inlineTagNames.contains(name) {
            let isEmpty = emptyTagNames.contains(name)
            let preserveWhitespace = preserveWhitespaceTagNames.contains(name)
            // formatAsBlock 对 inline 标签默认就是 false（Tag 初始化时 isBlock=false 同步 formatAsBlock=false）。
            return TagInfo(isBlock: false, formatAsBlock: false, isEmpty: isEmpty, preserveWhitespace: preserveWhitespace)
        }
        // 未知标签：Tag.valueOf 新建时 isBlock=false；formatAsBlock/empty/preserveWhitespace
        // 保持 Tag 私有构造函数里的默认值（formatAsBlock=true, empty=false, preserveWhitespace=false）。
        // 注：jsoup 源码里这是比较少见的边界情形，真实 HTML 解析时绝大多数标签都是已知标签。
        return TagInfo(isBlock: false, formatAsBlock: true, isEmpty: false, preserveWhitespace: false)
    }

    // MARK: - StringUtil 等价函数

    /// jsoup StringUtil.padding(width, 30)：indentAmount 固定为 1，所以 width == depth。
    static func padding(_ width: Int) -> String {
        let w = max(0, min(width, 30))
        return String(repeating: " ", count: w)
    }

    /// jsoup StringUtil.isActuallyWhitespace：普通空白 + U+00A0 (nbsp)。
    static func isActuallyWhitespace(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x20, 0x09, 0x0A, 0x0C, 0x0D, 0xA0: return true
        default: return false
        }
    }

    /// jsoup StringUtil.isWhitespace：仅标准 HTML 空白（不含 nbsp）。
    static func isWhitespace(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x20, 0x09, 0x0A, 0x0C, 0x0D: return true
        default: return false
        }
    }

    /// jsoup StringUtil.isInvisibleChar：零宽空格 U+200B、软连字符 U+00AD。
    static func isInvisibleChar(_ scalar: UInt32) -> Bool {
        return scalar == 0x200B || scalar == 0x00AD
    }

    /// jsoup StringUtil.isBlank：空或仅含标准空白（isWhitespace，不含 nbsp —— 与 TextNode.isBlank 一致）。
    static func isBlank(_ s: String) -> Bool {
        if s.isEmpty { return true }
        for scalar in s.unicodeScalars where !isWhitespace(scalar.value) {
            return false
        }
        return true
    }

    /// jsoup StringUtil.appendNormalisedWhitespace(sb, string, stripLeading)。
    static func appendNormalisedWhitespace(_ accum: inout String, _ string: String, stripLeading: Bool) {
        var lastWasWhite = false
        var reachedNonWhite = false
        for scalar in string.unicodeScalars {
            let v = scalar.value
            if isActuallyWhitespace(v) {
                if (stripLeading && !reachedNonWhite) || lastWasWhite { continue }
                accum.append(" ")
                lastWasWhite = true
            } else if !isInvisibleChar(v) {
                accum.unicodeScalars.append(scalar)
                lastWasWhite = false
                reachedNonWhite = true
            }
        }
    }

    static func normaliseWhitespace(_ string: String) -> String {
        var out = ""
        appendNormalisedWhitespace(&out, string, stripLeading: false)
        return out
    }

    // MARK: - Entities.escape（base 模式；escapeMode=base, syntax=html, charset=UTF-8）

    /// 复刻 jsoup Entities.escape(accum, string, out, inAttribute, normaliseWhite, stripLeadingWhite, trimTrailing)
    /// 的 base 模式分支。本项目固定 charset=UTF-8（CoreCharset.utf → canEncode 恒为 true，
    /// 除了低/高代理项，但代码点遍历已经是按 Unicode scalar 迭代，不会拆开代理对，故不需要
    /// 代理对判断分支），escapeMode=base，syntax=html。
    static func escape(
        _ string: String,
        inAttribute: Bool,
        normaliseWhite: Bool,
        stripLeadingWhite: Bool,
        trimTrailing: Bool
    ) -> String {
        var accum = ""
        accum.reserveCapacity(string.count)
        var lastWasWhite = false
        var reachedNonWhite = false
        var skipped = false

        for scalar in string.unicodeScalars {
            let codePoint = scalar.value

            if normaliseWhite {
                if isWhitespace(codePoint) {
                    if stripLeadingWhite && !reachedNonWhite { continue }
                    if lastWasWhite { continue }
                    if trimTrailing {
                        skipped = true
                        continue
                    }
                    accum.append(" ")
                    lastWasWhite = true
                    continue
                } else {
                    lastWasWhite = false
                    reachedNonWhite = true
                    if skipped {
                        accum.append(" ")
                        skipped = false
                    }
                }
            }

            // BMP 范围（< 0x10000）：逐字符特判；非 BMP（emoji、代理对表示的字符）：UTF-8 可编码，原样输出。
            if codePoint < 0x10000 {
                switch codePoint {
                case UInt32(UnicodeScalar("&").value):
                    accum.append("&amp;")
                case 0xA0:
                    // escapeMode != xhtml（本项目固定 base）→ &nbsp;
                    accum.append("&nbsp;")
                case UInt32(UnicodeScalar("<").value):
                    // inAttribute 且非 xhtml/xml 语法：不转义；否则转义。
                    if !inAttribute {
                        accum.append("&lt;")
                    } else {
                        accum.unicodeScalars.append(scalar)
                    }
                case UInt32(UnicodeScalar(">").value):
                    if !inAttribute {
                        accum.append("&gt;")
                    } else {
                        accum.unicodeScalars.append(scalar)
                    }
                case UInt32(UnicodeScalar("\"").value):
                    if inAttribute {
                        accum.append("&quot;")
                    } else {
                        accum.unicodeScalars.append(scalar)
                    }
                case 0x9, 0xA, 0xD:
                    accum.unicodeScalars.append(scalar)
                default:
                    // c < 0x20：控制字符需要数字实体转义；否则 UTF-8 可编码，原样输出
                    // （canEncode(utf, c) 恒为 true，对应 jsoup CoreCharset.utf 分支）。
                    if codePoint < 0x20 {
                        accum.append("&#x")
                        accum.append(String(codePoint, radix: 16))
                        accum.append(";")
                    } else {
                        accum.unicodeScalars.append(scalar)
                    }
                }
            } else {
                // 非 BMP 字符（如 emoji）：UTF-8 encoder.canEncode 恒为 true，原样输出，不转义。
                accum.unicodeScalars.append(scalar)
            }
        }
        return accum
    }

    // MARK: - 属性输出

    /// jsoup Attribute.shouldCollapseAttribute：syntax=html 且 (val 为空 或 val==key 忽略大小写)
    /// 且 key 是布尔属性时折叠（不输出 `="..."`）。
    static func shouldCollapseAttribute(key: String, value: String) -> Bool {
        let isBoolAttr = booleanAttributeNames.contains(key.lowercased())
        guard isBoolAttr else { return false }
        return value.isEmpty || value.caseInsensitiveCompare(key) == .orderedSame
    }

    /// 输出单个属性："key" 或 "key=\"value\""（value 按 inAttribute=true 转义）。
    static func attributeHTML(key: String, value: String) -> String {
        if shouldCollapseAttribute(key: key, value: value) {
            return key
        }
        let escaped = escape(value, inAttribute: true, normaliseWhite: false, stripLeadingWhite: false, trimTrailing: false)
        return "\(key)=\"\(escaped)\""
    }

    /// 输出元素的全部属性（每个前面带一个空格），顺序与解析出的原始顺序一致
    /// （SwiftSoup `Attributes.asList()` 保持插入顺序，等价于 jsoup `Attributes.html()` 遍历顺序）。
    static func attributesHTML(_ element: Element) -> String {
        guard let attrs = element.getAttributes() else { return "" }
        var out = ""
        for attribute in attrs.asList() {
            out.append(" ")
            out.append(attributeHTML(key: attribute.getKey(), value: attribute.getValue()))
        }
        return out
    }

    // MARK: - 主入口：对节点做 outerHtml() / html()

    /// 等价于 jsoup `Node.outerHtml()`：从该节点自身开始（depth=0），按深度优先遍历输出。
    static func outerHtml(_ node: Node) -> String {
        var accum = ""
        traverse(node, depth: 0, accum: &accum)
        return accum
    }

    /// 等价于 jsoup `Elements.outerHtml()`：对集合里每个元素分别 outerHtml()，用 "\n" 拼接。
    static func elementsOuterHtml(_ elements: [Element]) -> String {
        return elements.map { outerHtml($0) }.joined(separator: "\n")
    }

    /// 等价于 jsoup `Elements.html()`：对集合里每个元素分别 html()（inner html），用 "\n" 拼接。
    static func elementsInnerHtml(_ elements: [Element]) -> String {
        return elements.map { innerHtml($0) }.joined(separator: "\n")
    }

    /// 等价于 jsoup `Element.html()`：只输出子节点（不含自身标签），再 trim 一次
    /// （jsoup: `prettyPrint() ? html.trim() : html`，本项目固定 prettyPrint=true）。
    static func innerHtml(_ element: Element) -> String {
        var accum = ""
        for child in element.getChildNodes() {
            traverse(child, depth: 0, accum: &accum)
        }
        return accum.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 深度优先遍历，等价于 jsoup `NodeTraversor.traverse`：对每个节点调用 head，
    /// 如果有子节点则 depth+1 递归，叶子节点（或子节点遍历完）调用 tail。
    /// SwiftSoup 的 `Node`/`Element` 都暴露了 `getChildNodes()`，可以安全地直接递归
    /// （不需要复刻 jsoup 用显式栈避免递归爆栈的写法；书源 HTML 的实际嵌套深度远小于
    /// Swift 默认调用栈限制）。
    private static func traverse(_ node: Node, depth: Int, accum: inout String) {
        head(node, depth: depth, accum: &accum)
        let children = node.getChildNodes()
        for child in children {
            traverse(child, depth: depth + 1, accum: &accum)
        }
        // jsoup OuterHtmlVisitor.tail 对 "#text" 节点跳过 tail 调用（文本节点没有 tail 输出）。
        if node.nodeName() != "#text" {
            tail(node, depth: depth, accum: &accum)
        }
    }

    // MARK: - indent()

    /// jsoup Node.indent：'\n' + padding(depth * indentAmount, maxPaddingWidth)。
    /// 本项目固定 indentAmount=1, maxPaddingWidth=30。
    private static func indent(depth: Int, accum: inout String) {
        accum.append("\n")
        accum.append(padding(depth))
    }

    // MARK: - head/tail 分发（按节点的 Swift 动态类型）

    private static func head(_ node: Node, depth: Int, accum: inout String) {
        switch node {
        case let el as Element:
            elementHead(el, depth: depth, accum: &accum)
        case let tn as TextNode:
            textNodeHead(tn, depth: depth, accum: &accum)
        case let c as Comment:
            commentHead(c, depth: depth, accum: &accum)
        case let d as DataNode:
            dataNodeHead(d, accum: &accum)
        case let dt as DocumentType:
            documentTypeHead(dt, accum: &accum)
        default:
            // SwiftSoup 不包含 jsoup 的 CDataNode/XmlDeclaration 在 HTML 解析路径下的产出
            // （XmlDeclaration 仅在 XML 解析场景出现，本项目的书源规则引擎只处理 HTML 文档，
            // 不涉及 XML 解析），因此这里不做特殊处理，遇到未知节点类型时静默跳过。
            break
        }
    }

    private static func tail(_ node: Node, depth: Int, accum: inout String) {
        if let el = node as? Element {
            elementTail(el, depth: depth, accum: &accum)
        }
        // Comment/DataNode/DocumentType 的 outerHtmlTail 都是空实现（jsoup 源码确认）。
    }

    // MARK: - Element

    /// jsoup Element.isFormatAsBlock(out)：tag.isBlock() || (parent 的 tag formatAsBlock()) || outline()。
    /// 本项目固定 outline=false。
    private static func isFormatAsBlock(_ element: Element) -> Bool {
        let info = tagInfo(for: element.tagName())
        if info.isBlock { return true }
        if let parent = element.parent() as? Element {
            let parentInfo = tagInfo(for: parent.tagName())
            if parentInfo.formatAsBlock { return true }
        }
        return false
    }

    /// jsoup Element.isInlineable(out)：
    /// !tag.isInline() → false；否则 (parent==nil || parent.isBlock()) && !isEffectivelyFirst()
    /// && !outline() && !isNode("br")。本项目固定 outline=false。
    private static func isInlineable(_ element: Element) -> Bool {
        let info = tagInfo(for: element.tagName())
        guard info.isInline else { return false }
        let parent = element.parent()
        let parentIsBlockOrNil: Bool
        if let parentEl = parent as? Element {
            parentIsBlockOrNil = tagInfo(for: parentEl.tagName()).isBlock
        } else {
            // parent() 在 SwiftSoup 中对没有父节点的情况返回 nil；对于非 Element 类型的父节点
            // （理论上不会出现，父节点要么是 Element 要么是 Document/nil），按 jsoup 语义
            // parent==null 时视为满足条件。
            parentIsBlockOrNil = (parent == nil)
        }
        guard parentIsBlockOrNil else { return false }
        if isEffectivelyFirst(element) { return false }
        if element.tagNameNormal() == "br" { return false }
        return true
    }

    /// jsoup Node.isEffectivelyFirst：siblingIndex==0，或者 siblingIndex==1 且前一个兄弟是空白 TextNode。
    private static func isEffectivelyFirst(_ node: Node) -> Bool {
        if node.siblingIndex == 0 { return true }
        if node.siblingIndex == 1 {
            if let prev = node.previousSibling() as? TextNode {
                return prev.isBlank()
            }
        }
        return false
    }

    /// jsoup Element.preserveWhitespace(node)：从该节点（含自身）往上最多查 6 层 Element，
    /// 只要有一层 tag.preserveWhitespace() 为 true 就返回 true。
    static func preserveWhitespace(_ node: Node?) -> Bool {
        var current = node
        var i = 0
        while let el = current as? Element, i < 6 {
            if tagInfo(for: el.tagName()).preserveWhitespace { return true }
            current = el.parent()
            i += 1
        }
        return false
    }

    /// jsoup Element.shouldIndent(out)：prettyPrint && isFormatAsBlock && !isInlineable && !preserveWhitespace(parent)。
    private static func shouldIndent(_ element: Element) -> Bool {
        return isFormatAsBlock(element) && !isInlineable(element) && !preserveWhitespace(element.parent())
    }

    private static func elementHead(_ element: Element, depth: Int, accum: inout String) {
        if shouldIndent(element) {
            // jsoup: 只有 accum 非空（即不是输出的第一个字符）时才缩进。
            if !accum.isEmpty {
                indent(depth: depth, accum: &accum)
            }
        }
        accum.append("<")
        accum.append(element.tagName())
        accum.append(attributesHTML(element))

        // jsoup: `if (childNodes.isEmpty() && tag.isSelfClosing()) { syntax==html && tag.isEmpty()
        // ? accum.append('>') : accum.append(" />"); } else accum.append('>');`
        // 本项目 syntax 固定为 html，且 Tag 清单里只有 emptyTagNames 会让 isSelfClosing 为 true
        // （未复刻"未知标签自闭合"的 selfClosing 标记位——真实书源 HTML 不会触发该分支），
        // 所以 "children 为空且 isSelfClosing" 这个分支在本项目里恒等于 "html + isEmpty"，
        // 两个条件分支都输出同样的无斜杠 "<tag ...>"，故直接统一输出 ">"。
        accum.append(">")
    }

    private static func elementTail(_ element: Element, depth: Int, accum: inout String) {
        let info = tagInfo(for: element.tagName())
        let children = element.getChildNodes()
        let isSelfClosingEmpty = children.isEmpty && info.isSelfClosing
        guard !isSelfClosingEmpty else { return }

        // prettyPrint && !children.isEmpty && (tag.formatAsBlock() && !preserveWhitespace(parent))
        // （outline=false 固定，省略 outline 分支）
        if !children.isEmpty {
            let formatAsBlock = tagInfo(for: element.tagName()).formatAsBlock
            if formatAsBlock && !preserveWhitespace(element.parent()) {
                indent(depth: depth, accum: &accum)
            }
        }
        accum.append("</")
        accum.append(element.tagName())
        accum.append(">")
    }

    // MARK: - TextNode

    private static func textNodeHead(_ textNode: TextNode, depth: Int, accum: inout String) {
        let prettyPrint = true // OutputSettings 固定
        let parentNode = textNode.parent()
        let parentElement = parentNode as? Element
        let normaliseWhite = prettyPrint && !preserveWhitespace(parentNode)
        let trimLikeBlock: Bool
        if let parent = parentElement {
            let info = tagInfo(for: parent.tagName())
            trimLikeBlock = info.isBlock || info.formatAsBlock
        } else {
            trimLikeBlock = false
        }

        var trimLeading = false
        var trimTrailing = false

        if normaliseWhite {
            trimLeading = (trimLikeBlock && textNode.siblingIndex == 0) || (parentNode is Document)
            trimTrailing = trimLikeBlock && textNode.nextSibling() == nil

            let next = textNode.nextSibling()
            let prev = textNode.previousSibling()
            let isBlankText = textNode.isBlank()

            var couldSkip = false
            if let nextEl = next as? Element, shouldIndent(nextEl) {
                couldSkip = true
            }
            if let nextText = next as? TextNode, nextText.isBlank() {
                couldSkip = true
            }
            if let prevEl = prev as? Element {
                let prevInfo = tagInfo(for: prevEl.tagName())
                if prevInfo.isBlock || prevEl.tagNameNormal() == "br" {
                    couldSkip = true
                }
            }

            if couldSkip && isBlankText { return }

            var shouldWrapIndent = false
            if textNode.siblingIndex == 0, let parent = parentElement,
               tagInfo(for: parent.tagName()).formatAsBlock, !isBlankText {
                shouldWrapIndent = true
            }
            // out.outline() 固定 false，省略该分支。
            if textNode.siblingIndex > 0, let prevEl = prev as? Element, prevEl.tagNameNormal() == "br" {
                shouldWrapIndent = true
            }

            if shouldWrapIndent {
                indent(depth: depth, accum: &accum)
            }
        }

        let escaped = escape(
            textNode.getWholeText(),
            inAttribute: false,
            normaliseWhite: normaliseWhite,
            stripLeadingWhite: trimLeading,
            trimTrailing: trimTrailing
        )
        accum.append(escaped)
    }

    // MARK: - Comment

    private static func commentHead(_ comment: Comment, depth: Int, accum: inout String) {
        let isFirst = isEffectivelyFirst(comment)
        let parentFormatsAsBlock: Bool
        if let parentEl = comment.parent() as? Element {
            parentFormatsAsBlock = tagInfo(for: parentEl.tagName()).formatAsBlock
        } else {
            parentFormatsAsBlock = false
        }
        // out.outline() 固定 false，省略该分支。
        if isFirst && parentFormatsAsBlock {
            indent(depth: depth, accum: &accum)
        }
        accum.append("<!--")
        accum.append(comment.getData())
        accum.append("-->")
    }

    // MARK: - DataNode（script/style 内容，原样输出不转义）

    private static func dataNodeHead(_ dataNode: DataNode, accum: inout String) {
        accum.append(dataNode.getWholeData())
    }

    // MARK: - DocumentType

    private static func documentTypeHead(_ docType: DocumentType, accum: inout String) {
        let publicId = (try? docType.attr("publicId")) ?? ""
        let systemId = (try? docType.attr("systemId")) ?? ""
        let name = (try? docType.attr("name")) ?? ""
        let pubSysKey = (try? docType.attr("pubSysKey")) ?? ""

        // syntax 固定 html：若无 publicId/systemId，输出小写 "<!doctype"（HTML5 风格）；
        // 否则输出大写 "<!DOCTYPE"（与 jsoup 一致）。
        if isBlank(publicId) && isBlank(systemId) {
            accum.append("<!doctype")
        } else {
            accum.append("<!DOCTYPE")
        }
        if !isBlank(name) {
            accum.append(" ")
            accum.append(name)
        }
        if !isBlank(pubSysKey) {
            accum.append(" ")
            accum.append(pubSysKey)
        }
        if !isBlank(publicId) {
            accum.append(" \"")
            accum.append(publicId)
            accum.append("\"")
        }
        if !isBlank(systemId) {
            accum.append(" \"")
            accum.append(systemId)
            accum.append("\"")
        }
        accum.append(">")
    }
}

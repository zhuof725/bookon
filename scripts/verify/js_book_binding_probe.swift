//
//  js_book_binding_probe.swift — 验证 `@js:` 规则的 `book` 绑定**数据源**正确。
//
//  背景（CI run 37463875191 的真实失败）：
//    Linux/CI 日志显示 `⇒目录0未获取到url,使用baseUrl替代`，即淘小说
//    `ruleToc.chapterUrl` 的 `@js:` 没算出 URL。原因是该规则写：
//        var m = String(book.bookUrl).match(/sourceId=([^&]+)/);
//    而本移植的 JS 绑定把 `book` 绑成了**书名字符串**（Kotlin 绑的是 BaseBook 对象），
//    于是 `book.bookUrl` 得 `undefined` → `.match()` 返回 null → `m[1]` 抛 TypeError。
//
//  Linux 无 JavaScriptCore，无法直接跑 JS。本探针改为验证**喂给 JS 的数据源**：
//    * `BookBox.jsFields` / `BookChapterBox.jsFields` 必须包含 Kotlin 规则会用到的键；
//    * `bookUrl` 等值必须与 Book 的真值一致（尤其含 `sourceId=`，正则才能匹配）；
//    * 空 Book 不应崩溃（键存在但值为空串）。
//
//  真正的 JS 求值以 macOS / iOS CI 为准。
//

import Foundation
import LegadoBookSource

var PASS = 0, FAIL = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { PASS += 1 } else { FAIL += 1; print("  [X] FAIL: \(msg)  [line \(line)]") }
}

@main struct JsBookBindingProbe {
    static func main() {
        print("== JS `book` / `chapter` 绑定数据源 ==")

        // ── 1) BookBox.jsFields 覆盖淘小说 chapterUrl 规则所需字段 ──
        var book = Book()
        book.bookUrl = "http://betam.taoyuewenhua.com/ajax/or/ty/book?sourceName=tf&sourceId=4001"
        book.tocUrl = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/chapter_list?sourceName=tf&sourceId=4001&page=0&pageSize=100"
        book.name = "合成淘小说之书"
        book.author = "合成作者丁"
        book.origin = "http://betam.taoyuewenhua.com"
        book.kind = "科幻"
        book.wordCount = "66万"

        let box = BookBox(book)
        let f = box.jsFields
        check(f["bookUrl"] == book.bookUrl, "bookUrl 必须为真值（实际 \(f["bookUrl"] ?? "nil")）")
        check(f["bookUrl"]?.contains("sourceId=4001") == true,
              "bookUrl 必须含 sourceId=4001（chapterUrl 的 /sourceId=([^&]+)/ 才匹配得上）")
        check(f["tocUrl"] == book.tocUrl, "tocUrl 必须为真值")
        check(f["name"] == "合成淘小说之书", "name 必须为真值")
        check(f["author"] == "合成作者丁", "author 必须为真值")
        check(f["kind"] == "科幻", "kind 必须为真值")
        check(f["wordCount"] == "66万", "wordCount 必须为真值")
        check(f["origin"] == book.origin, "origin 必须为真值")
        // 备选/空值字段也要**存在**（避免 JS 里取到 undefined 而非空串）。
        for k in ["intro", "latestChapterTitle", "durChapterTitle", "variable", "originName", "totalChapterNum"] {
            check(f[k] != nil, "可选字段 \(k) 也应存在（空值用空串，不能缺失）")
        }

        // ── 2) SearchBookBox.jsFields ──
        var sb = SearchBook()
        sb.bookUrl = book.bookUrl
        sb.name = "合成淘小说之书"
        sb.author = "合成作者丁"
        let sbox = SearchBookBox(sb)
        check(sbox.jsFields["bookUrl"] == book.bookUrl, "SearchBookBox.bookUrl 必须为真值")
        check(sbox.jsFields["name"] == "合成淘小说之书", "SearchBookBox.name 必须为真值")

        // ── 3) BookChapterBox.jsFields ──
        var ch = BookChapter()
        ch.title = "第一章 淘小说起始"
        ch.url = "http://x/1"
        ch.bookUrl = book.bookUrl
        ch.index = 3
        ch.isVip = true
        let cbox = BookChapterBox(ch)
        let cf = cbox.jsFields
        check(cf["title"] == "第一章 淘小说起始", "chapter.title 必须为真值")
        check(cf["url"] == "http://x/1", "chapter.url 必须为真值")
        check(cf["bookUrl"] == book.bookUrl, "chapter.bookUrl 必须为真值")
        check(cf["index"] == "3", "chapter.index 必须为数字字符串（实际 \(cf["index"] ?? "nil")）")
        check(cf["isVip"] == "true", "chapter.isVip 必须为 \"true\"")
        check(cf["isPay"] == "false", "chapter.isPay 必须为 \"false\"")

        // ── 4) 空值不崩溃（键存在、值为空串）──
        let emptyBox = BookBox(Book())
        check(emptyBox.jsFields["bookUrl"] == "", "空 Book 的 bookUrl 应为空串（不是 nil/崩溃）")
        check(emptyBox.jsFields["kind"] == "", "空 Book 的 kind 应为空串")
        check(BookChapterBox(BookChapter()).jsFields["title"] == "", "空 BookChapter.title 应为空串")

        // ── 5) 默认实现（非 BookBox 的 BookData）仍可用，键集为空 ──
        let mem = InMemoryBook(name: "X")
        check(mem.jsFields.isEmpty, "InMemoryBook 应走默认实现（空字典），保证既有行为不变")

        print("PASS=\(PASS) FAIL=\(FAIL)")
        if FAIL > 0 { exit(1) }
    }
}

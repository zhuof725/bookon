//
//  toc_flow_probe.swift — 在 Linux 上完整跑一遍「淘小说 目录」流程，
//  用 MockWebBookNetwork.requestedURLs 打印**实际发生的每一次请求 URL**，
//  用于与 CI（有 JavaScriptCore）的真实行为对照。
//
//  Linux 限制与等价处理（不撒谎，见 e2e 测试文件头的平台差异说明）：
//    * 没有 JavaScriptCore，`@js:` 规则无法求值。本探针因此手工预置
//      `book.tocUrl` 为「JSC 在 CI 上会算出的值」，把**流程层 + 规则解析层**
//      （与平台无关的部分）单独验证出来。
//    * 真正的 `@js:` 求值仍以 macOS / iOS CI 为准。
//

import Foundation
import LegadoBookSource

@main struct TocFlowProbe {
    static func main() async {
        let base = "Tests/LegadoWebBookTests/Resources/real/"
        guard let all = try? LegadoJSON.decoder.decode([BookSource].self,
                from: Data(contentsOf: URL(fileURLWithPath: base + "real_sources_5.json"))),
              let src = all.first(where: { $0.bookSourceName == "⚡📂淘小说书城" }) else {
            print("no src"); return
        }

        let bookURL = "http://betam.taoyuewenhua.com/ajax/or/ty/book?sourceName=tf&sourceId=4001"
        let tocURL = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/chapter_list?sourceName=tf&sourceId=4001&page=0&pageSize=100"
        let tocBody = """
        {"code":0,"data":{"chapters":[
          {"chapterId":"1","chapterTitle":"第一章 淘小说起始"},
          {"chapterId":"2","chapterTitle":"第二章 淘小说发展"}]}}
        """
        let net = MockWebBookNetwork()
        net.set(tocURL, WebBookResponse(url: tocURL, status: 200, body: tocBody))

        // bookUrl 含 sourceId（JSC 的 chapterUrl 规则正是从这里取 sourceId）。
        var book = Book()
        book.bookUrl = bookURL
        book.tocUrl = tocURL
        book.origin = src.bookSourceUrl
        book.name = "合成淘小说之书"
        book.author = "合成作者丁"

        let opts = WebBookOptions(network: net)
        do {
            let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
            print("chapters.count = \(chapters.count)")
            for c in chapters { print("   title=[\(c.title)] url=[\(c.url)]") }
        } catch {
            print("THROW: \(error)")
        }
        print("requestedURLs = \(net.requestedURLs)")
    }
}

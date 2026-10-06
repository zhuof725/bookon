//
//  toc_path_probe.swift — 复刻 `BookChapterList.analyzeChapterList` 里
//  `analyzeRule.getElements(listRule)` 的**真实调用路径**，定位淘小说只解析出 1 章的原因。
//
import Foundation
import LegadoBookSource

@main struct TocPathProbe {
  static func main() throws {
    let base = "Tests/LegadoWebBookTests/Resources/real/"
    let all = try LegadoJSON.decoder.decode([BookSource].self,
        from: try Data(contentsOf: URL(fileURLWithPath: base + "real_sources_5.json")))
    guard var src = all.first(where: { $0.bookSourceName == "⚡📂淘小说书城" }) else {
        print("no src"); return }

    let tocBody = """
    {"code":0,"data":{"chapters":[
      {"chapterId":"1","chapterTitle":"第一章 淘小说起始"},
      {"chapterId":"2","chapterTitle":"第二章 淘小说发展"}]}}
    """
    let tocRule = src.getTocRule()
    print("chapterList =", tocRule.chapterList ?? "nil")
    print("chapterName =", tocRule.chapterName ?? "nil")
    print("chapterUrl  =", (tocRule.chapterUrl ?? "nil").prefix(60), "...")
    print("nextTocUrl  =", (tocRule.nextTocUrl ?? "nil").prefix(80), "...")
    print("")

    let r = AnalyzeRule()
    _ = try r.setContent(tocBody).setBaseUrl("http://betam.taoyuewenhua.com/ajax/or/ty/book?sourceName=tf&sourceId=4001")
    r.setRedirectUrl("http://x/")

    let els = (try? r.getElements(tocRule.chapterList ?? "")) ?? []
    print("getElements -> count =", els.count)
    for (i, e) in els.enumerated() {
      print("  [\(i)] kind=\(e)  stringValue=[\(e.stringValue.prefix(120))]")
    }
    print("")
    // 对照：getStringList
    let sl = (try? r.getStringList(tocRule.chapterList ?? "")) ?? []
    print("getStringList -> count =", sl.count, sl)
  }
}

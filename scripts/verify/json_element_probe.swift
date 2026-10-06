//
//  json_element_probe.swift — 验证 JSONPath 多元素解析**保留结构**（本轮修复）。
//
//  背景（真实缺陷）：真实书源「淘小说书城」的 `ruleToc.chapterUrl` 是
//    `@js: ... + String(result.chapterId)`
//  —— 要求 JS 里的 `result` 是一个**带字段的对象**。本移植早期把 `getElements` 的
//  json 分支降级成 JSON 文本字符串，导致 `result.chapterId` 恒为 undefined，
//  所有章节 URL 相同、被按 url 去重压成 1 章。
//
//  本探针验证修复后的不变量：
//    1) `getElements("$.data.chapters[*]")` 返回 **2** 个元素；
//    2) 每个元素的 kind 是 `.json`（结构化），不是 `.string`；
//    3) 元素上能按 JSONPath 取到字段（等价于 JS 里 `result.chapterId` 能取到值）。
//

import Foundation
import LegadoBookSource

var PASS = 0, FAIL = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { PASS += 1 } else { FAIL += 1; print("  [X] FAIL: \(msg)  [line \(line)]") }
}

@main struct JsonElementProbe {
    static func main() throws {
        print("== JSONPath 多元素结构保留 ==")

        let tocBody = """
        {"code":0,"data":{"chapters":[
          {"chapterId":"1","chapterTitle":"第一章 淘小说起始"},
          {"chapterId":"2","chapterTitle":"第二章 淘小说发展"}]}}
        """
        let r = AnalyzeRule()
        _ = try r.setContent(tocBody).setBaseUrl("http://b/")

        let els = try r.getElements("$.data.chapters[*]")
        check(els.count == 2, "应返回 2 个元素，实际 \(els.count)")

        if els.count == 2 {
            for (i, e) in els.enumerated() {
                if case .json(let j) = e {
                    check(true, "[\(i)] 元素为结构化 .json")
                    // 模拟 @js 里的 `result.chapterId` / `result.chapterTitle`：
                    // 在 .json 元素上按字段取 JSONPath。
                    let cid = try? AnalyzeByJSonPath(j).getString("$.chapterId")
                    let title = try? AnalyzeByJSonPath(j).getString("$.chapterTitle")
                    let expectedId = "\(i + 1)"
                    let expectedTitle = i == 0 ? "第一章 淘小说起始" : "第二章 淘小说发展"
                    check(cid == expectedId, "[\(i)] chapterId 应为 \(expectedId)，实际 \(cid ?? "nil")")
                    check(title == expectedTitle, "[\(i)] chapterTitle 应为 \(expectedTitle)，实际 \(title ?? "nil")")
                } else {
                    check(false, "[\(i)] 元素应为 .json，实际 \(e)")
                }
            }
        }

        // 逐元素 setContent 后解析 chapterName 规则（与 BookChapterList 的循环等价）。
        let nameRules = try r.splitSourceRule("$.chapterTitle")
        var titles: [String] = []
        for item in els {
            _ = try? r.setContent(item)
            titles.append((try? r.getString(ruleList: nameRules)) ?? "")
        }
        check(titles == ["第一章 淘小说起始", "第二章 淘小说发展"],
              "逐元素解析标题应为两章，实际 \(titles)")

        print("PASS=\(PASS) FAIL=\(FAIL)")
        if FAIL > 0 { exit(1) }
    }
}

import Foundation

/// 番茄🍅（沐凡）书源（服务器聚合源 fqaggregate）的兼容性回归。
///
/// 这个源的搜索分类（ruleSearch.kind）是「模板文本段 + <js> 段 + 尾部纯正则段」的混合规则，
/// 踩到的坑都在 AnalyzeRule 混合规则求值与原版的差异上：
/// 1. 带 {{模板}} 的文本段被 jsonStringValues 当成 JSON 路径查询（因为内容是 JSON 字典），
///    返回数组传给后续 JS → `result.replace is not a function`（搜索 10 本书报 10 次错）。
///    原版把这一段按字符串累计进 result 再交给 JS。
/// 2. JS 失败后 cur 变空串，尾部纯正则段 `##·##,` 把空串又解析成 HTML 文档，
///    stringValue 的 rule.isEmpty 分支取了空文档的 outerHtml → 分类变成
///    `<html>,<head></head>,<body></body>,</html>`。原版：规则为空 + 有替换正则 →
///    不再求值，直接对累计 result 做替换。
/// 3. 混合规则 JS 段里 java.getString("$.gender") 应作用于本条规则的内容节点
///    （原版 bindings["java"] = this），不是前面各段累计的 result。
enum MufanSourceRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        // 与真实搜索接口同形的条目（gender/creation_status/score 是字符串，isbn/时间戳缺失）。
        let item: [String: Any] = [
            "book_id": "7208454824847739938",
            "book_name": "开局激活神豪系统，获得无限黑卡",
            "author": "怒目金刚",
            "gender": "1",
            "category": "玄幻脑洞",
            "creation_status": "0",
            "score": "8.0",
            "sub_title": "",
        ]

        // MARK: 1) 模板文本段不被当 JSON 查询：后续 JS 的 result 是字符串

        let ar1 = AnalyzeRule(content: item, baseUrl: "https://x.example")
        let r1 = ar1.getStringList("{{$.gender}}\n##nomatch##\n<js>result.replace('1','X')</js>")
        check(r1 == ["X"], "混合规则文本段不被当 JSON 查询（result 是字符串），实际 \(r1)")

        // MARK: 2) 尾部纯正则段直接改累计结果，不解析成 HTML

        let r2 = ar1.getStringList("{{$.gender}}\n<js>'a·b'</js>##·##,")
        check(r2 == ["a,b"], "纯正则段作用于累计结果（不回读空文档 outerHtml），实际 \(r2)")
        // getString 同一语义
        let r2b = ar1.getString("{{$.gender}}\n<js>'a·b'</js>##·##,")
        check(r2b == "a,b", "getString 纯正则段作用于累计结果，实际 \(r2b)")

        // MARK: 3) JS 段里 java.getString 作用于内容节点

        let r3 = ar1.getString("{{$.gender}}\n<js>java.getString('$.category')</js>")
        check(r3 == "玄幻脑洞", "JS 段 java.getString 作用于内容节点，实际 \(r3)")

        // MARK: 4) 番茄（沐凡）真实 kind 规则（夹具）

        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures/mufan-fanqie-source.json")
        guard let data = try? Data(contentsOf: fixture),
              let list = try? JSONDecoder().decode([BookSource].self, from: data),
              let source = list.first, let kindRule = source.ruleSearch?.kind else {
            check(false, "沐凡书源：夹具可用且 ruleSearch.kind 存在")
            return
        }
        let kinds = AnalyzeRule(content: item, baseUrl: source.bookSourceUrl)
            .getStringList(kindRule)
        check(kinds.contains("玄幻脑洞") && kinds.contains("男生"),
              "沐凡 kind：分类含性别与分类，实际 \(kinds)")
        check(!kinds.contains(where: { $0.contains("<html>") || $0.contains("head") }),
              "沐凡 kind：没有空文档 outerHtml 残片，实际 \(kinds)")
        check(kinds.joined(separator: ",") == "男生,玄幻脑洞,完结,8.0分",
              "沐凡 kind：整串按原版语义清理，实际 \(kinds.joined(separator: ","))")
    }
}

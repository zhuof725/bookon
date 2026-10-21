import Foundation
import SwiftSoup

/// 规则没命中时的**自动识别兜底**：站点改版后，书源规则往往整段失效
/// （目录链接没了、章节列表换了 class、正文容器改名）。
/// 这里按通用特征把内容找回来，不改书源也能读。
///
/// 原则：
/// - 只在规则结果为空时启用，绝不覆盖能正常工作的规则；
/// - 每次兜底都写一条 `≡…` 日志，方便书源调试页确认走的是哪条路径；
/// - 阈值保守（章节数、正文长度、链接密度），宁可返回空也不乱抓。
enum AutoDetect {

    // MARK: - 详情页：og: meta 兜底

    /// 常见站点的 OpenGraph / 小说元信息（爱丽丝书屋、大量 CMS 站都有）。
    static func meta(_ doc: Document, names: [String]) -> String {
        for name in names {
            if let el = try? doc.select("meta[property=\(name)],meta[name=\(name)]").first(),
               let content = try? el.attr("content"),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    static func metaName(_ doc: Document) -> String {
        meta(doc, names: ["og:novel:book_name", "og:novel:novel_name", "og:title", "twitter:title"])
    }

    static func metaAuthor(_ doc: Document) -> String {
        meta(doc, names: ["og:novel:author", "article:author", "og:article:author"])
    }

    static func metaIntro(_ doc: Document) -> String {
        meta(doc, names: ["og:description", "og:novel:description", "description"])
    }

    static func metaCover(_ doc: Document) -> String {
        meta(doc, names: ["og:image", "twitter:image"])
    }

    static func metaKind(_ doc: Document) -> String {
        meta(doc, names: ["og:novel:category", "og:novel:genre"])
    }

    static func metaLastChapter(_ doc: Document) -> String {
        meta(doc, names: ["og:novel:latest_chapter_name", "og:novel:last_chapter"])
    }

    // MARK: - 详情页：目录链接兜底

    /// 详情页里找「目录 / 章节列表」入口（站点改版后 tocUrl 规则最容易失效）。
    static func tocLink(in doc: Document, baseUrl: String) -> String? {
        let keywords = ["全部章节", "查看目录", "章节目录", "章节列表", "目录", "章节", "chapter"]
        var best: (score: Int, href: String)?
        let anchors = (try? doc.select("a[href]").array()) ?? []
        for a in anchors {
            let text = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 20 else { continue }
            let href = ((try? a.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !href.hasPrefix("javascript:"), !href.hasPrefix("#") else { continue }
            let lowered = text.lowercased()
            var score = 0
            for (index, keyword) in keywords.enumerated() where lowered.contains(keyword.lowercased()) {
                score = max(score, keywords.count - index)
            }
            guard score > 0 else { continue }
            // 目录地址通常含 chapters/list/mulu/catalog 之类特征，加分
            let hrefLower = href.lowercased()
            if ["chapter", "catalog", "mulu", "list", "index"].contains(where: { hrefLower.contains($0) }) {
                score += 2
            }
            if best == nil || score > best!.score {
                best = (score, AnalyzeUrl.absolute(href, base: baseUrl))
            }
        }
        return best?.href
    }

    // MARK: - 目录页：章节列表自动识别

    /// 从目录页里找「一组结构相同的章节链接」。
    /// 打分：数量、href 前缀一致性、标题长度、导航词惩罚。
    static func chapters(in doc: Document, baseUrl: String) -> [BookChapter] {
        let navWords: Set<String> = ["首页", "上一页", "下一页", "末页", "目录", "章节", "返回", "加入书架", "投票", "推荐"]
        var best: (score: Int, items: [(title: String, href: String)])?

        // 候选容器：ul / ol / div / dl / table / section
        let containers = (try? doc.select("ul,ol,div,dl,table,section").array()) ?? []
        for container in containers {
            // 只看直接子元素里的链接（li>a 或 a），避免把整页导航算进来
            var links: [Element] = []
            for child in container.children().array() {
                if child.tagName() == "a" {
                    links.append(child)
                } else if let nested = try? child.select("a[href]").array(), !nested.isEmpty, child.tagName() == "li" || child.tagName() == "dd" || child.tagName() == "tr" {
                    links.append(contentsOf: nested)
                }
            }
            guard links.count >= 5 else { continue }
            var items: [(String, String)] = []
            for a in links {
                let title = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let href = ((try? a.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 60, !href.isEmpty,
                      !href.hasPrefix("javascript:"), !href.hasPrefix("#") else { continue }
                if navWords.contains(title) { continue }
                items.append((title, href))
            }
            guard items.count >= 5 else { continue }
            // href 前缀一致性：取前 12 个字符作为「路径特征」
            let prefixes = Set(items.map { String($0.1.prefix(12)) })
            let consistency = prefixes.count <= max(1, items.count / 4) ? 3 : 0
            let avgTitle = items.reduce(0) { $0 + $1.0.count } / max(1, items.count)
            let titleScore = (avgTitle >= 3 && avgTitle <= 40) ? 2 : 0
            let score = items.count * 2 + consistency + titleScore
            if best == nil || score > best!.score {
                best = (score, items)
            }
        }
        guard let best, best.items.count >= 5 else { return [] }
        var out: [BookChapter] = []
        for (index, item) in best.items.enumerated() {
            out.append(BookChapter(url: AnalyzeUrl.absolute(item.href, base: baseUrl),
                                   title: item.title, index: index))
        }
        return out
    }

    // MARK: - 正文页：正文容器自动识别

    /// 找「文字最多、链接最少」的容器；类名像正文的加分。
    static func content(in doc: Document) -> String {
        let hints = ["content", "read", "chapter", "article", "text", "novel", "正文", "content_txt"]
        var best: (score: Double, html: String)?
        let candidates = (try? doc.select("div,article,section,td").array()) ?? []
        for el in candidates {
            guard let text = try? el.text() else { continue }
            let length = text.count
            guard length >= 200 else { continue }
            let linkText = ((try? el.select("a").array()) ?? []).reduce(0) { $0 + ((try? $1.text().count) ?? 0) }
            let linkDensity = Double(linkText) / Double(max(1, length))
            guard linkDensity < 0.5 else { continue }
            var score = Double(length) * (1 - linkDensity)
            let cls = ((try? el.className()) ?? "").lowercased()
            let ident = ((try? el.id()) ?? "").lowercased()
            if hints.contains(where: { cls.contains($0) || ident.contains($0) }) { score *= 1.8 }
            if el.tagName() == "article" { score *= 1.3 }
            if best == nil || score > best!.score {
                best = (score, (try? el.html()) ?? "")
            }
        }
        guard let best, best.html.count >= 200 else { return "" }
        return best.html
    }
}

import Foundation

/// 「发现」页的纯数据整理：哪些书源可用于发现、按分组归类、分类切节、域名与头像色。
/// 与 UI 无关，可在 SourceTest 里离线回归。
enum DiscoverCatalog {
    /// 可用于「发现」浏览的书源：启用 + 启用发现（缺省开启）+ 配置了发现地址。
    static func explorableSources(_ list: [BookSource]) -> [BookSource] {
        list.filter { source in
            guard source.isEnabled, source.enabledExplore ?? true else { return false }
            return !(source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 一级分组：与书源管理同一规则（第一个分组名归类，无分组归「默认分组」并放最后）。
    static func sections(_ list: [BookSource]) -> [(name: String, sources: [BookSource])] {
        BookSource.groupedSections(explorableSources(list))
    }

    /// 某个分组下的可发现书源（归类规则与 sections 一致）。
    static func sources(inGroup name: String, from list: [BookSource]) -> [BookSource] {
        explorableSources(list).filter { ($0.sourceGroupNames.first ?? BookSource.defaultGroupName) == name }
    }

    /// 域名：优先取主机名；缺协议头时按 https 再试一次；都失败则返回去掉路径的原串。
    static func displayDomain(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let host = URLComponents(string: trimmed)?.host, !host.isEmpty { return host }
        if !trimmed.contains("://"),
           let host = URLComponents(string: "https://" + trimmed)?.host, !host.isEmpty {
            return host
        }
        var text = trimmed
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        return text
    }

    /// 书源卡片副标题：优先显示分组（原样，多个分组用逗号分隔），没有分组时显示域名。
    static func cardSubtitle(_ source: BookSource) -> String {
        let group = (source.bookSourceGroup ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return group.isEmpty ? displayDomain(source.bookSourceUrl) : group
    }

    /// 发现分类切节：控件项（text/button/select）不参与；原版发现规则里没有网址的项是分组标题
    /// （如「推荐」「最热」），其余按出现顺序归入当前小节；空小节（只有标题没有分类）被丢弃。
    static func kindSections(_ kinds: [SourceDiagnostics.ExploreKind])
        -> [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        var out: [(header: String?, items: [SourceDiagnostics.ExploreKind])] = []
        var header: String?
        var items: [SourceDiagnostics.ExploreKind] = []
        func flush() {
            if !items.isEmpty { out.append((header, items)) }
            header = nil
            items = []
        }
        for kind in kinds {
            if let type = kind.type, !type.isEmpty { continue }
            if (kind.url ?? "").isEmpty {
                flush()
                header = kind.title
            } else {
                items.append(kind)
            }
        }
        flush()
        return out
    }

    /// 榜单类板块用排名横条展示（分类名含「榜 / 推荐 / 排行 / 热门 / 热搜」），其余用封面网格。
    static func isRankingTitle(_ title: String) -> Bool {
        for keyword in ["榜", "推荐", "排行", "热门", "热搜"] where title.contains(keyword) {
            return true
        }
        return false
    }

    /// 发现控件是否只是装饰性横幅（如「██████ 男 生 ██████」）：装饰字符占比过高时跳过不显示。
    static func isDecorativeControlTitle(_ title: String) -> Bool {
        let decoration = CharacterSet(charactersIn: "█▓▒░■□●○◆◇★☆·•-—=~_+|/\\ ")
        let scalars = Array(title.unicodeScalars)
        guard !scalars.isEmpty else { return true }
        let decorated = scalars.filter { decoration.contains($0) }.count
        return Double(decorated) / Double(scalars.count) > 0.5
    }

    /// 发现脚本失败：原版在脚本出错时返回 ERROR: 项，页面据此显示错误与重试。
    static func kindError(_ kinds: [SourceDiagnostics.ExploreKind]) -> String? {
        kinds.first { $0.title.hasPrefix("ERROR:") }?.title
    }

    /// 头像底色色相（0..<1）：由名字决定且与进程无关，重启后颜色不变。
    static func avatarHue(for name: String) -> Double {
        var hash: UInt64 = 5381
        for byte in name.trimmingCharacters(in: .whitespacesAndNewlines).utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Double(hash % 360) / 360.0
    }
}

extension BookSource {
    /// 「发现」卡片上的类型标签（文本源不显示）。
    var discoverTypeLabel: String? {
        switch bookSourceType ?? 0 {
        case 1: return "音频"
        case 2: return "图片"
        case 3: return "文件"
        case 4: return "视频"
        default: return nil
        }
    }
}

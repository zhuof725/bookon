import SwiftUI
import UIKit

/// 「探索」页的固定色与共用尺寸。
///
/// 参考图用一套暖红色做强调（榜单前三、选中标签、推荐语高亮）。
/// 这是版式自身的强调色，不跟随主题强调色，避免自定义主题把整套参考配色打散。
enum ExploreStyle {
    /// 参考图的品牌红。
    static let hot = Color(red: 0.914, green: 0.325, blue: 0.259)
    /// 推荐语里引号片段的蓝。
    static let link = Color(red: 0.239, green: 0.478, blue: 0.921)
    /// 标签的暖色底 / 字色（深浅色分别取值）。
    static let tagBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.29, green: 0.24, blue: 0.17, alpha: 1)
            : UIColor(red: 0.976, green: 0.933, blue: 0.867, alpha: 1)
    })
    static let tagText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.88, green: 0.74, blue: 0.55, alpha: 1)
            : UIColor(red: 0.635, green: 0.435, blue: 0.243, alpha: 1)
    })

    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 6
}

// MARK: - 卡片容器

/// 白底大圆角卡片：参考图里每个板块都是一张这样的卡。
struct ExploreCard<Content: View>: View {
    @ThemePalette private var palette
    var spacing: CGFloat
    var padding: CGFloat
    private let content: Content

    init(spacing: CGFloat = 14, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: ExploreStyle.cardRadius, style: .continuous)
                    .fill(palette.surface)
            }
    }
}

// MARK: - 页头

/// 普通板块页头：标题（可带副标题）+「更多」。
struct ExploreCardHeader: View {
    @ThemePalette private var palette
    let title: String
    var subtitle: String? = nil
    var more: ExploreCategory? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .appFont(.system(size: 21, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let subtitle, !subtitle.isEmpty {
                Rectangle()
                    .fill(palette.border.opacity(0.7))
                    .frame(width: 1, height: 15)
                Text(subtitle)
                    .appFont(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            if let more { ExploreMoreLink(category: more) }
        }
    }
}

/// 可切换分类的页头：选中项在文字下半截垫一条暖红横杠（参考图的高亮笔效果）。
struct ExploreTabHeader: View {
    @ThemePalette private var palette
    let titles: [String]
    let selection: Int
    var more: ExploreCategory? = nil
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        Button {
                            onSelect(index)
                        } label: {
                            tabLabel(title, selected: index == selection)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(index == selection ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            if let more {
                ExploreMoreLink(category: more)
                    .fixedSize()
            }
        }
    }

    private func tabLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .appFont(.system(size: 20, weight: .bold))
            .foregroundStyle(selected ? palette.primary : palette.secondary)
            .padding(.bottom, 3)
            .background(alignment: .bottom) {
                if selected {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(ExploreStyle.hot.opacity(0.92))
                        .frame(height: 9)
                        .offset(y: 2)
                }
            }
            .fixedSize()
    }
}

/// 居中大标题 + 两侧斜杠（「猜你喜欢」）。
struct ExploreCenteredTitle: View {
    @ThemePalette private var palette
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            slash(angle: -18)
            Text(title)
                .appFont(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.primary)
            slash(angle: 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func slash(angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(ExploreStyle.hot.opacity(0.55))
            .frame(width: 19, height: 6)
            .rotationEffect(.degrees(angle))
    }
}

/// 「更多 >」胶囊。
struct ExploreMoreLink: View {
    @ThemePalette private var palette
    @EnvironmentObject private var appStore: AppStore
    let category: ExploreCategory

    var body: some View {
        if let source = appStore.source(for: category.sourceURL) {
            NavigationLink {
                DiscoverBooksView(source: source, kindTitle: category.title, kindUrl: category.url)
            } label: {
                HStack(spacing: 3) {
                    Text("更多").appFont(.system(size: 13))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background {
                    Capsule().stroke(palette.border.opacity(0.6), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 小部件

/// 分类筛选胶囊：选中 = 暖红字 + 淡红底；未选中 = 深色字 + 浅灰底。
struct ExploreChip: View {
    @ThemePalette private var palette
    let text: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .appFont(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? ExploreStyle.hot : palette.primary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background {
                    Capsule().fill(selected ? ExploreStyle.hot.opacity(0.10) : palette.selection.opacity(0.55))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum ExploreTagKind {
    /// 暖色（畅销精选的第一个标签）。
    case warm
    /// 淡红（新书榜的「更新稳定 / 日评论破千」）。
    case hot
    /// 浅灰。
    case plain
}

struct ExploreTagPill: View {
    @ThemePalette private var palette
    let text: String
    var kind: ExploreTagKind = .plain

    var body: some View {
        Text(text)
            .appFont(.system(size: 10.5))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(background)
            }
    }

    private var foreground: Color {
        switch kind {
        case .warm: return ExploreStyle.tagText
        case .hot: return ExploreStyle.hot
        case .plain: return palette.secondary
        }
    }

    private var background: Color {
        switch kind {
        case .warm: return ExploreStyle.tagBackground
        case .hot: return ExploreStyle.hot.opacity(0.10)
        case .plain: return palette.selection.opacity(0.55)
        }
    }
}

/// 榜单排名：前三名用暖红圆角块 + 白字，其余只显示灰色数字。
struct ExploreRankBadge: View {
    @ThemePalette private var palette
    let rank: Int
    var size: CGFloat = 20

    var body: some View {
        Text("\(rank)")
            .appFont(.system(size: rank <= 3 ? 12 : 13, weight: .bold))
            .foregroundStyle(rank <= 3 ? .white : palette.secondary)
            .frame(width: size, height: size)
            .background {
                if rank <= 3 {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(ExploreStyle.hot.opacity(0.9))
                }
            }
    }
}

/// 榜单里紧跟标题的序号（没有色块，只有颜色）。
struct ExploreRankNumber: View {
    @ThemePalette private var palette
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .appFont(.system(size: 14, weight: .bold))
            .foregroundStyle(rank <= 3 ? ExploreStyle.hot : palette.secondary)
            .frame(width: 15, alignment: .leading)
    }
}

/// 探索页统一封面：内存 + 磁盘缓存、按书源请求头下载。
struct ExploreCover: View {
    let book: Book

    var body: some View {
        DiscoverCoverImage(url: BookCoverLocation.url(for: book), origin: book.origin)
            .clipShape(RoundedRectangle(cornerRadius: ExploreStyle.innerRadius, style: .continuous))
    }
}

/// 把「更多」等导航包一层，行内容自己决定排版。
struct ExploreBookLink<Content: View>: View {
    let book: Book
    private let content: Content

    init(book: Book, @ViewBuilder content: () -> Content) {
        self.book = book
        self.content = content()
    }

    var body: some View {
        NavigationLink {
            BookDetailView(book: book)
        } label: {
            content
        }
        .buttonStyle(.plain)
    }
}

/// 推荐语：引号（“…” / 「…」 / 『…』）里的片段换蓝色。
struct ExploreReasonText: View {
    @ThemePalette private var palette
    let reason: String
    var size: CGFloat = 14

    var body: some View {
        text
            .appFont(.system(size: size))
            .lineLimit(2)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
    }

    private var text: Text {
        ExploreReasonFormat.segments(reason).reduce(Text("")) { partial, segment in
            partial + Text(segment.text)
                .foregroundColor(segment.highlighted ? ExploreStyle.link : palette.secondary)
        }
    }
}

/// 加载中 / 失败 / 空态的统一占位。
struct ExploreStateRow: View {
    @ThemePalette private var palette
    let loading: Bool
    let failed: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if failed {
                Text("加载失败").appFont(.footnote).foregroundStyle(palette.secondary)
                if let onRetry {
                    Button("重试", action: onRetry)
                        .appFont(.footnote.weight(.semibold))
                }
            } else {
                if loading { ProgressView().controlSize(.small) }
                Text(loading ? "加载中…" : "暂无内容")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

// MARK: - 文本工具

enum ExploreBookText {
    static func intro(_ book: Book) -> String? {
        DiscoverRankRow.intro(book)
    }

    static func kind(_ book: Book) -> String? {
        let value = (book.kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func meta(_ book: Book) -> String? {
        ExploreFormat.metaLine(kind: book.kind, wordCount: book.wordCount)
    }

    /// 每本书自己的标签优先；没有（AI 还没写入）时用板块的兜底标签。
    static func tags(_ book: Book, fallback: [String]) -> [String] {
        let own = ExploreMetaStore.tags(for: book.bookUrl)
        return own.isEmpty ? fallback : own
    }

    /// 推荐理由：外部写入的优先，否则用分类拼一句，保证卡片不空。
    static func reason(_ book: Book) -> String {
        if let reason = ExploreMetaStore.reason(for: book.bookUrl) { return reason }
        if let kind = kind(book) { return "这本「\(kind)」佳作，也许正合你口味" }
        return "为你挑的这本书，也许正合你口味"
    }
}

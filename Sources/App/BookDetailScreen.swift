import SwiftUI
import UIKit

/// Presentation only: the caller owns navigation, loading and all mutations.
///
/// 版式对齐参考图（「作品详情」）：
/// 1) 封面 + 书名/作者/彩色标签  2) 开始阅读 + 加入书架  3) 分组 / 类型 / 更新 三栏
/// 4) 简介（超过 4 行可展开）     5) 目录                6) 来源 + 换源
struct BookDetailScreen: View {
    @ThemePalette private var palette
    let book: Book
    let onShelf: Bool
    let category: String
    let chapters: [BookChapter]
    let loading: Bool
    let message: String?
    /// 「类型」栏：文本 / 音频 / 漫画 / 文件 / 视频（由书源类型决定，缺省按文本）。
    let sourceType: String
    let onBack: () -> Void
    let onMore: () -> Void
    let onRead: () -> Void
    let onCategory: () -> Void
    let onSource: () -> Void
    let onShelfAction: () -> Void
    let onEditIntro: () -> Void
    let onTOC: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// 长简介默认收起 4 行，点「展开全文」再看全。
    @State private var introExpanded = false

    init(book: Book, onShelf: Bool, category: String, chapters: [BookChapter],
         loading: Bool, message: String?, sourceType: String = "文本",
         onBack: @escaping () -> Void,
         onMore: @escaping () -> Void, onRead: @escaping () -> Void,
         onCategory: @escaping () -> Void, onSource: @escaping () -> Void,
         onShelfAction: @escaping () -> Void, onEditIntro: @escaping () -> Void,
         onTOC: @escaping () -> Void) {
        self.book = book
        self.onShelf = onShelf
        self.category = category
        self.chapters = chapters
        self.loading = loading
        self.message = message
        self.sourceType = sourceType
        self.onBack = onBack
        self.onMore = onMore
        self.onRead = onRead
        self.onCategory = onCategory
        self.onSource = onSource
        self.onShelfAction = onShelfAction
        self.onEditIntro = onEditIntro
        self.onTOC = onTOC
    }

    private var hasStarted: Bool {
        book.durChapterIndex > 0 || book.durChapterPos > 0 || nonempty(book.durChapterTitle) != nil
    }
    private var readableChapters: [BookChapter] { chapters.filter { !$0.isVolume } }
    private var kindTags: [String] {
        var seen = Set<String>()
        return (book.kind ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",，、;；|｜/\n\r\t"))
            .compactMap { nonempty($0) }
            .filter { seen.insert($0).inserted }
    }
    private var categoryText: String { nonempty(category) ?? "未分类" }
    private var sourceText: String {
        if let name = nonempty(book.originName) { return name }
        return book.origin == "local" ? "本地书籍" : "未知来源"
    }
    /// 「更新」栏：只有目录里真带了章节更新时间才显示日期，否则如实写「未知」。
    private var updateText: String {
        guard let raw = nonempty(readableChapters.last?.updateTime) else { return "未知" }
        return Self.shortDate(raw)
    }
    private var intro: BookIntro? { BookIntro.parse(book.intro) }
    private var introIsCollapsible: Bool {
        guard let intro, !intro.kind.isRich else { return false }
        return intro.plainText.count > 85
    }

    var body: some View {
        VStack(spacing: 12) {
            navigationHeader
            ScrollView {
                VStack(spacing: 12) {
                    summaryCard
                    actionRow
                    infoStrip
                    introCard
                    tocCard
                    sourceCard
                    feedback
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    // MARK: - 顶栏

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            navigationButton("返回", symbol: "chevron.left", id: "detail.back", action: onBack)
            Text("书籍详情")
                .appFont(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            navigationButton("更多", symbol: "ellipsis", id: "detail.more", action: onMore)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func navigationButton(_ title: String, symbol: String, id: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .frame(width: 46, height: 46)
                .modifier(ShelfGlass(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    // MARK: - 封面 / 书名 / 标签

    private var summaryCard: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    cover
                    metadata
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    cover
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .modifier(DetailCardSurface())
    }

    private var cover: some View {
        ShelfCoverImage(url: BookCoverLocation.url(for: book), origin: book.origin)
            .frame(width: 100, height: 145)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(false)
            .accessibilityLabel("封面：" + book.name)
            .accessibilityIdentifier("detail.cover")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(book.name)
                .appFont(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detail.title")
            Label(nonempty(book.author) ?? "作者未知", systemImage: "person.fill")
                .appFont(.subheadline)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.author")
            DetailTagLayout(spacing: 7) {
                if let wordCount = nonempty(book.wordCount) {
                    tag(wordCount, tone: .accent).accessibilityIdentifier("detail.wordCount")
                }
                tag(categoryText, tone: .accent).accessibilityIdentifier("detail.category")
                tag(hasStarted ? "在读" : "未读", tone: hasStarted ? .green : .muted)
                    .accessibilityIdentifier("detail.status")
            }
            if !kindTags.isEmpty {
                DetailTagLayout(spacing: 7) {
                    ForEach(kindTags, id: \.self) { tag($0, tone: .purple) }
                }
            }
        }
    }

    /// 彩色胶囊标签：浅色底 + 同色文字（参考图里字数/分类是蓝、状态是绿、题材是紫）。
    private func tag(_ text: String, tone: DetailTagTone) -> some View {
        let color = tone.color(palette)
        return Text(text)
            .appFont(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - 开始阅读 / 加入书架

    private var actionRow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    readButton
                    shelfButton
                }
            } else {
                HStack(spacing: 10) {
                    readButton
                    shelfButton.fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var readButton: some View {
        Button(action: onRead) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(hasStarted ? "继续阅读" : "开始阅读")
                    .appFont(.headline)
                    .lineLimit(1)
            }
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(palette.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.read")
    }

    private var shelfButton: some View {
        Button(action: onShelfAction) {
            HStack(spacing: 6) {
                Image(systemName: onShelf ? "minus" : "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text(onShelf ? "移除书架" : "加入书架")
                    .appFont(.headline)
                    .lineLimit(1)
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
            .background(Capsule().fill(palette.surface))
            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.35), lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(onShelf ? "移除书架" : "加入书架")
        .accessibilityIdentifier("detail.shelfAction")
    }

    // MARK: - 分组 / 类型 / 更新

    private var infoStrip: some View {
        HStack(spacing: 0) {
            infoColumn(icon: "folder.fill", title: "分组", value: categoryText,
                       valueID: "detail.group.value", id: "detail.changeCategory", action: onCategory)
            stripDivider
            infoColumn(icon: "doc.text.fill", title: "类型", value: sourceType,
                       valueID: "detail.type.value", id: nil, action: nil)
            stripDivider
            infoColumn(icon: "bell.fill", title: "更新", value: updateText,
                       valueID: "detail.update.value", id: nil, action: nil)
        }
        .modifier(DetailCardSurface(padding: 14))
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(width: 1, height: 46)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func infoColumn(icon: String, title: String, value: String,
                            valueID: String, id: String?, action: (() -> Void)?) -> some View {
        let content = VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(palette.accent)
            Text(title)
                .appFont(.subheadline)
                .foregroundStyle(palette.primary)
            Text(value)
                .appFont(.caption)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityIdentifier(valueID)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())

        if let action, let id {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityIdentifier(id)
        } else {
            content
        }
    }

    // MARK: - 简介

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("简介")
                .appFont(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            introBody
            if introIsCollapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { introExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(introExpanded ? "收起" : "展开全文")
                        Image(systemName: introExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .appFont(.subheadline.weight(.medium))
                    .foregroundStyle(palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.introExpand")
            }
            // Book.origin == "local" is the persisted imported-book marker.
            // Source books remain read-only, including after joining the shelf.
            if book.origin == "local" {
                Button(action: onEditIntro) {
                    Label("编辑简介", systemImage: "square.and.pencil")
                        .appFont(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.editIntro")
            }
        }
        .modifier(DetailCardSurface())
    }

    /// 书源简介可以是 `<useweb>`／`<usehtml>` 包裹的 HTML（原版用 WebView 渲染，支持 CSS），
    /// 其余按纯文本显示。
    @ViewBuilder
    private var introBody: some View {
        if let intro, intro.kind.isRich {
            RichIntroWebView(html: intro.renderBody,
                             textColor: palette.primary,
                             secondaryColor: palette.secondary,
                             height: $richIntroHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: max(richIntroHeight, 1))
                .accessibilityIdentifier("detail.intro")
        } else {
            let text = intro?.plainText ?? ""
            Text(text.isEmpty ? "暂无简介" : text)
                .appFont(.body)
                .foregroundStyle(text.isEmpty ? palette.secondary : palette.primary)
                .lineSpacing(7)
                .lineLimit(introIsCollapsible && !introExpanded ? 4 : nil)
                .fixedSize(horizontal: false, vertical: introIsCollapsible && !introExpanded)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.intro")
        }
    }

    @State private var richIntroHeight: CGFloat = 0

    // MARK: - 目录

    private var tocCard: some View {
        Button(action: onTOC) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        tocHeading.fixedSize()
                        Spacer(minLength: 0)
                        tocCount.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        tocHeading
                        tocCount
                    }
                }
                if let latest = nonempty(book.lastChapter) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        pill("最新").fixedSize()
                        Text(latest)
                            .appFont(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail.latest")
                    }
                }
                if let updateTime = nonempty(readableChapters.last?.updateTime) {
                    Label("更新于 " + updateTime, systemImage: "clock")
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(DetailCardSurface())
            .contentShape(RoundedRectangle(cornerRadius: palette.cornerRadius(default: 25), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.toc")
        .accessibilityHint("打开章节目录")
    }

    private var tocHeading: some View {
        Label {
            Text("目录").appFont(.title2.weight(.bold))
        } icon: {
            Image(systemName: "list.bullet").foregroundStyle(palette.secondary)
        }
    }

    private var tocCount: some View {
        HStack(spacing: 3) {
            // Empty input can mean the catalog has not loaded. Do not claim zero.
            if !readableChapters.isEmpty {
                Text("共 \(readableChapters.count) 章")
                    .accessibilityIdentifier("detail.count")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
        }
        .appFont(.subheadline)
        .foregroundStyle(palette.accent)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .appFont(.caption)
            .foregroundStyle(palette.accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(palette.accent.opacity(0.12)))
    }

    // MARK: - 来源

    private var sourceCard: some View {
        Button(action: onSource) {
            VStack(alignment: .leading, spacing: 9) {
                Label("来源", systemImage: "globe")
                    .appFont(.subheadline)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.accent)
                    Text(sourceText)
                        .appFont(.body)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        Text("换源").appFont(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(palette.accent)
                }
            }
            .modifier(DetailCardSurface(padding: 16))
            .contentShape(RoundedRectangle(cornerRadius: palette.cornerRadius(default: 25), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.changeSource")
        .accessibilityHint("选择其他书源")
    }

    // MARK: - 反馈

    @ViewBuilder private var feedback: some View {
        if loading || nonempty(message) != nil {
            HStack(alignment: .top, spacing: 10) {
                if loading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在加载书籍信息")
                }
                if let text = nonempty(message) {
                    Text(text).fixedSize(horizontal: false, vertical: true)
                } else if loading {
                    Text("正在加载…")
                }
            }
            .appFont(.footnote)
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "2026/10/22 21:15:21" / "2026-10-22 21:15" → "10/22"；解析不了就原样返回。
    private static func shortDate(_ raw: String) -> String {
        let head = raw.replacingOccurrences(of: "-", with: "/")
            .split(separator: " ", maxSplits: 1)
            .first.map(String.init) ?? raw
        let parts = head.split(separator: "/")
        if parts.count >= 3, parts[0].count == 4 {
            return "\(parts[1])/\(parts[2])"
        }
        return head
    }
}

// MARK: - 标签配色

private enum DetailTagTone {
    case accent, green, purple, muted

    func color(_ palette: ResolvedAppPalette) -> Color {
        switch self {
        case .accent: return palette.accent
        case .green: return .green
        case .purple: return .purple
        case .muted: return palette.secondary
        }
    }
}

// MARK: - 卡片与标签布局

private struct DetailCardSurface: ViewModifier {
    @ThemePalette private var palette
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: palette.cornerRadius(default: 25), style: .continuous)
                ThemeSurface(shape: shape, isCard: true)
            }
    }
}

/// Intrinsic-width pills wrap without discarding tags or clipping large text.
/// Available since iOS 16; the same measurements drive sizing and placement.
private struct DetailTagLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, item) in arrangement.items.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat?) -> (size: CGSize, items: [CGRect]) {
        let limit = max(0, width ?? .infinity)
        var items: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(natural.width, limit), height: nil))
            if x > 0 && x + size.width > limit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: items.isEmpty ? 0 : y + rowHeight), items)
    }
}

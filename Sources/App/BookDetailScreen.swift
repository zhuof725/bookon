import SwiftUI
import UIKit

/// Presentation only: the caller owns navigation, loading and all mutations.
struct BookDetailScreen: View {
    let book: Book
    let onShelf: Bool
    let category: String
    let chapters: [BookChapter]
    let loading: Bool
    let message: String?
    let onBack: () -> Void
    let onMore: () -> Void
    let onRead: () -> Void
    let onCategory: () -> Void
    let onSource: () -> Void
    let onShelfAction: () -> Void
    let onEditIntro: () -> Void
    let onTOC: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .caption2) private var actionDiameter: CGFloat = 52

    init(book: Book, onShelf: Bool, category: String, chapters: [BookChapter],
         loading: Bool, message: String?, onBack: @escaping () -> Void,
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

    var body: some View {
        VStack(spacing: 12) {
            navigationHeader
            ScrollView {
                VStack(spacing: 16) {
                    primaryCard
                    introCard
                    tocCard
                    feedback
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .foregroundStyle(.primary)
        .background {
            AppPalette.background
                .ignoresSafeArea()
        }
    }

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
                .background {
                    if reduceTransparency {
                        Circle().fill(AppPalette.surface)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private var primaryCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            if typeSize.isAccessibilitySize {
                stackedSummary
            } else {
                HStack(alignment: .top, spacing: 14) {
                    cover
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    readButton(inline: true)
                    secondaryActions
                }
                VStack(spacing: 14) {
                    readButton(inline: false)
                    secondaryActions.frame(maxWidth: .infinity)
                }
            }
        }
        .modifier(DetailCardSurface())
    }

    private var stackedSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            cover
            metadata
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cover: some View {
        ShelfCoverImage(url: nonempty(book.coverUrl).flatMap { URL(string: $0) })
            .frame(width: 100, height: 145)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(false)
            .accessibilityLabel("封面：" + book.name)
            .accessibilityIdentifier("detail.cover")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.name)
                .appFont(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detail.title")
            Label(nonempty(book.author) ?? "作者未知", systemImage: "person.fill")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.author")
            DetailTagLayout(spacing: 7) {
                if let wordCount = nonempty(book.wordCount) {
                    pill(wordCount).accessibilityIdentifier("detail.wordCount")
                }
                pill(nonempty(category) ?? "未分类").accessibilityIdentifier("detail.category")
                pill(hasStarted ? "在读" : "未读")
                    .accessibilityIdentifier("detail.status")
            }
            if !kindTags.isEmpty {
                DetailTagLayout(spacing: 7) {
                    ForEach(kindTags, id: \.self) { tag in pill(tag) }
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .appFont(.caption)
            .foregroundStyle(AppPalette.accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppPalette.selection, in: Capsule())
    }

    private func readButton(inline: Bool) -> some View {
        Button(action: onRead) {
            Label(hasStarted ? "继续阅读" : "开始阅读", systemImage: "book")
                .appFont(.headline)
                .fixedSize(horizontal: inline, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                .background(scheme == .dark ? Color.white : Color(white: 0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.read")
    }

    private var secondaryActions: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { actionControls }
            } else {
                HStack(spacing: 7) { actionControls }
            }
        }
    }

    @ViewBuilder private var actionControls: some View {
        actionButton("切换类型", symbol: "arrow.left.arrow.right", id: "detail.changeCategory", action: onCategory)
        actionButton("换源", symbol: "arrow.triangle.2.circlepath", id: "detail.changeSource", action: onSource)
        actionButton(onShelf ? "移除书架" : "加入书架", symbol: onShelf ? "minus.circle" : "plus.circle",
                     id: "detail.shelfAction", action: onShelfAction)
    }

    private func actionButton(_ title: String, symbol: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    Label(title, systemImage: symbol)
                        .appFont(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(AppPalette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).appFont(.caption2).fixedSize()
                    }
                    .frame(width: actionDiameter, height: actionDiameter)
                    .background(AppPalette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("简介")
                .appFont(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(nonempty(book.intro) ?? "暂无简介")
                .appFont(.body)
                .foregroundStyle(nonempty(book.intro) == nil ? Color.secondary : Color.primary)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.intro")
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
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.editIntro")
            }
        }
        .modifier(DetailCardSurface())
    }

    private var tocCard: some View {
        Button(action: onTOC) {
            VStack(alignment: .leading, spacing: 14) {
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
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(DetailCardSurface())
            .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.toc")
        .accessibilityHint("打开章节目录")
    }

    private var tocHeading: some View {
        Label {
            Text("目录").appFont(.title2.weight(.bold))
        } icon: {
            Image(systemName: "list.bullet").foregroundStyle(.secondary)
        }
    }

    private var tocCount: some View {
        HStack(spacing: 5) {
            // Empty input can mean the catalog has not loaded. Do not claim zero.
            if !readableChapters.isEmpty {
                Text("共 \(readableChapters.count) 章")
                    .accessibilityIdentifier("detail.count")
            }
            Image(systemName: "chevron.right").accessibilityHidden(true)
        }
        .appFont(.subheadline)
        .foregroundStyle(AppPalette.accent)
        .fixedSize(horizontal: false, vertical: true)
    }

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
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DetailCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(AppPalette.surface)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.025), radius: 14, x: 0, y: 6)
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

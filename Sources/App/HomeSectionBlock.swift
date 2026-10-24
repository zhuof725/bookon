import SwiftUI

/// 首页上的一个板块。
///
/// **为什么必须是一个独立 View**：之前它写成 `CustomDiscoverView` 里的一个方法，
/// 方法体里读 `section.books` 不会建立对 `DiscoverSectionModel` 的订阅——
/// `@Published` 只有被 `body` 直接观察时才会触发重绘。结果就是下拉刷新
/// 数据确实换了，界面却不更新，看着像「刷新没用」。
///
/// 现在用 `@ObservedObject` 持有模型，书籍一变这一块就自己重画。
struct HomeSectionBlock: View {
    @ThemePalette private var palette
    @ObservedObject var section: DiscoverSectionModel
    let history: [HistoryItem]
    var onMore: () -> Void
    var onSelectBook: (Book) -> Void
    var onSelectHistory: (HistoryItem) -> Void
    var onRetry: () -> Void
    var identity: DeckIdentity?
    var multiKinds: [MultiRankKind]
    var source: BookSource?

    var body: some View {
        if section.kind == .history {
            DiscoverTemplateView(
                kind: .history,
                title: section.title,
                moreTitle: "全部",
                history: history,
                count: section.count,
                onMore: onMore,
                onSelectHistory: onSelectHistory
            )
        } else if section.failed {
            failedRow
        } else if section.books.isEmpty && section.loading {
            loadingRow
        } else {
            DiscoverTemplateView(
                kind: section.kind,
                title: section.title,
                moreTitle: "全部",
                books: section.books,
                cards: section.cards,
                count: section.count,
                scale: section.entry.scale,
                corner: section.entry.corner,
                showNumber: section.entry.showNumber,
                onMore: onMore,
                onSelectBook: onSelectBook,
                identity: identity,
                multiKinds: multiKinds,
                source: source
            )
        }
    }

    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("加载中…")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var failedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                Text(section.errorText ?? "加载失败")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                Button("重试", action: onRetry)
                    .appFont(.system(size: 12, weight: .semibold))
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var header: some View {
        HStack {
            Text(section.title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
            Spacer()
        }
    }
}

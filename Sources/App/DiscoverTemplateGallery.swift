import SwiftUI

// MARK: - 模板画廊

/// 模板菜单：一行一个，显示名称、说明、需要什么数据。
struct DiscoverTemplateGallery: View {
    @ThemePalette private var palette
    var onPick: (DiscoverTemplateKind) -> Void = { _ in }

    var body: some View {
        List {
            Section {
                ForEach(DiscoverTemplate.all) { template in
                    Button { onPick(template.kind) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(template.kind))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.title).appFont(.headline)
                                Text(template.detail)
                                    .appFont(.caption)
                                    .foregroundStyle(palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("template.pick.\(template.kind.rawValue)")
                }
            } header: {
                Text("板块模板")
            } footer: {
                Text("每个模板是一种把书源分类排成板块的方式。选一个即可，之后可以随时换。")
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    private func icon(_ kind: DiscoverTemplateKind) -> String {
        switch kind {
        case .badgeGrid: return "square.grid.2x2"
        case .covers: return "rectangle.split.3x1"
        case .rankRow: return "list.number"
        case .waterfall: return "rectangle.grid.2x2"
        case .curve: return "rectangle.on.rectangle.angled"
        case .fan: return "fan.fill"
        case .deck: return "square.stack.3d.down.right"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - 单模板预览

/// 只渲染一个模板，用于设置里的「预览」和调试。
/// 不加载网络：传入什么就画什么。
struct DiscoverTemplatePreview: View {
    @ThemePalette private var palette
    let kind: DiscoverTemplateKind

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(kind.title).appFont(.headline)
                Text(kind.detail)
                    .appFont(.caption2)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            DiscoverTemplateView(
                kind: kind,
                title: "预览",
                moreTitle: "全部",
                books: Self.sampleBooks,
                history: Self.sampleHistory,
                count: 9
            )
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
    }

    // MARK: 预览用的假数据

    static let sampleBooks: [Book] = {
        let names = ["蛊道修仙", "模拟系统流", "牛马踢英超", "寒门逆袭",
                     "精灵极恶", "外企重生", "从花少2开始", "我能看到",
                     "盗墓笔记", "道士不好惹", "剑来", "诡秘之主"]
        let authors = ["青山道长", "夜半钟声", "老K", "沈砚", "云中客", "陈默",
                       "林小满", "周白", "南派三叔", "骨头", "烽火戏诸侯", "爱潜水的乌贼"]
        return names.enumerated().map { index, name in
            var book = Book(bookUrl: "preview://\(index)", name: name, origin: "preview")
            book.author = authors[index]
            return book
        }
    }()

    static let sampleHistory: [HistoryItem] = [
        HistoryItem(id: "h1", title: "盗墓笔记",
                    chapterText: "读到 第 128 章 · 共 520 章",
                    progress: 128.0 / 520.0, timeText: "今天",
                    actionText: "继续阅读"),
        HistoryItem(id: "h2", title: "道士不好惹",
                    chapterText: "读到 第 47 章 · 共 310 章",
                    progress: 47.0 / 310.0, timeText: "昨天",
                    actionText: "继续阅读"),
        HistoryItem(id: "h3", title: "剑来",
                    chapterText: "读到 第 902 章 · 共 1180 章",
                    progress: 902.0 / 1180.0, timeText: "3 天前",
                    actionText: "继续阅读"),
        HistoryItem(id: "h4", title: "诡秘之主",
                    chapterText: "读到 第 1 章 · 共 1432 章",
                    progress: 0, timeText: "上周",
                    actionText: "从头开始")
    ]
}

// MARK: - 全部模板一览（调试用）

/// 一页看完所有模板，方便对比。只用于调试，不进正式导航。
struct DiscoverTemplateGalleryPreview: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(DiscoverTemplate.all) { template in
                    DiscoverTemplatePreview(kind: template.kind)
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
    }
}

// MARK: - 「全部」页

/// 某个板块的全部内容：不限数量，用同一套模板继续往下渲染。
///
/// 传 `count: DiscoverTemplate.unlimited`，模板内部不截断，
/// 列表类模板（瀑布流 / 横滑 / 竖排）会一直往下铺；
/// 卡片类模板（弧形 / 扇形 / 堆叠）本身是翻看交互，按实际数量自己排。
struct DiscoverTemplateFullPage: View {
    @ThemePalette private var palette
    let kind: DiscoverTemplateKind
    let title: String
    let books: [Book]
    var history: [HistoryItem] = []
    var onSelectBook: (Book) -> Void = { _ in }
    var onSelectHistory: (HistoryItem) -> Void = { _ in }

    var body: some View {
        ScrollView {
            DiscoverTemplateView(
                kind: kind,
                title: "",
                moreTitle: "",
                books: books,
                history: history,
                count: DiscoverTemplate.unlimited,
                onMore: nil,
                onSelectBook: onSelectBook,
                onSelectHistory: onSelectHistory
            )
            .padding(.top, 8)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("template.full.\(kind.rawValue)")
    }
}

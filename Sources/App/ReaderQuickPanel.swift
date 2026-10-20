import SwiftUI

/// Reader overflow panel. Callbacks are supplied by the reader; no network work in the view.
struct ReaderQuickPanel: View {
    @ThemePalette private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let book: Book
    let sourceName: String
    let position: String
    var busy = false
    var message: String?
    var enabled: Set<String> = []
    /// 书源已保存登录凭据时，「书源登录」按钮显示为「已登录」。
    var loggedIn = false
    /// 书源 customButton：由书源脚本控制的按钮，点击触发 callBackJs 的 clickCustomButton。
    var customButton = false
    let action: (String) -> Void
    private var items: [(String, String, String)] {
        var list: [(String, String, String)] = [
        ("refresh", "刷新", "arrow.clockwise"),
        ("toc", "刷新目录", "list.bullet"),
        ("clear", "清缓存并刷新", "trash"),
        ("login", "书源登录", "person.crop.circle"),
        ("source", "换源", "arrow.triangle.2.circlepath"),
        ("rules", "替换净化", "wand.and.stars"),
        ("bookmarks", "书签列表", "bookmark"),
        ("browser", "浏览器打开", "safari")
        ]
        if customButton { list.append(("custom", "书源按钮", "hand.tap")) }
        return list
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 18) {
                    BookCoverImage(url: BookCoverLocation.url(for: book), origin: book.origin)
                        .frame(width: 76, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(book.name).appFont(.title3.weight(.semibold)).lineLimit(2)
                        Text(book.author.isEmpty ? "作者未知" : book.author)
                            .appFont(.subheadline).foregroundStyle(palette.secondary)
                        Label(sourceName, systemImage: "network").appFont(.footnote)
                        Label("进度  \(position)", systemImage: "book")
                            .appFont(.footnote).accessibilityIdentifier("reader.quick.position")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 24) {
                    ForEach(items, id: \.0) { item in
                        let done = item.0 == "login" && loggedIn
                        Button { action(item.0) } label: {
                            VStack(spacing: 12) {
                                Image(systemName: done ? "person.crop.circle.badge.checkmark" : item.2)
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundStyle(done ? palette.accent : palette.primary)
                                Text(done ? "已登录" : item.1).appFont(.caption).lineLimit(2).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity, minHeight: 76)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || !enabled.contains(item.0))
                        .opacity(enabled.contains(item.0) ? 1 : 0.4)
                        .accessibilityIdentifier("reader.quick." + item.0)
                    }
                }
                if let message { Text(message).appFont(.footnote).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("reader.quick.status") }
                Text("书签来自长按正文选中文字；清缓存仅作用于当前章节。")
                    .appFont(.caption2).foregroundStyle(palette.secondary)
            }.padding(20)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }
}

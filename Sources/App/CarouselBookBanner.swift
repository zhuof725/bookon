import SwiftUI

/// 顶部轮播：**单张大图**，内容是配置里选定的分类下的书。
///
/// 对应参考图二：一张横版大图铺满，左右露出下一张的边，
/// 底部渐变压暗承载书名与作者。
struct CarouselBookBanner: View {
    @ThemePalette private var palette
    let books: [Book]
    var height: CGFloat = 200

    @State private var index = 0

    private var shown: [Book] { Array(books.prefix(8)) }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(shown.enumerated()), id: \.element.bookUrl) { pair in
                    page(pair.element)
                        .padding(.horizontal, 6)
                        .tag(pair.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)

            if shown.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<shown.count, id: \.self) { i in
                        Capsule()
                            .fill(palette.primary.opacity(i == index ? 0.55 : 0.16))
                            .frame(width: i == index ? 13 : 4, height: 4)
                            .animation(.easeInOut(duration: 0.2), value: index)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 2)
    }

    private func page(_ book: Book) -> some View {
        ZStack(alignment: .bottomLeading) {
            DeckCoverImage(url: BookCoverLocation.url(for: book))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.38),
                    .init(color: .black.opacity(0.42), location: 0.72),
                    .init(color: .black.opacity(0.78), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .appFont(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
                if !book.author.isEmpty {
                    Text(book.author)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

import SwiftUI

/// 顶部大图轮播：模糊背景 + 左文 + 右侧 3D 斜叠封面。
///
/// 按参考图复刻：
/// - 背景是当前封面放大模糊后铺满，再压一层白到页面底色的渐变
/// - 左侧：书名（大字）、来源、简介（最多 4 行）
/// - 右侧：正面一张，后面三张往右上错开、轻微旋转
/// - 底部一条胶囊指示点
struct CarouselBookBanner: View {
    @ThemePalette private var palette
    let books: [Book]
    var height: CGFloat = 232

    @State private var index = 0

    private var shown: [Book] { Array(books.prefix(8)) }
    private var current: Book? {
        shown.indices.contains(index) ? shown[index] : shown.first
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Array(shown.enumerated()), id: \.element.bookUrl) { pair in
                    ZStack(alignment: .top) {
                        background(for: pair.element)
                        content(for: pair.element)
                    }
                    .tag(pair.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            .clipped()

            if shown.count > 1 {
                dots
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: 背景

    private func background(for book: Book) -> some View {
        ZStack {
            // 用当前封面自身做背景：放大 + 高斯模糊
            DeckCoverImage(url: coverURL(book))
                .blur(radius: 42, opaque: true)
                .scaleEffect(1.5)
                .opacity(0.55)

            // 压白：顶部略透，往下逐渐过渡到页面底色
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.55), location: 0.0),
                    .init(color: Color.white.opacity(0.72), location: 0.45),
                    .init(color: Color.white.opacity(0.94), location: 0.82),
                    .init(color: Color.white, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: 前景

    private func content(for book: Book) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 左：文字
            VStack(alignment: .leading, spacing: 0) {
                Text(book.name)
                    .appFont(.system(size: 27, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                if !book.author.isEmpty {
                    Text(book.author)
                        .appFont(.system(size: 14))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .padding(.top, 10)
                }

                if let intro = introText(for: book) {
                    Text(intro)
                        .appFont(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .lineSpacing(3.5)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 9)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右：3D 斜叠封面
            coverStack(for: book, at: index)
                .frame(width: 154, height: 172)
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .padding(.top, 14)
        .frame(height: height, alignment: .top)
    }

    private func introText(for book: Book) -> String? {
        guard let raw = book.intro else { return nil }
        let parsed = BookIntro.parse(raw)?.plainText
            ?? raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let trimmed = parsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 正面一张 + 后面三张往右上错开，形成「一摞」。
    private func coverStack(for book: Book, at base: Int) -> some View {
        ZStack {
            // 从最后一张往前画，越前面越靠上
            ForEach(Array((0..<3).reversed()), id: \.self) { layer in
                stackCard(layer: layer + 1, base: base, current: book)
            }
            stackCard(layer: 0, base: base, current: book)
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
        }
        .frame(width: 154, height: 172, alignment: .center)
    }

    /// layer 0 = 正面，1/2/3 = 后面的层。
    private func stackCard(layer: Int, base: Int, current: Book) -> some View {
        let step = CGFloat(layer)
        // 越靠后：越往右上、越小、越暗
        let dx = step * 7
        let dy = step * -11
        let scale = 1 - step * 0.035
        let side = 132 * scale

        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(uiColor: .secondarySystemFill))
            .frame(width: side, height: side)
            .overlay {
                DeckCoverImage(url: coverURL(bookAt(layer: layer, base: base, current: current)))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .overlay {
                // 后面的层压一点白色，做出「被挡住」的感觉
                if layer > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(layer == 0 ? 0.9 : 0.5),
                                  lineWidth: layer == 0 ? 2.5 : 1)
            }
            .rotationEffect(.degrees(Double(layer) * 1.6))
            .offset(x: dx, y: dy)
            .zIndex(-Double(layer))
    }

    /// 叠在后面的封面：取当前之后的第 N 本，循环取。
    private func bookAt(layer: Int, base: Int, current: Book) -> Book? {
        guard !shown.isEmpty else { return nil }
        if layer == 0 { return current }
        return shown[(base + layer) % shown.count]
    }

    private func coverURL(_ book: Book?) -> URL? {
        guard let book else { return nil }
        return BookCoverLocation.url(for: book)
    }

    // MARK: 指示点

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<shown.count, id: \.self) { i in
                Capsule()
                    .fill(palette.primary.opacity(i == index ? 0.42 : 0.14))
                    .frame(width: i == index ? 17 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay {
            // 透明层接管横向拖拽，避免只靠 TabView 点不到
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > 30 else { return }
                            let next = index + (value.translation.width < 0 ? 1 : -1)
                            guard shown.indices.contains(next) else { return }
                            withAnimation(.easeInOut(duration: 0.25)) { index = next }
                        }
                )
        }
        .allowsHitTesting(true)
    }
}

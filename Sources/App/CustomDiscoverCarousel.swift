import SwiftUI

// MARK: - 顶部轮播

/// 顶部轮播：每个分类一屏，左文右图，右侧三张封面错开成「一摞」。
///
/// 数据来自分类下第一个板块的前三本书封面；分类没有板块时退回占位色。
struct CustomDiscoverCarousel: View {
    @ThemePalette private var palette
    let pages: [CustomDiscoverHero]
    @Binding var index: Int

    private let height: CGFloat = 186

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { pair in
                    page(pair.element)
                        .tag(pair.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)

            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(palette.primary.opacity(i == index ? 0.58 : 0.16))
                            .frame(width: i == index ? 15 : 5, height: 5)
                            .animation(.easeInOut(duration: 0.2), value: index)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func page(_ hero: CustomDiscoverHero) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(hero.title)
                    .appFont(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !hero.subtitle.isEmpty {
                    Text(hero.subtitle)
                        .appFont(.system(size: 13.5))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                if !hero.detail.isEmpty {
                    Text(hero.detail)
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(palette.secondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stack(hero.covers)
                .frame(width: 150, height: 150)
        }
        .padding(.horizontal, 20)
        .frame(height: height, alignment: .top)
    }

    private func stack(_ covers: [URL?]) -> some View {
        var slots = covers
        while slots.count < 3 { slots.append(nil) }
        let side: CGFloat = 150
        return ZStack {
            card(slots[2]).frame(width: side * 0.86, height: side * 0.86)
                .rotationEffect(.degrees(6))
                .offset(x: side * 0.03, y: -side * 0.04)
                .opacity(0.55)
            card(slots[1]).frame(width: side * 0.92, height: side * 0.92)
                .rotationEffect(.degrees(3))
                .offset(x: side * 0.02, y: -side * 0.02)
                .opacity(0.8)
            card(slots[0]).frame(width: side, height: side)
                .shadow(color: .black.opacity(0.16), radius: 11, x: 0, y: 5)
        }
    }

    private func card(_ url: URL?) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(uiColor: .secondarySystemFill))
            .overlay {
                DeckCoverImage(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.5)
            }
    }
}

/// 轮播一屏的数据。
struct CustomDiscoverHero: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var detail: String
    var covers: [URL?]
}

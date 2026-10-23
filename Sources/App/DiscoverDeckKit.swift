import SwiftUI

// MARK: - 卡片壳（三种布局共用）

/// 一张竖版卡片：封面 + 可选角标 + 底部渐变书名条。
private struct DeckCard<Content: View>: View {
    let radius: CGFloat
    let showCaption: Bool
    let title: String
    let number: Int?
    let content: Content

    init(radius: CGFloat = 10,
         showCaption: Bool = true,
         title: String,
         number: Int? = nil,
         @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.showCaption = showCaption
        self.title = title
        self.number = number
        self.content = content()
    }

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if showCaption {
                    VStack {
                        Spacer(minLength: 0)
                        Text(title)
                            .appFont(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7)
                            .padding(.top, 14)
                            .padding(.bottom, 7)
                            .background(
                                LinearGradient(colors: [.clear, .black.opacity(0.62), .black.opacity(0.82)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let number {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 19)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(7)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            }
            // 阴影半径压到 6：大半径 + 3D 旋转会让 Core Animation 每帧重算离屏层，
            // 一排卡片滑动时就是明显的掉帧。
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            .contentShape(Rectangle())
    }
}

// MARK: - 错位瀑布流

/// 双列不等高瀑布流：每本书按序丢进「当前更矮」的那一列，
/// 封面高度在 3:4 与 1:1 之间交替，形成错落感。
struct DiscoverWaterfallSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    /// 卡片宽度倍率 / 圆角 / 是否显示序号
    var scale: Double = 1
    var corner: Double = 8
    var showNumber = true
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    /// 每 3 本里第 1、3 本是竖版，第 2 本是方形——固定节奏比随机更稳，滚动时不会忽大忽小乱跳。
    private func isSquare(_ index: Int) -> Bool { index % 3 == 1 }

    /// 分列结果：两列各自的 (原始索引, 条目)。
    ///
    /// 用 struct 而不是元组 + @State：元组不满足 Equatable，而且
    /// `ForEach(Array([split.left, split.right].enumerated())...)` 这种写法
    /// 会让类型检查器在 @State 上打转，Swift 6.2 直接崩在 recordOpenedType。
    struct WaterfallColumns: Equatable {
        var left: [Entry] = []
        var right: [Entry] = []

        struct Entry: Identifiable, Equatable {
            let index: Int
            let item: DeckItem
            var id: String { item.id }
        }

        var all: [[Entry]] { [left, right] }
    }

    /// 只在 items 变化时重算一次，滚动时直接用缓存。
    private func columns(for items: [DeckItem]) -> WaterfallColumns {
        var result = WaterfallColumns()
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for (index, item) in items.enumerated() {
            let coverRatio: CGFloat = isSquare(index) ? 1.0 : 0.75
            let estimated = coverRatio * 100 + 46
            let entry = WaterfallColumns.Entry(index: index, item: item)
            if leftHeight <= rightHeight {
                result.left.append(entry)
                leftHeight += estimated
            } else {
                result.right.append(entry)
                rightHeight += estimated
            }
        }
        return result
    }

    /// 以 items 为键缓存分列结果，items 不变就不重算。
    @State private var cached: WaterfallColumns = WaterfallColumns()
    /// 用 Optional 而不是 0：0 可能和真实 key 撞上，导致首帧不计算、页面空白。
    @State private var cachedKey: Int?

    private func refreshColumnsIfNeeded(force: Bool = false) {
        let key = items.count ^ (items.first?.id.hashValue ?? 0)
        guard force || key != cachedKey else { return }
        cachedKey = key
        cached = columns(for: items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<2, id: \.self) { column in
                    LazyVStack(spacing: 14) {
                        ForEach(cached.all[column]) { entry in
                            Button { onSelect(entry.item, entry.index) } label: {
                                cell(entry.item, index: entry.index)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("waterfall.item.\(entry.item.id)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .onAppear { refreshColumnsIfNeeded(force: true) }
        .onChange(of: items) { _, _ in refreshColumnsIfNeeded() }
    }

    private func cell(_ item: DeckItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(isSquare(index) ? 1.0 : 3.0 / 4.0, contentMode: .fit)
                .overlay { DeckCoverImage(url: item.cover) }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 7, x: 0, y: 4)

            Text(item.title)
                .appFont(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.caption.isEmpty {
                Text(item.caption)
                    .appFont(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onMore {
                Button(action: onMore) {
                    Text(moreTitle)
                        .appFont(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        }
    }
}

// MARK: - 三种基础布局

/// 两列大封面 + 左下角大号序号。数量多时按行往下铺。
struct DiscoverBadgeGridSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    /// 卡片宽度倍率 / 圆角 / 是否显示序号
    var scale: Double = 1
    var corner: Double = 8
    var showNumber = true
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    /// 卡片越大列数越少：1.0 → 2 列，0.8 以下 → 3 列，1.3 以上 → 1 列（大图）。
    private var columns: Int {
        switch scale {
        case ..<0.8: return 3
        case 1.3...: return 1
        default: return 2
        }
    }

    private var radius: CGFloat { CGFloat(max(corner, 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                                     count: columns),
                      alignment: .leading,
                      spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    Button { onSelect(pair.element, pair.offset) } label: {
                        card(pair.element, number: pair.offset + 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("badge.item.\(pair.element.id)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func card(_ item: DeckItem, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { DeckCoverImage(url: item.cover) }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if showNumber {
                        Text(String(format: "%02d", max(number, 1)))
                            .font(.system(size: columns == 1 ? 52 : 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
                            .padding(.leading, 8)
                            .padding(.bottom, 2)
                            .allowsHitTesting(false)
                    }
                }

            Text(item.title)
                .appFont(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.caption.isEmpty {
                Text(item.caption)
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onMore {
                Button(action: onMore) {
                    Text(moreTitle)
                        .appFont(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        }
    }
}

/// 一行横滑封面，露出下一张的边缘。
struct DiscoverCoversSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    /// 卡片宽度倍率 / 圆角 / 是否显示序号
    var scale: Double = 1
    var corner: Double = 8
    var showNumber = true
    /// 基础宽度，实际宽度 = width * scale
    var width: CGFloat = 108

    private var cardWidth: CGFloat { max(64, width * CGFloat(min(max(scale, 0.6), 1.6))) }
    private var radius: CGFloat { CGFloat(max(corner, 0)) }
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                        Button { onSelect(pair.element, pair.offset) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Color.clear
                                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                    .overlay { DeckCoverImage(url: pair.element.cover) }
                                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                                Text(pair.element.title)
                                    .appFont(.system(size: 13, weight: .medium))
                                    .foregroundStyle(palette.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !pair.element.caption.isEmpty {
                                    Text(pair.element.caption)
                                        .appFont(.system(size: 11))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("covers.item.\(pair.element.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onMore {
                Button(action: onMore) {
                    Text(moreTitle)
                        .appFont(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        }
    }
}

/// 竖排排名横条：序号徽章 + 封面 + 书名 / 作者。
struct DiscoverRankRowSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    /// 卡片宽度倍率 / 圆角 / 是否显示序号
    var scale: Double = 1
    var corner: Double = 8
    var showNumber = true

    private var coverW: CGFloat { max(40, 52 * CGFloat(min(max(scale, 0.6), 1.6))) }
    private var coverH: CGFloat { coverW * 1.35 }
    private var radius: CGFloat { CGFloat(max(corner, 0)) }
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    Button { onSelect(pair.element, pair.offset) } label: {
                        row(pair.element, rank: pair.offset + 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rank.item.\(pair.element.id)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func row(_ item: DeckItem, rank: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .appFont(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(rank <= 3 ? palette.accent : palette.secondary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Color.clear
                .frame(width: 52, height: 70)
                .overlay { DeckCoverImage(url: item.cover) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .appFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                if !item.caption.isEmpty {
                    Text(item.caption)
                        .appFont(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onMore {
                Button(action: onMore) {
                    Text(moreTitle)
                        .appFont(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        }
    }
}

// MARK: - 通用横向卡片轨道

/// 一行可以左右滑的卡片：**交给原生横向 ScrollView**，不再自己接管 DragGesture。
///
/// 为什么要换成 ScrollView：
///  - 手指落在封面上往下滑时，自定义 DragGesture 会把这次触摸判成「横向翻卡」，
///    外层竖向 ScrollView 就收不到，页面卡住不动；
///  - 原生滚动由 UIScrollView 驱动，逐帧跟手、有惯性、有吸附，比手动改 offset 顺得多。
///
/// 卡片之间的 3D 弧度、缩放、上下错位全部按「离中心几格」逐帧算：
/// 滑动时 offset 每帧更新，卡片跟着连续变化，不是松手才跳一下。
struct DeckCarousel<Card: View>: View {
    let count: Int
    /// 卡片本体宽度
    let cardWidth: CGFloat
    /// 相邻两张卡的水平间距（小于卡宽就有叠压效果）
    let step: CGFloat
    let stageHeight: CGFloat
    /// 每偏离一格旋转的角度（度）
    var rotation: Double = 19
    /// 每偏离一格缩小的比例
    var scaleStep: Double = 0.055
    /// 每偏离一格下移的点数（弧形走廊靠它弯下去）
    var yStep: CGFloat = 0
    /// 每偏离一格降低的不透明度
    var opacityStep: Double = 0.09
    /// 当前居中的卡片下标（双向绑定：滑动会更新它，设置它会滚过去）
    @Binding var index: Int?
    @ViewBuilder var card: (Int) -> Card

    /// 滚动偏移（pt）。由 ScrollView 内容的位置算出来，逐帧更新。
    @State private var offset: CGFloat = 0

    private var overlap: CGFloat { max(cardWidth - step, 0) }

    var body: some View {
        GeometryReader { proxy in
            let side = max((proxy.size.width - cardWidth) / 2, 0)
            ScrollView(.horizontal) {
                LazyHStack(spacing: -overlap) {
                    ForEach(0..<max(count, 0), id: \.self) { i in
                        card(i)
                            .frame(width: cardWidth)
                            .modifier(CarouselStep(
                                distance: steps(from: i),
                                rotation: rotation,
                                scaleStep: scaleStep,
                                yStep: yStep,
                                opacityStep: opacityStep))
                            .id(i)
                    }
                }
                .scrollTargetLayout()
                .background {
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: CarouselOffsetKey.self,
                            value: side - inner.frame(in: .named(Self.space)).minX)
                    }
                }
            }
            .coordinateSpace(name: Self.space)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollPosition(id: $index)
            .onPreferenceChange(CarouselOffsetKey.self) { value in
                guard abs(value - offset) > 0.2 else { return }
                offset = value
            }
            .frame(height: stageHeight)
        }
        .frame(height: stageHeight)
    }

    private static var space: String { "deck.carousel" }

    /// 第 i 张卡离视口中心差几格：0 = 正中，±1 = 相邻。
    private func steps(from i: Int) -> CGFloat {
        guard step > 0 else { return 0 }
        return offset / step - CGFloat(i)
    }
}

/// 一张卡在轨道里的变换：离中心越远越小、越斜、越靠后。
///
/// 抽成独立的小类型，是为了让 `ForEach` 里那几行别太长——
/// SwiftUI 的类型检查器在超长的 modifier 链上会慢得离谱，甚至超时。
private struct CarouselStep: ViewModifier {
    let distance: CGFloat
    let rotation: Double
    let scaleStep: Double
    let yStep: CGFloat
    let opacityStep: Double

    private var clamped: CGFloat { min(abs(distance), 4) }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - clamped * scaleStep)
            .rotation3DEffect(.degrees(Double(distance) * -rotation),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: .center,
                              perspective: 0.55)
            .offset(y: clamped * yStep)
            .opacity(clamped > 4.4 ? 0 : 1 - clamped * opacityStep)
            // 越靠中心越靠前：两侧的卡压在中间卡后面，不会盖住它
            .zIndex(-Double(clamped))
    }
}

private struct CarouselOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - U2 弧形走廊

/// 卡片沿一条向上弯的弧线排列：中间最大最亮，向两侧逐渐缩小、下移、后退。
/// 只有当前卡显示书名，其余卡不显示文字（避免侧卡挡住名字）。
struct DiscoverCurveSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    @State private var index: Int? = 0

    private let cardWidth: CGFloat = 112
    private let cardHeight: CGFloat = 150
    /// 相邻卡的水平间距
    private let step: CGFloat = 68
    private let stageHeight: CGFloat = 208

    private var current: DeckItem? {
        items.indices.contains(index ?? 0) ? items[index ?? 0] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)

            DeckCarousel(count: items.count,
                         cardWidth: cardWidth,
                         step: step,
                         stageHeight: stageHeight,
                         rotation: 17,
                         scaleStep: 0.055,
                         yStep: 11,
                         opacityStep: 0.09,
                         index: $index) { itemIndex in
                let item = items[itemIndex]
                DeckCard(radius: 10,
                         showCaption: itemIndex == (index ?? 0),
                         title: item.title) {
                    DeckCoverImage(url: item.cover)
                }
                .frame(width: cardWidth, height: cardHeight)
                .onTapGesture { onSelect(item, itemIndex) }
                .accessibilityIdentifier("curve.card.\(item.id)")
            }

            // 当前书名单独放下面，宽度不受卡片限制
            if let current {
                VStack(spacing: 3) {
                    Text(current.title)
                        .appFont(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    if !current.caption.isEmpty {
                        Text(current.caption)
                            .appFont(.system(size: 10.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .animation(.easeInOut(duration: 0.2), value: index)
            }

            if items.count > 1 {
                DeckDots(count: items.count, index: index ?? 0)
                    .padding(.top, 9)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let onMore {
                    Button(action: onMore) {
                        Text(moreTitle)
                            .appFont(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
        }
    }
}

// MARK: - U 卡片堆叠

/// 中央卡在前完整显示，左右各两张向后旋转、缩小、压暗。
/// 侧卡只露边，不承载文字——书名只出现在中央卡上。
struct DiscoverDeckSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    @State private var index: Int? = 0

    private let cardWidth: CGFloat = 124
    private let cardHeight: CGFloat = 166
    private let stageHeight: CGFloat = 224

    private var current: DeckItem? {
        items.indices.contains(index ?? 0) ? items[index ?? 0] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)

            DeckCarousel(count: items.count,
                         cardWidth: cardWidth,
                         step: cardWidth * 0.56,
                         stageHeight: stageHeight,
                         rotation: 19,
                         scaleStep: 0.09,
                         yStep: 0,
                         opacityStep: 0.05,
                         index: $index) { itemIndex in
                let item = items[itemIndex]
                DeckCard(radius: 10,
                         showCaption: itemIndex == (index ?? 0),
                         title: item.title,
                         number: itemIndex == (index ?? 0) ? itemIndex + 1 : nil) {
                    DeckCoverImage(url: item.cover)
                }
                .frame(width: cardWidth, height: cardHeight)
                .onTapGesture { onSelect(item, itemIndex) }
                .accessibilityIdentifier("deck.card.\(item.id)")
            }

            if let current {
                VStack(spacing: 3) {
                    Text(current.title)
                        .appFont(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    if !current.caption.isEmpty {
                        Text(current.caption)
                            .appFont(.system(size: 10.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .animation(.easeInOut(duration: 0.2), value: index)
            }

            if items.count > 1 {
                DeckDots(count: items.count, index: index ?? 0)
                    .padding(.top, 9)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let onMore {
                    Button(action: onMore) {
                        Text(moreTitle)
                            .appFont(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
        }
    }
}

// MARK: - J 观看记录

/// 「继续阅读」板块：大图铺满 + 底部渐变压暗 + 书名 / 进度条 / 最后阅读时间 / 按钮。
/// 数据来自书架里每本书的 durChapterIndex 与 lastReadAt。
struct DiscoverHistorySection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [HistoryItem]
    var onMore: (() -> Void)? = nil
    var onSelect: (HistoryItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !title.isEmpty || onMore != nil {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.primary)
                Spacer(minLength: 8)
                if let onMore {
                    Button(action: onMore) {
                        Text(moreTitle)
                            .appFont(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            }

            if items.isEmpty {
                Text("还没有阅读记录，翻开一本书就会出现在这里。")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(items) { item in
                            Button { onSelect(item) } label: {
                                HistoryCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

private struct HistoryCard: View {
    let item: HistoryItem

    private let width: CGFloat = 150
    private let height: CGFloat = 180

    var body: some View {
        ZStack(alignment: .bottom) {
            DeckCoverImage(url: item.cover)
                .frame(width: width, height: height)
                .clipped()

            // 底部渐变压暗，保证白字可读
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.34), location: 0.55),
                    .init(color: .black.opacity(0.80), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: width, height: height)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .appFont(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.chapterText)
                    .appFont(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.top, 5)

                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule().fill(.white)
                            .frame(width: max(2, geo.size.width * item.progress))
                    }
                }
                .frame(height: 2.5)
                .padding(.top, 8)

                HStack(spacing: 6) {
                    Text(item.timeText)
                        .appFont(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        Text(item.actionText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .appFont(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 21)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5) }
                }
                .padding(.top, 7)
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 10)
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .contentShape(Rectangle())
    }
}

// MARK: - 指示点

/// 圆点指示：当前页拉长成胶囊。
struct DeckDots: View {
    @ThemePalette private var palette
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                Capsule()
                    .fill(palette.primary.opacity(i == index ? 0.55 : 0.16))
                    .frame(width: i == index ? 14 : 5, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("第 \(index + 1) 项，共 \(count) 项")
    }
}

// MARK: - 封面解析（App 层补上本地书支持）

extension DeckItem {
    /// 书源书籍 → 卡片条目。封面走 BookCoverLocation，本地书也能显示。
    /// 与 Engine 层的 `init(book:)` 区分开：这里的封面能解析本地书路径。
    init(localCover book: Book) {
        self.init(id: book.bookUrl,
                  title: book.name,
                  caption: book.author,
                  cover: BookCoverLocation.url(for: book))
    }
}

extension HistoryItem {
    /// 书架书籍 → 记录条目，封面走 BookCoverLocation（支持本地书）。
    init(localCover book: Book, chapterCount: Int?, now: Date = Date()) {
        self.init(book: book, chapterCount: chapterCount, now: now,
                  cover: BookCoverLocation.url(for: book))
    }
}

// MARK: - 模板注册表

/// 按模板枚举取对应的板块视图。
///
/// 调用方（自定义发现页、书源发现页、将来的任何页面）只依赖这个入口：
/// 想换版式就改 `kind`，不用改调用代码。新增模板时在这里加一条分支即可。
struct DiscoverTemplateView: View {
    let kind: DiscoverTemplateKind
    let title: String
    var moreTitle: String = "全部"
    var books: [Book] = []
    /// 预先转好的卡片；传了就优先用，省掉 body 里的 map/prefix。
    var cards: [DeckItem] = []
    var history: [HistoryItem] = []
    var count: Int = DiscoverTemplate.countCeiling
    /// 外观：卡片倍率 / 圆角 / 序号
    var scale: Double = 1
    var corner: Double = 8
    var showNumber = true
    var onMore: (() -> Void)? = nil
    var onSelectBook: (Book) -> Void = { _ in }
    var onSelectHistory: (HistoryItem) -> Void = { _ in }

    private var limit: Int {
        DiscoverTemplate.template(for: kind).clampedCount(count)
    }

    private var deckItems: [DeckItem] {
        if !cards.isEmpty { return cards }
        return Array(books.prefix(limit)).map { DeckItem(book: $0) }
    }

    var body: some View {
        switch kind {
        case .largeCard:
            BoardLargeCard(title: title, moreTitle: moreTitle, items: deckItems,
                           onMore: onMore,
                           onSelect: { index in
                               if books.indices.contains(index) { onSelectBook(books[index]) }
                           })
        case .compactCard:
            BoardCompactCard(title: title, moreTitle: moreTitle, items: deckItems,
                             onMore: onMore,
                             onSelect: { index in
                                 if books.indices.contains(index) { onSelectBook(books[index]) }
                             })
        case .threeColumn:
            BoardThreeColumn(title: title, moreTitle: moreTitle, items: deckItems,
                             onMore: onMore,
                             onSelect: { index in
                                 if books.indices.contains(index) { onSelectBook(books[index]) }
                             })
        case .dualRow:
            BoardDualRow(title: title, moreTitle: moreTitle, items: deckItems,
                         onMore: onMore,
                         onSelect: { index in
                             if books.indices.contains(index) { onSelectBook(books[index]) }
                         })
        case .fixedList:
            BoardFixedList(title: title, moreTitle: moreTitle, items: deckItems,
                           onMore: onMore,
                           onSelect: { index in
                               if books.indices.contains(index) { onSelectBook(books[index]) }
                           })
        case .featureCard:
            BoardFeatureCard(title: title, moreTitle: moreTitle, items: deckItems,
                             onMore: onMore,
                             onSelect: { index in
                                 if books.indices.contains(index) { onSelectBook(books[index]) }
                             })
        case .updateFeed:
            BoardUpdateFeed(title: title, moreTitle: moreTitle, items: deckItems,
                            onMore: onMore,
                            onSelect: { index in
                                if books.indices.contains(index) { onSelectBook(books[index]) }
                            })
        case .badgeGrid:
            DiscoverBadgeGridSection(
                title: title,
                moreTitle: moreTitle,
                items: deckItems,
                scale: scale,
                corner: corner,
                showNumber: showNumber,
                onMore: onMore,
                onSelect: { _, index in
                    if books.indices.contains(index) { onSelectBook(books[index]) }
                }
            )
        case .covers:
            DiscoverCoversSection(
                title: title,
                moreTitle: moreTitle,
                items: deckItems,
                scale: scale,
                corner: corner,
                showNumber: showNumber,
                onMore: onMore,
                onSelect: { _, index in
                    if books.indices.contains(index) { onSelectBook(books[index]) }
                }
            )
        case .rankRow:
            DiscoverRankRowSection(
                title: title,
                moreTitle: moreTitle,
                items: deckItems,
                scale: scale,
                corner: corner,
                showNumber: showNumber,
                onMore: onMore,
                onSelect: { _, index in
                    if books.indices.contains(index) { onSelectBook(books[index]) }
                }
            )
        case .waterfall:
            DiscoverWaterfallSection(
                title: title,
                moreTitle: moreTitle,
                items: deckItems,
                scale: scale,
                corner: corner,
                showNumber: showNumber,
                onMore: onMore,
                onSelect: { _, index in
                    if books.indices.contains(index) { onSelectBook(books[index]) }
                }
            )
        case .curve:
            DiscoverCurveSection(
                title: title,
                moreTitle: moreTitle,
                items: deckItems,
                onMore: onMore,
                onSelect: { _, index in
                    if books.indices.contains(index) { onSelectBook(books[index]) }
                }
            )
        case .deck:
            DiscoverDeckSection(
                title: title,
                moreTitle: moreTitle,
                items: deckItems,
                onMore: onMore,
                onSelect: { _, index in
                    if books.indices.contains(index) { onSelectBook(books[index]) }
                }
            )
        case .history:
            DiscoverHistorySection(
                title: title,
                moreTitle: moreTitle,
                items: Array(history.prefix(limit)),
                onMore: onMore,
                onSelect: onSelectHistory
            )
        }
    }
}

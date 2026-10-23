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

// MARK: - 3D 翻转景深的卡片轨道

/// 一行可以左右滑的卡片。
///
/// **为什么用原生 ScrollView 而不是自己写 DragGesture**：
///  - 手指落在卡片上往下滑时，自定义拖拽手势会吃掉这次触摸，外层竖向 ScrollView
///    就再也收不到，页面卡住不动；原生横向滚动是 UIKit 的嵌套滚动，
///    横向归它、竖向自动交给外层，两边都不抢；
///  - 自己算位移时，快速甩动会先跟手、再弹回原位（松手才决定翻不翻页），
///    看着就是「回弹」。原生滚动有惯性和吸附，不存在这个问题。
///
/// 3D 翻转景深用 `scrollTransition(.interactive)` 完成：它拿到的 phase 是每一帧
/// 卡片相对视口中心的实时进度（-1…1），所以拖动过程中卡片就在连续翻转、缩小、
/// 后退、变淡，停下来再吸附到位。
struct DeckCarousel<Card: View>: View {
    let count: Int
    /// 卡片本体宽度
    let cardWidth: CGFloat
    /// 相邻卡片的槽位宽度（小于卡宽就会互相叠压）
    let step: CGFloat
    let stageHeight: CGFloat
    /// 偏离中心时的最大翻转角度（度），越大景深越强
    var flipDegrees: Double = 62
    /// 偏离中心时缩小到的比例
    var scaleFloor: Double = 0.74
    /// 偏离中心时下移的点数（弧形走廊靠它弯下来）
    var yDrift: CGFloat = 0
    /// 偏离中心时淡到的不透明度
    var opacityFloor: Double = 0.42
    /// 叠牌形态：卡片绕**底边**翻、并向两侧散开，像手里捏着一叠牌被拨开。
    /// 弧形走廊不打开，它保持贴着一道弧线滑。
    var fanOut: Bool = false
    /// 叠牌时每格额外的横向散开（pt）
    var fanSpread: CGFloat = 0
    /// 当前居中的卡片下标（滑动时更新，用于底部书名与圆点）
    @Binding var index: Int?
    @ViewBuilder var card: (Int) -> Card

    var body: some View {
        GeometryReader { proxy in
            // 两端留出半个槽位的空位，第一张和最后一张也能停在正中
            let side = max((proxy.size.width - step) / 2, 0)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<max(count, 0), id: \.self) { i in
                        // 槽位比卡窄：画面宽度按 step 算，卡本身按 cardWidth 画，
                        // 于是相邻两张自然叠压在一起，像一叠真卡片
                        card(i)
                            .frame(width: cardWidth, height: stageHeight)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                // 相邻卡片也要有明显角度，所以先把相位放大再夹到 0…1
                                let depth = min(abs(phase.value) * 2.2, 1)
                                return content
                                    .rotation3DEffect(.degrees(Double(-phase.value) * flipDegrees),
                                                      axis: (x: 0, y: 1, z: 0),
                                                      // 透视调弱：太强的透视会让倾斜的卡被压扁，
                                                      // 侧卡看着像一条竖线。
                                                      anchor: .center,
                                                      perspective: 0.35)
                                    .scaleEffect(1 - (1 - scaleFloor) * depth)
                                    .offset(y: yDrift * depth)
                                    .opacity(1 - (1 - opacityFloor) * depth)
                            }
                            .frame(width: step, height: stageHeight)
                            // 层级只能在 VisualEffect 外面设（里面没有 zIndex）。
                            // 用「离当前页码几个」算：正中的卡压在最上层。
                            .zIndex(-Double(abs(i - (index ?? 0))))
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            // 内容装得下时不回弹；甩动由系统惯性接管，不会弹回原卡
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollPosition(id: $index)
            .frame(height: stageHeight)
        }
        .frame(height: stageHeight)
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
    /// 相邻卡的水平间距（小于卡宽即互相叠压）
    private let step: CGFloat = 68
    private let stageHeight: CGFloat = 208

    private var currentIndex: Int { index ?? 0 }
    private var current: DeckItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)

            DeckCarousel(count: items.count,
                         cardWidth: cardWidth,
                         step: step,
                         stageHeight: stageHeight,
                         flipDegrees: 58,
                         scaleFloor: 0.78,
                         yDrift: 11,
                         opacityFloor: 0.45,
                         index: $index) { itemIndex in
                let item = items[itemIndex]
                DeckCard(radius: 10,
                         showCaption: false,
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
                DeckDots(count: items.count, index: currentIndex)
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

/// 中央卡在前完整显示，左右各两张向后翻转、缩小、压暗。
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
    /// 槽位宽度：卡宽的一半多一点，两侧各露半张，层层压住
    private var step: CGFloat { cardWidth * 0.56 }

    private var currentIndex: Int { index ?? 0 }
    private var current: DeckItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)

            DeckCarousel(count: items.count,
                         cardWidth: cardWidth,
                         step: step,
                         stageHeight: stageHeight,
                         // 卡片堆叠：温和的叠卡。
                         // 之前 78° + perspective 0.9 + 绕底边，侧卡直接变成一条竖线，
                         // 看着很不舒服。现在只做轻微倾斜，侧卡仍能看清封面。
                         flipDegrees: 26,
                         scaleFloor: 0.86,
                         yDrift: 0,
                         opacityFloor: 0.62,
                         index: $index) { itemIndex in
                let item = items[itemIndex]
                DeckCard(radius: 10,
                         showCaption: false,
                         title: item.title) {
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
                DeckDots(count: items.count, index: currentIndex)
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
        // cards 也要按 limit 截断：模板展示库靠 count 控制预览数量，
        // 如果这里原样返回全部 cards，预览就会一律铺满（大封面 12 个、圆点 12 个）。
        // limit == unlimited 时表示「全部」，不截。
        if !cards.isEmpty {
            guard limit != DiscoverTemplate.unlimited else { return cards }
            return Array(cards.prefix(max(limit, 0)))
        }
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
        case .featureCard:
            BoardFeatureCard(title: title, moreTitle: moreTitle, items: deckItems,
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

import SwiftUI

// MARK: - 版式公共件

/// 栏目头：左标题、右「全部 ›」。所有版式共用同一套字号与间距，
/// 保证一屏里十几块板块看起来是同一本杂志。
struct BoardHeader: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    var onMore: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .appFont(.system(size: 19, weight: .bold))
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

/// 版式统一的封面：3:4 比例 + 顶部高光 + 底部书名条。
///
/// 参考 Apple Books 的封面处理：底部一条纯黑说明条写书名和作者，
/// 衬线体、居中、两行封顶。这样一屏里十几张封面高度一致，
/// 不会因为书名长短把网格顶得七零八落。
struct BoardCover: View {
    let url: URL?
    let title: String
    var author: String = ""
    /// 是否显示底部书名条（小尺寸封面里字会糊，可以关掉）
    var showCaption: Bool = true
    var corner: CGFloat = 3
    /// 书名条相对封面的高度比例，小卡会自动收紧
    var captionScale: CGFloat = 1

    /// 小卡自动收紧字号：按实际渲染宽度算，而不是调用方传进来的宽度。
    private func scaledCaption(_ w: CGFloat) -> CGFloat {
        let base = min(max(w * 0.072, 6), 9)
        return base * captionScale
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                DeckCoverImage(url: url)
                // 顶部一道极淡的高光，模拟硬壳封面的反光
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .topLeading, endPoint: .center
                )
                // 书脊：左侧一条窄阴影
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.28), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(2, w * 0.035))
                    Spacer(minLength: 0)
                }
                if showCaption {
                    VStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 1.5) {
                            Text(title)
                                .font(.system(size: scaledCaption(w),
                                              weight: .bold,
                                              design: .serif))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            if !author.isEmpty {
                                Text(author)
                                    .font(.system(size: max(scaledCaption(w) * 0.72, 5)))
                                    .foregroundStyle(.white.opacity(0.66))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4 * captionScale)
                        .background(.black)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - 01 大型阅读卡片

/// 一张白卡讲清一本书。横向滑动，右侧露出下一张的边。
struct BoardLargeCard: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    private let cardWidth: CGFloat = 310
    private let coverW: CGFloat = 104
    private let coverH: CGFloat = 139

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                        Button { onSelect(pair.offset) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                BoardCover(url: pair.element.cover,
                                           title: pair.element.title,
                                           author: pair.element.caption,
                                           corner: 3)
                                    .frame(width: coverW, height: coverH)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pair.element.title)
                                        .appFont(.system(size: 20, weight: .bold))
                                        .foregroundStyle(palette.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .minimumScaleFactor(0.8)
                                    if !pair.element.caption.isEmpty {
                                        Text(pair.element.caption)
                                            .appFont(.system(size: 15))
                                            .foregroundStyle(palette.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.top, 12)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(width: cardWidth, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(palette.surface)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("board.large.\(pair.element.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 18)
    }
}

// MARK: - 02 精简阅读卡片

/// 整卡用封面主色铺底，小封面 + 白书名。没有图片也能靠配色撑住版面。
struct BoardCompactCard: View {
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    private let cardWidth: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                        Button { onSelect(pair.offset) } label: {
                            HStack(spacing: 10) {
                                BoardCover(url: pair.element.cover,
                                           title: pair.element.title,
                                           author: pair.element.caption,
                                           corner: 4,
                                           captionScale: 0.7)
                                    .frame(width: 46, height: 62)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pair.element.title)
                                        .appFont(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if !pair.element.caption.isEmpty {
                                        Text(pair.element.caption)
                                            .appFont(.system(size: 12.5))
                                            .foregroundStyle(.white.opacity(0.72))
                                            .lineLimit(1)
                                    }
                                    Text("书籍")
                                        .appFont(.system(size: 11.5))
                                        .foregroundStyle(.white.opacity(0.46))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(11)
                            .frame(width: cardWidth, alignment: .leading)
                            .background {
                                // 用卡片自身的 id 取一个稳定色，同一本书每次颜色都一样
                                LinearGradient(
                                    colors: BoardTint.pair(for: pair.element.id),
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("board.compact.\(pair.element.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 18)
    }
}

// MARK: - 03 三列书架

struct BoardThreeColumn: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 13, alignment: .top),
                                count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    Button { onSelect(pair.offset) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            BoardCover(url: pair.element.cover,
                                       title: pair.element.title,
                                       author: pair.element.caption,
                                       corner: 3)
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            Text(pair.element.title)
                                .appFont(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !pair.element.caption.isEmpty {
                                Text(pair.element.caption)
                                    .appFont(.system(size: 11.5))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("board.three.\(pair.element.id)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }
}

// MARK: - 04 双行横向轮播

/// 两行各一组横向滚动，展示量是单行的两倍。
struct BoardDualRow: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    private let cardWidth: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
                .padding(.horizontal, 16)
            VStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { row in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(rowItems(row).enumerated()), id: \.element.item.id) { pair in
                                Button { onSelect(pair.element.index) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        BoardCover(url: pair.element.item.cover,
                                                   title: pair.element.item.title,
                                                   author: pair.element.item.caption,
                                                   corner: 3)
                                            .frame(width: cardWidth, height: cardWidth * 4 / 3)
                                        Text(pair.element.item.title)
                                            .appFont(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(palette.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        if !pair.element.item.caption.isEmpty {
                                            Text(pair.element.item.caption)
                                                .appFont(.system(size: 11))
                                                .foregroundStyle(palette.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(width: cardWidth)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("board.dual.\(pair.element.item.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(.bottom, 18)
    }

    /// 第 row 行的条目，附带原始下标（点击时要回传）。
    private func rowItems(_ row: Int) -> [(index: Int, item: DeckItem)] {
        let half = (items.count + 1) / 2
        if row == 0 {
            return Array(items.prefix(half).enumerated()).map { ($0.offset, $0.element) }
        }
        return Array(items.dropFirst(half).enumerated()).map { (half + $0.offset, $0.element) }
    }
}

// MARK: - 05 固定列表

struct BoardFixedList: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    Button { onSelect(pair.offset) } label: {
                        HStack(spacing: 13) {
                            BoardCover(url: pair.element.cover,
                                       title: pair.element.title,
                                       author: pair.element.caption,
                                       corner: 2,
                                       captionScale: 0.62)
                                .frame(width: 56, height: 75)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pair.element.title)
                                    .appFont(.system(size: 15.5, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                                    .lineLimit(1)
                                if !pair.element.caption.isEmpty {
                                    Text(pair.element.caption)
                                        .appFont(.system(size: 13))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            // 分隔线从缩进处开始，和书名左缘对齐
                            if pair.offset > 0 {
                                Rectangle()
                                    .fill(palette.secondary.opacity(0.22))
                                    .frame(height: 0.5)
                                    .padding(.leading, 69)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("board.list.\(pair.element.id)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }
}

// MARK: - 06 图文大卡

struct BoardFeatureCard: View {
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    private let cardWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                        Button { onSelect(pair.offset) } label: {
                            HStack(alignment: .top, spacing: 13) {
                                BoardCover(url: pair.element.cover,
                                           title: pair.element.title,
                                           author: pair.element.caption,
                                           corner: 3)
                                    .frame(width: 118, height: 158)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pair.element.title)
                                        .appFont(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .minimumScaleFactor(0.82)
                                    if !pair.element.caption.isEmpty {
                                        Text(pair.element.caption)
                                            .appFont(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.76))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text("查看作品")
                                        .appFont(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 6)
                                        .background(.white, in: Capsule())
                                }
                                .padding(.top, 5)
                                .padding(.bottom, 2)
                                Spacer(minLength: 0)
                            }
                            .padding(13)
                            .frame(width: cardWidth, alignment: .leading)
                            .background {
                                LinearGradient(
                                    colors: BoardTint.pair(for: pair.element.id),
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("board.feature.\(pair.element.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 18)
    }
}

// MARK: - 07 更新信息流

/// 追更专用：书名 + 蓝色「更新」标签 + 章节 + 相对时间。
struct BoardUpdateFeed: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    let items: [DeckItem]
    var onMore: (() -> Void)?
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BoardHeader(title: title, moreTitle: moreTitle, onMore: onMore)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    Button { onSelect(pair.offset) } label: {
                        HStack(spacing: 11) {
                            BoardCover(url: pair.element.cover,
                                       title: pair.element.title,
                                       author: pair.element.caption,
                                       corner: 3,
                                       captionScale: 0.58)
                                .frame(width: 46, height: 61)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.element.title)
                                    .appFont(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("更新")
                                        .appFont(.system(size: 12.5))
                                        .foregroundStyle(palette.accent)
                                    Text(pair.element.caption.isEmpty ? "有新章节" : pair.element.caption)
                                        .appFont(.system(size: 12.5))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if pair.offset > 0 {
                                Rectangle()
                                    .fill(palette.secondary.opacity(0.22))
                                    .frame(height: 0.5)
                                    .padding(.leading, 57)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("board.feed.\(pair.element.id)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }
}

// MARK: - 配色

/// 从条目 id 取一对稳定的渐变色。
///
/// 用 FNV-1a 而不是 `hashValue`：后者每次启动都会变，
/// 同一本书今天蓝明天绿，用户会以为是另一张卡。
enum BoardTint {
    private static let palettes: [(String, String)] = [
        ("#3F4A35", "#1E2419"),
        ("#1B3A5C", "#0A1A2C"),
        ("#6B7A52", "#37402B"),
        ("#2B3A4A", "#101820"),
        ("#4A4038", "#221C17"),
        ("#3A1C71", "#241340"),
        ("#134E5E", "#0B2B33"),
        ("#42275A", "#2A183A")
    ]

    static func pair(for id: String) -> [Color] {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        let entry = palettes[Int(hash % UInt64(palettes.count))]
        return [Color(hex: entry.0), Color(hex: entry.1)]
    }
}

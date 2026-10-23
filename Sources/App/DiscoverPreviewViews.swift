import SwiftUI

/// 预览专用封面：按书名现画的渐变 + 圆 + 文字，不请求网络、不内置图片。
struct PreviewCoverArt: View {
    let title: String
    /// 是否把书名印在封面上（大图/横滑用 true，已在下方显示书名的用 false）
    var showTitle: Bool = true
    var corner: CGFloat = 8

    private var size: CGFloat {
        // 书名越长字号越小，避免溢出
        switch title.count {
        case ..<5: return 13
        case 5...7: return 10.5
        default: return 8.5
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let colors = DiscoverPreviewCover.colors(for: title)
            let orbs = DiscoverPreviewCover.orbs(for: title)

            ZStack {
                LinearGradient(
                    colors: [Color(hex: colors.start), Color(hex: colors.end)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 装饰圆
                ForEach(Array(orbs.enumerated()), id: \.offset) { pair in
                    Circle()
                        .fill(.white.opacity(0.03 + Double(pair.offset) * 0.02))
                        .frame(width: w * orbs[pair.offset].r * 2,
                               height: w * orbs[pair.offset].r * 2)
                        .position(x: w * orbs[pair.offset].x, y: h * orbs[pair.offset].y)
                }
                // 底部斜块
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.55))
                    path.addLine(to: CGPoint(x: w, y: h * 0.76))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(.black.opacity(0.16))

                if showTitle {
                    titleText(width: w)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    /// 书名分两行，字号按长度自适应。
    private func titleText(width: CGFloat) -> some View {
        let chars = Array(title)
        let half = (chars.count + 1) / 2
        let line1 = String(chars.prefix(half))
        let line2 = String(chars.dropFirst(half))

        return VStack(alignment: .leading, spacing: 2) {
            Text(line1)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
            if !line2.isEmpty {
                Text(line2)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.top, width * 0.10)
    }
}

extension Color {
    /// "2D4A6B" → Color。解析失败时回落灰。
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self = Color(white: 0.4)
            return
        }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

// MARK: - 模板预览

/// 选模板时给每种版式一个真实观感的缩略预览。
///
/// 用 `DiscoverPreviewCatalog` 的公有领域书目 + `PreviewCoverArt` 现画封面，
/// 不联网、瞬间出图，也不涉及任何第三方素材授权。
struct DiscoverTemplateThumbnail: View {
    @ThemePalette private var palette
    let kind: DiscoverTemplateKind

    private var samples: [DiscoverPreviewCatalog.Sample] {
        DiscoverPreviewCatalog.heroSamples(count: 6)
    }

    var body: some View {
        GeometryReader { geo in
            // 缩略图会被放进 104x78 这种小格子里，所有内部尺寸按可用宽度等比缩
            let unit = max(geo.size.width, 1) / 104

            VStack(alignment: .leading, spacing: 6 * unit) {
                content(unit: unit)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private func content(unit: CGFloat) -> some View {
        // 所有尺寸乘 unit：从 104pt 宽的大预览到 78pt 的小格子都按比例缩
        let gap = 6 * unit

        switch kind {
        case .largeCard:
            // 一张白卡 + 左封面右标题
            HStack(spacing: gap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                        .fill(palette.surface)
                    HStack(spacing: 7 * unit) {
                        PreviewCoverArt(title: samples[0].title, corner: 4 * unit)
                            .frame(width: 26 * unit, height: 35 * unit)
                        VStack(alignment: .leading, spacing: 2.5 * unit) {
                            Text(samples[0].title)
                                .font(.system(size: 8 * unit, weight: .bold))
                                .foregroundStyle(palette.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("作者")
                                .font(.system(size: 6.5 * unit))
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8 * unit)
                }
                .frame(width: 78 * unit, height: 46 * unit)
            }

        case .compactCard:
            // 色底横条 + 小封面 + 白字
            HStack(spacing: gap * 0.8) {
                ForEach(samples.prefix(2)) { sample in
                    HStack(spacing: 6 * unit) {
                        PreviewCoverArt(title: sample.title, corner: 3 * unit)
                            .frame(width: 18 * unit, height: 24 * unit)
                        VStack(alignment: .leading, spacing: 1.5 * unit) {
                            Text(sample.title)
                                .font(.system(size: 7.5 * unit, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("书籍")
                                .font(.system(size: 5.8 * unit))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(5 * unit)
                    .frame(width: 62 * unit, height: 34 * unit)
                    .background {
                        LinearGradient(colors: BoardTint.pair(for: sample.title),
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6 * unit, style: .continuous))
                }
            }

        case .threeColumn:
            HStack(alignment: .top, spacing: gap * 0.8) {
                ForEach(samples.prefix(3)) { sample in
                    VStack(alignment: .leading, spacing: 2 * unit) {
                        PreviewCoverArt(title: sample.title, corner: 3 * unit)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        Text(sample.title)
                            .font(.system(size: 6 * unit, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }

        case .dualRow:
            VStack(spacing: 5 * unit) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap * 0.7) {
                        ForEach(samples.prefix(4).dropFirst(row * 2).prefix(2)) { sample in
                            VStack(alignment: .leading, spacing: 1.5 * unit) {
                                PreviewCoverArt(title: sample.title, corner: 3 * unit)
                                    .frame(width: 22 * unit, height: 29 * unit)
                                Text(sample.title)
                                    .font(.system(size: 5.6 * unit))
                                    .foregroundStyle(palette.primary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

        case .fixedList:
            VStack(spacing: 0) {
                ForEach(Array(samples.prefix(3).enumerated()), id: \.element.id) { pair in
                    HStack(spacing: 6 * unit) {
                        PreviewCoverArt(title: pair.element.title, showTitle: false, corner: 2 * unit)
                            .frame(width: 14 * unit, height: 19 * unit)
                        VStack(alignment: .leading, spacing: 1.5 * unit) {
                            Text(pair.element.title)
                                .font(.system(size: 7.5 * unit, weight: .semibold))
                                .foregroundStyle(palette.primary)
                                .lineLimit(1)
                            Text(pair.element.author)
                                .font(.system(size: 6 * unit))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3.5 * unit)
                    .overlay(alignment: .top) {
                        if pair.offset > 0 {
                            Rectangle()
                                .fill(palette.secondary.opacity(0.2))
                                .frame(height: 0.5)
                                .padding(.leading, 20 * unit)
                        }
                    }
                }
            }

        case .featureCard:
            // 大色块卡 + 左下胶囊按钮
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                    .fill(palette.surface)
                HStack(alignment: .top, spacing: 6 * unit) {
                    PreviewCoverArt(title: samples[0].title, corner: 3 * unit)
                        .frame(width: 28 * unit, height: 38 * unit)
                    VStack(alignment: .leading, spacing: 2 * unit) {
                        Text(samples[0].title)
                            .font(.system(size: 7.5 * unit, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text("查看作品")
                            .font(.system(size: 5.4 * unit, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5 * unit)
                            .padding(.vertical, 1.8 * unit)
                            .background(.white, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .padding(6 * unit)
            }
            .frame(width: 88 * unit, height: 50 * unit)
            .background {
                LinearGradient(colors: BoardTint.pair(for: samples[0].title),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8 * unit, style: .continuous))

        case .updateFeed:
            VStack(spacing: 0) {
                ForEach(Array(samples.prefix(3).enumerated()), id: \.element.id) { pair in
                    HStack(spacing: 6 * unit) {
                        PreviewCoverArt(title: pair.element.title, showTitle: false, corner: 2 * unit)
                            .frame(width: 13 * unit, height: 17 * unit)
                        VStack(alignment: .leading, spacing: 1.5 * unit) {
                            Text(pair.element.title)
                                .font(.system(size: 7.2 * unit, weight: .semibold))
                                .foregroundStyle(palette.primary)
                                .lineLimit(1)
                            HStack(spacing: 1.5 * unit) {
                                Text("更新")
                                    .font(.system(size: 5.6 * unit))
                                    .foregroundStyle(palette.accent)
                                Text("第 \(782 - pair.offset * 37) 章")
                                    .font(.system(size: 5.6 * unit))
                                    .foregroundStyle(palette.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3.5 * unit)
                    .overlay(alignment: .top) {
                        if pair.offset > 0 {
                            Rectangle()
                                .fill(palette.secondary.opacity(0.2))
                                .frame(height: 0.5)
                                .padding(.leading, 19 * unit)
                        }
                    }
                }
            }

        case .badgeGrid:
            HStack(spacing: gap) {
                ForEach(Array(samples.prefix(2).enumerated()), id: \.element.id) { pair in
                    ZStack(alignment: .bottomLeading) {
                        PreviewCoverArt(title: pair.element.title, corner: 6 * unit)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        Text(String(format: "%02d", pair.offset + 1))
                            .font(.system(size: 18 * unit, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .padding(.leading, 4 * unit)
                            .padding(.bottom, 1)
                    }
                }
            }

        case .covers:
            HStack(spacing: gap * 0.8) {
                ForEach(samples.prefix(4)) { sample in
                    VStack(alignment: .leading, spacing: 2 * unit) {
                        PreviewCoverArt(title: sample.title, corner: 5 * unit)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        Text(sample.title)
                            .font(.system(size: 6.5 * unit))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                    }
                }
            }

        case .rankRow:
            VStack(spacing: 3 * unit) {
                ForEach(Array(samples.prefix(3).enumerated()), id: \.element.id) { pair in
                    HStack(spacing: gap * 0.8) {
                        Text("\(pair.offset + 1)")
                            .font(.system(size: 8 * unit, weight: .bold))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 9 * unit)
                        PreviewCoverArt(title: pair.element.title, showTitle: false, corner: 2 * unit)
                            .frame(width: 16 * unit, height: 21 * unit)
                        Text(pair.element.title)
                            .font(.system(size: 8 * unit, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .waterfall:
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    PreviewCoverArt(title: samples[0].title, corner: 4 * unit)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    PreviewCoverArt(title: samples[1].title, corner: 4 * unit)
                        .aspectRatio(1, contentMode: .fit)
                }
                VStack(spacing: gap) {
                    PreviewCoverArt(title: samples[2].title, corner: 4 * unit)
                        .aspectRatio(1, contentMode: .fit)
                    PreviewCoverArt(title: samples[3].title, corner: 4 * unit)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                }
            }

        case .curve, .fan, .deck:
            // 三种立体版式用同一套「叠放」示意，靠角度区分
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let sample = samples[index]
                    PreviewCoverArt(title: sample.title,
                                    showTitle: index == 1,
                                    corner: 5 * unit)
                        .frame(width: 42 * unit, height: 56 * unit)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: offsetX(for: index, unit: unit),
                                y: offsetY(for: index, unit: unit))
                        .scaleEffect(index == 1 ? 1 : 0.88)
                        .opacity(index == 1 ? 1 : 0.85)
                        .zIndex(index == 1 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)

        case .history:
            HStack(spacing: gap) {
                ForEach(samples.prefix(2)) { sample in
                    ZStack(alignment: .bottomLeading) {
                        PreviewCoverArt(title: sample.title, showTitle: false, corner: 5 * unit)
                            .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                       startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 5 * unit, style: .continuous))
                        VStack(alignment: .leading, spacing: 1 * unit) {
                            Text(sample.title)
                                .font(.system(size: 7 * unit, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("读到 第 12 章")
                                .font(.system(size: 5.8 * unit))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .padding(3 * unit)
                    }
                }
            }
        }
    }

    private func rotation(for index: Int) -> Double {
        switch kind {
        case .fan: return Double(index - 1) * 16
        case .curve: return Double(index - 1) * 10
        default: return 0
        }
    }

    private func offsetX(for index: Int, unit: CGFloat) -> CGFloat {
        switch kind {
        case .fan: return CGFloat(index - 1) * 8 * unit
        case .curve: return CGFloat(index - 1) * 23 * unit
        default: return CGFloat(index - 1) * 20 * unit
        }
    }

    private func offsetY(for index: Int, unit: CGFloat) -> CGFloat {
        switch kind {
        case .fan: return CGFloat(abs(index - 1)) * 4 * unit
        default: return CGFloat(abs(index - 1)) * 3 * unit
        }
    }
}

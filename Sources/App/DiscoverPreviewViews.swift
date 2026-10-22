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
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .badgeGrid:
            HStack(spacing: 8) {
                ForEach(Array(samples.prefix(2).enumerated()), id: \.element.id) { pair in
                    ZStack(alignment: .bottomLeading) {
                        PreviewCoverArt(title: pair.element.title)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        Text(String(format: "%02d", pair.offset + 1))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .padding(.leading, 5)
                            .padding(.bottom, 1)
                    }
                }
            }

        case .covers:
            HStack(spacing: 6) {
                ForEach(samples.prefix(4)) { sample in
                    VStack(alignment: .leading, spacing: 3) {
                        PreviewCoverArt(title: sample.title, corner: 6)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        Text(sample.title)
                            .font(.system(size: 7))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                    }
                }
            }

        case .rankRow:
            VStack(spacing: 4) {
                ForEach(Array(samples.prefix(3).enumerated()), id: \.element.id) { pair in
                    HStack(spacing: 6) {
                        Text("\(pair.offset + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 10)
                        PreviewCoverArt(title: pair.element.title, showTitle: false, corner: 3)
                            .frame(width: 18, height: 24)
                        Text(pair.element.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .waterfall:
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 6) {
                    PreviewCoverArt(title: samples[0].title, corner: 5)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    PreviewCoverArt(title: samples[1].title, corner: 5)
                        .aspectRatio(1, contentMode: .fit)
                }
                VStack(spacing: 6) {
                    PreviewCoverArt(title: samples[2].title, corner: 5)
                        .aspectRatio(1, contentMode: .fit)
                    PreviewCoverArt(title: samples[3].title, corner: 5)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                }
            }

        case .curve, .fan, .deck:
            // 三种立体版式用同一套「叠放」示意，靠角度区分
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let sample = samples[index]
                    PreviewCoverArt(title: sample.title, showTitle: index == 1, corner: 6)
                        .frame(width: 54, height: 72)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: offsetX(for: index), y: offsetY(for: index))
                        .scaleEffect(index == 1 ? 1 : 0.88)
                        .opacity(index == 1 ? 1 : 0.85)
                        .zIndex(index == 1 ? 1 : 0)
                }
            }
            .frame(height: 84)
            .frame(maxWidth: .infinity)

        case .history:
            HStack(spacing: 6) {
                ForEach(samples.prefix(2)) { sample in
                    ZStack(alignment: .bottomLeading) {
                        PreviewCoverArt(title: sample.title, showTitle: false, corner: 6)
                            .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                       startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.title)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("读到 第 12 章")
                                .font(.system(size: 6.5))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .padding(4)
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

    private func offsetX(for index: Int) -> CGFloat {
        switch kind {
        case .fan: return CGFloat(index - 1) * 10
        case .curve: return CGFloat(index - 1) * 30
        default: return CGFloat(index - 1) * 26
        }
    }

    private func offsetY(for index: Int) -> CGFloat {
        switch kind {
        case .fan: return CGFloat(abs(index - 1)) * 5
        default: return CGFloat(abs(index - 1)) * 4
        }
    }
}

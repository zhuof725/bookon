import SwiftUI
import UIKit

/// Grid-only cover width is a preference, never a minimum that can overflow.
/// Columns shrink on compact windows; accessibility uses at most two 120pt cells.
struct ThemeShelfMetrics {
    let columns: Int
    let coverWidth: CGFloat

    init(width: CGFloat, customization: ThemeCustomization, accessibility: Bool) {
        let available = max(1, (width.isFinite ? width : 320) - 48)
        let minimumCell: CGFloat = accessibility ? 120 : 60
        let fitting = max(1, Int(min(5, (available + 18) / (minimumCell + 18))))
        let requested = min(max(customization.shelfColumns, 2), 5)
        columns = min(requested, fitting, accessibility ? 2 : 5)
        let cell = max(1, (available - CGFloat(columns - 1) * 18) / CGFloat(columns))
        let desired = customization.coverWidth.isFinite ? min(max(customization.coverWidth, 60), 180) : 112
        coverWidth = min(CGFloat(desired), cell)
    }
}

/// Process-wide claim, including a launch without an image. Foregrounding and
/// changing the active theme never start another splash; additional windows do not either.
@MainActor
private final class ThemeLaunchSession {
    static let shared = ThemeLaunchSession()
    private var consumed = false
    func claim(_ id: String?) -> String? {
        guard !consumed else { return nil }
        consumed = true
        return id.flatMap { ThemeAssetStore.isValidID($0) ? $0 : nil }
    }
}

/// Reusable app overlay, deliberately unrelated to the system LaunchScreen.
struct ThemeLaunchOverlay: View {
    let image: UIImage
    let onDismiss: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea().accessibilityHidden(true)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
        .accessibilityIdentifier("theme.launch.overlay")
        .task {
            do { try await Task.sleep(nanoseconds: 1_200_000_000) }
            catch { return }
            onDismiss()
        }
    }
}

struct ThemeLaunchHost: ViewModifier {
    @Environment(\.appTheme) private var theme
    @StateObject private var imageLoader = ThemeAssetImageLoader()
    @State private var evaluated = false
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!presented)
            .accessibilityHidden(presented)
            .overlay {
                if presented, let image = imageLoader.image {
                    ThemeLaunchOverlay(image: image) { presented = false }
                }
            }
            .task {
                guard !evaluated else { return }
                evaluated = true
                let id = ThemeLaunchSession.shared.claim(theme.customization?.launchImage)
                await imageLoader.load(id)
                guard !Task.isCancelled, imageLoader.image != nil else { return }
                presented = true
                // Overlay owns the same automatic dismissal in production and preview.
            }
    }
}

/// App chrome only. Reader paper, pagination and ReadingFontManager stay independent.
enum ThemeTabStyle: String, Codable, CaseIterable, Identifiable {
    case iconsAndText, icons, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconsAndText: return "图标和文字"
        case .icons: return "仅图标"
        case .text: return "仅文字"
        }
    }
}

enum ThemeInterfaceEffect: String, Codable, CaseIterable, Identifiable {
    case transparent, frosted, opaque
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transparent: return "透明"
        case .frosted: return "玻璃"
        case .opaque: return "不透明"
        }
    }
}

struct ThemeCustomization: Codable, Equatable {
    var tabStyle: ThemeTabStyle = .iconsAndText
    var shelfColumns: Int = 3
    var coverWidth: Double = 112
    var defaultCoverImage: String? = nil
    var launchImage: String? = nil
    var pageBackgroundImage: String? = nil
    /// nil follows the existing font manager; an empty string explicitly means system.
    var fontPostScriptName: String? = nil
    var effect: ThemeInterfaceEffect = .frosted
    var cardBackground: Bool = true
    /// Optional per-tab icon override. Keys are LibraryTab raw names
    /// ("shelf"/"statistics"/"profile"); values are either an SF Symbol name
    /// or a ThemeAssetStore identifier (UUID.jpg) for an imported image.
    var tabIcons: [String: String]? = nil
    /// Strength of the subtle glow behind transparent surfaces, 0 disables it.
    var glowIntensity: Double = 0.5
    /// Opacity of the frosted effect's surface tint layer.
    var surfaceOpacity: Double = 0.85

    static let shelfColumnsRange = 2...5
    static let coverWidthRange: ClosedRange<Double> = 60...180
    static let glowIntensityRange: ClosedRange<Double> = 0...1
    static let surfaceOpacityRange: ClosedRange<Double> = 0...1
    static let tabIconKeys: Set<String> = ["shelf", "statistics", "profile"]

    init(tabStyle: ThemeTabStyle = .iconsAndText, shelfColumns: Int = 3,
         coverWidth: Double = 112, defaultCoverImage: String? = nil,
         launchImage: String? = nil, pageBackgroundImage: String? = nil,
         fontPostScriptName: String? = nil, effect: ThemeInterfaceEffect = .frosted,
         cardBackground: Bool = true, tabIcons: [String: String]? = nil,
         glowIntensity: Double = 0.5, surfaceOpacity: Double = 0.85) {
        self.tabStyle = tabStyle
        self.shelfColumns = shelfColumns
        self.coverWidth = coverWidth
        self.defaultCoverImage = defaultCoverImage
        self.launchImage = launchImage
        self.pageBackgroundImage = pageBackgroundImage
        self.fontPostScriptName = fontPostScriptName
        self.effect = effect
        self.cardBackground = cardBackground
        self.tabIcons = tabIcons
        self.glowIntensity = glowIntensity
        self.surfaceOpacity = surfaceOpacity
    }

    private enum CodingKeys: String, CodingKey {
        case tabStyle, shelfColumns, coverWidth, defaultCoverImage, launchImage
        case pageBackgroundImage, fontPostScriptName, effect, cardBackground
        case tabIcons, glowIntensity, surfaceOpacity
    }

    /// Newly added fields get their defaults; malformed present values still fail.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tabStyle = try values.decodeIfPresent(ThemeTabStyle.self, forKey: .tabStyle) ?? .iconsAndText
        shelfColumns = try values.decodeIfPresent(Int.self, forKey: .shelfColumns) ?? 3
        coverWidth = try values.decodeIfPresent(Double.self, forKey: .coverWidth) ?? 112
        defaultCoverImage = try values.decodeIfPresent(String.self, forKey: .defaultCoverImage)
        launchImage = try values.decodeIfPresent(String.self, forKey: .launchImage)
        pageBackgroundImage = try values.decodeIfPresent(String.self, forKey: .pageBackgroundImage)
        fontPostScriptName = try values.decodeIfPresent(String.self, forKey: .fontPostScriptName)
        effect = try values.decodeIfPresent(ThemeInterfaceEffect.self, forKey: .effect) ?? .transparent
        cardBackground = try values.decodeIfPresent(Bool.self, forKey: .cardBackground) ?? true
        tabIcons = try values.decodeIfPresent([String: String].self, forKey: .tabIcons)
        glowIntensity = try values.decodeIfPresent(Double.self, forKey: .glowIntensity) ?? 0.5
        surfaceOpacity = try values.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 0.85
    }

    var assetIDs: Set<String> {
        Set([defaultCoverImage, launchImage, pageBackgroundImage].compactMap { $0 })
            .union((tabIcons ?? [:]).values.filter(ThemeAssetStore.isValidID))
    }

    var validationMessage: String? {
        guard Self.shelfColumnsRange.contains(shelfColumns) else { return "书架列数须在 2–5 列之间。" }
        guard coverWidth.isFinite, Self.coverWidthRange.contains(coverWidth) else { return "封面宽度须在 60–180 点之间。" }
        if let font = fontPostScriptName,
           font.count > 128 || font.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "字体标识无效，最多允许 128 个字符。"
        }
        guard glowIntensity.isFinite, Self.glowIntensityRange.contains(glowIntensity) else {
            return "光晕强度须在 0–1 之间。"
        }
        guard surfaceOpacity.isFinite, Self.surfaceOpacityRange.contains(surfaceOpacity) else {
            return "透明度须在 0–1 之间。"
        }
        if let tabIcons {
            guard !tabIcons.isEmpty, tabIcons.count <= Self.tabIconKeys.count,
                  tabIcons.keys.allSatisfy(Self.tabIconKeys.contains) else {
                return "标签页图标设置无效，请重新配置。"
            }
            guard tabIcons.values.allSatisfy({
                ThemeAssetStore.isValidID($0) || ThemeAssetStore.isValidSymbolName($0)
            }) else { return "标签页图标无效，请重新选择图标或图片。" }
        }
        guard assetIDs.allSatisfy(ThemeAssetStore.isValidID) else { return "主题图片标识无效，请重新导入图片。" }
        return nil
    }
}

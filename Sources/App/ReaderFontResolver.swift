import UIKit
import CoreText

/// Reading-only font resolution. App controls, covers, emoji and numeric comment
/// bubbles keep their existing fonts. Empty selection preserves the old layout.
enum ReaderFontResolver {
    static var identity: String { ReadingFontManager.shared.selectedPostScriptName }

    static func customFont(size: CGFloat) -> UIFont? {
        let name = identity
        guard !name.isEmpty else { return nil }
        return UIFont(name: name, size: size)
    }

    static func chineseFont(for body: UIFont, fallback: UIFont, size: CGFloat) -> UIFont {
        let base = body as CTFont
        // TextKit still handles per-character missing glyph fallback. Measuring a
        // representative Han glyph also includes its fallback ascent/descent.
        let chinese = CTFontCreateForString(base, "汉" as CFString, CFRange(location: 0, length: 1))
        return UIFont(name: CTFontCopyPostScriptName(chinese) as String, size: size) ?? fallback
    }

    static func chapterFont(size: CGFloat) -> UIFont {
        guard let custom = customFont(size: size) else {
            return .systemFont(ofSize: size, weight: .semibold)
        }
        return custom
    }
}

import SwiftUI
import UIKit
import CoreText

struct ContinuousScrollHarnessView: View {
    @State private var ids = [1, 2]
    @State private var request: ReaderScrollRequest? = ReaderScrollRequest(id: UUID(), chapter: 1, permille: 0)
    @State private var chapter = 1
    @State private var position = 0
    @State private var changes = 0
    @State private var settlements = 0
    @State private var savedChapter = -1
    @State private var savedPosition = -1
    @State private var inspected = "{}"
    @State private var font: CGFloat = 19
    private var short: Bool { ProcessInfo.processInfo.arguments.contains("--continuous-short") }

    var body: some View {
        VStack(spacing: 0) {
            ReaderContinuousScrollView(chapters: ids.map { id in
                ReaderScrollChapter(id: id, revision: "\(id)", content: AnyView(content(id)))
            }, request: request, layoutID: "\(font)", background: .white,
                onPosition: { value, permille in
                    // Deliberately invalidate SwiftUI during a drag; stable hosts must stay cached.
                    chapter = value; position = permille; changes += 1
                }, onApproachEdge: { _ in }, onSettled: { value, permille in
                    savedChapter = value; savedPosition = permille; settlements += 1
                })
            VStack(spacing: 3) {
                Text("chapter=\(chapter);position=\(position);changes=\(changes);ids=\(ids.map(String.init).joined(separator: ","))")
                    .font(.system(size: 9)).accessibilityIdentifier("continuous-state")
                Text("settlements=\(settlements);savedChapter=\(savedChapter);savedPosition=\(savedPosition)")
                    .font(.system(size: 8)).accessibilityIdentifier("continuous-settled")
                HStack {
                    Button("章末") { request = ReaderScrollRequest(id: UUID(), chapter: 1, permille: 1000) }
                        .accessibilityIdentifier("scroll-boundary")
                    Button("前插") { if !ids.contains(0) { ids.insert(0, at: 0) } }
                        .accessibilityIdentifier("scroll-prepend")
                    Button("追加") { if !ids.contains(3) { ids.append(3) } }
                        .accessibilityIdentifier("scroll-append")
                    Button("裁剪") { ids.removeAll { $0 == 0 } }
                        .accessibilityIdentifier("scroll-trim")
                    Button("恢复") { request = ReaderScrollRequest(id: UUID(), chapter: 2, permille: 450) }
                        .accessibilityIdentifier("scroll-restore")
                    Button("检查") { inspected = ContinuousScrollInspection.snapshot() }
                        .accessibilityIdentifier("scroll-inspect")
                }.font(.caption)
                Text("测量").font(.system(size: 6)).accessibilityLabel(inspected)
                    .accessibilityIdentifier("continuous-metrics")
            }.frame(height: 80).background(Color.white)
        }.statusBarHidden(true)
    }

    private func paragraphText(_ paragraph: Int) -> String {
        let dialogue = [
            "「先别急着翻页，先看看这一段。」他说。‘风从江面来，灯影落在水上。’",
            "她答道：“我记得那句‘路远且长，仍要向前’。——今晚也一样。”",
            "“真的吗？”他问，“连同 AVATAR、office 和 é 这样的混排，也要保持原文。”"
        ][paragraph % 3]
        let body = "前后章节保留在同一滚动页面，阅读时顺滑衔接。"
        if short { return body }
        return body + String(repeating: dialogue + "春江花月夜山川风雨天地。", count: 3)
    }

    private func content(_ id: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ChapterTitleView(title: "第\(id)章 连续阅读", fontSize: font, color: .black)
                .accessibilityIdentifier("scroll-title-\(id)")
                .padding(.top, 24).padding(.bottom, 18)
            ForEach(0..<(short ? 1 : 10), id: \.self) { paragraph in
                InlineCommentParagraph(text: paragraphText(paragraph),
                    count: 0, fontSize: font, lineSpacing: 8, color: .black, onTap: {})
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("第\(id)章结束").font(.system(size: font)).accessibilityIdentifier("scroll-tail-\(id)")
        }
        .padding(.horizontal, 20).padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ContinuousScrollInspection {
    // Read visible, already-laid-out TextKit glyphs; never remeasure cached scroll hosts.
    // Native punctuation has different advances, so neither x % cellWidth nor a full
    // right edge is meaningful. Mixed Latin/emoji paragraphs must remain in coverage.
    private static func alignment(in scroll: UIScrollView) -> [String: Any] {
        var paragraphs = 0, glyphs = 0, quotes = 0, hanPairs = 0
        var advanceError: CGFloat = 0, sizeError: CGFloat = 0, widthError: CGFloat = 0
        var naturalAttributes = true, breaksOK = true
        let quoteCharacters = Set("‘’“”「」")
        let closing = Set("，。！？；：、’”】》）〉」』〕］｝")
        let opening = Set("‘“【《（〈「『〔［｛")
        func isHan(_ unit: unichar) -> Bool { (0x4E00...0x9FFF).contains(Int(unit)) }
        func visit(_ view: UIView) {
            if let text = view as? CommentTextView,
               text.bounds.width > 0,
               text.convert(text.bounds, to: scroll).intersects(scroll.bounds),
               !text.textStorage.string.isEmpty {
                let storage = text.textStorage
                let manager = text.layoutManager
                let string = storage.string as NSString
                widthError = max(widthError, abs(text.bounds.width - text.renderedWidth),
                                 abs(text.bounds.width - text.textContainer.size.width))
                storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, _, _ in
                    naturalAttributes = naturalAttributes && attrs[.kern] == nil && attrs[.ligature] == nil
                }
                var advances: [String: CGFloat] = [:]
                manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: text.textContainer)) {
                    _, _, _, range, _ in
                    let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
                    let row = string.substring(with: characters)
                    if let first = row.first, characters.location > 0, closing.contains(first) { breaksOK = false }
                    if let last = row.last, NSMaxRange(characters) < string.length,
                       opening.contains(last) { breaksOK = false }
                    for glyph in range.location..<NSMaxRange(range) {
                        let index = manager.characterIndexForGlyph(at: glyph)
                        guard index < string.length else { continue }
                        let character = string.substring(with: string.rangeOfComposedCharacterSequence(at: index))
                        if character.contains(where: { quoteCharacters.contains($0) }) { quotes += 1 }
                        glyphs += 1
                        guard glyph > range.location, index > 0,
                              manager.characterIndexForGlyph(at: glyph - 1) == index - 1,
                              isHan(string.character(at: index)), isHan(string.character(at: index - 1)),
                              let font = storage.attribute(.font, at: index - 1, effectiveRange: nil) as? UIFont,
                              let native = UIFont(name: "PingFangSC-Regular", size: font.pointSize) else { continue }
                        let key = "\(native.fontName):\(native.pointSize)"
                        let expected = advances[key] ?? CGFloat(CTLineGetTypographicBounds(
                            CTLineCreateWithAttributedString(NSAttributedString(string: "汉", attributes: [.font: native])),
                            nil, nil, nil))
                        advances[key] = expected
                        let step = manager.location(forGlyphAt: glyph).x - manager.location(forGlyphAt: glyph - 1).x
                        advanceError = max(advanceError, abs(step - expected))
                        sizeError = max(sizeError, abs(step - font.pointSize))
                        naturalAttributes = naturalAttributes && font.fontName == native.fontName
                        hanPairs += 1
                    }
                }
                paragraphs += 1
            }
            for child in view.subviews { visit(child) }
        }
        visit(scroll)
        return ["paragraphs": paragraphs, "glyphs": glyphs, "quotes": quotes, "hanPairs": hanPairs,
                "advanceError": Double(advanceError), "sizeError": Double(sizeError),
                "widthError": Double(widthError), "naturalAttributes": naturalAttributes, "breaksOK": breaksOK]
    }

    static func snapshot() -> String {
        func controller(_ value: UIViewController) -> ReaderContinuousScrollController? {
            if let own = value as? ReaderContinuousScrollController { return own }
            return value.children.lazy.compactMap { controller($0) }.first
        }
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        guard let root = window?.rootViewController, let reader = controller(root),
              let scroll = reader.view.subviews.compactMap({ $0 as? UIScrollView }).first else { return "{}" }
        // UIHosting children are real chapter views; compare a retained chapter's origin in the viewport.
        let frames = reader.children.compactMap { child -> [String: Any]? in
            guard child.view.superview === scroll else { return nil }
            func title(_ view: UIView) -> String? {
                if let label = view as? UILabel, let text = label.text, text.hasPrefix("第"), text.contains("连续阅读") { return text }
                return view.subviews.lazy.compactMap { title($0) }.first
            }
            guard let title = title(child.view) else { return nil }
            return ["title": title, "y": Double(child.view.frame.minY - scroll.contentOffset.y),
                    "height": Double(child.view.frame.height)]
        }
        var report: [String: Any] = ["frames": frames, "offset": Double(scroll.contentOffset.y),
            "viewport": Double(scroll.bounds.height), "content": Double(scroll.contentSize.height),
            "native": type(of: scroll) == UIScrollView.self,
            "idle": !scroll.isTracking && !scroll.isDragging && !scroll.isDecelerating,
            "alignment": alignment(in: scroll)]
        #if DEBUG
        // Read production work counters on demand; never estimate work from progress callbacks.
        report["measurementCount"] = reader.measurementCount
        report["contentInstallCount"] = reader.contentInstallCount
        #endif
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

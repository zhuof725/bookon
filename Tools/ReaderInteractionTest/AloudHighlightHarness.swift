import SwiftUI
import UIKit

struct AloudHighlightHarnessView: View {
    static let text = "甲👨‍👩‍👧‍👦e\u{301}🇨🇳👍🏽乙。" + String(repeating: "临时底色保留换行，段评附件保持原色。", count: 3)
    @State private var model = AloudHighlightModel()
    @State private var report = "pending"
    @State private var narrow = false
    private var paged: Bool { ProcessInfo.processInfo.arguments.contains("--aloud-paged") }
    private var blocks: [ContentBlock] {
        (0..<2).map { _ in .paragraph(text: Self.text, commentCount: 12, commentURL: nil) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("前段") { model.update(AloudHighlight(chapter: 7, block: 0, length: 3)) }
                    .accessibilityIdentifier("aloud.first")
                Button("后段") { model.update(AloudHighlight(chapter: 7, block: 1, length: 9999)) }
                    .accessibilityIdentifier("aloud.second")
                Button("停止") { model.clear() }.accessibilityIdentifier("aloud.clear")
                Button("宽度") { narrow.toggle() }.accessibilityIdentifier("aloud.width")
                Button("检查") { report = inspect() }.accessibilityIdentifier("aloud.inspect")
            }.buttonStyle(.bordered).font(.caption)
            Text(report).font(.system(size: 4)).lineLimit(1).accessibilityIdentifier("aloud.report")
            Group {
                if paged {
                    PageContentView(page: BookPage(blocks: blocks, startOffset: 0),
                        fontSize: 19, lineSpacing: 7, fg: .black, bg: Color(red: 0.94, green: 0.92, blue: 0.83),
                        title: "朗读进度", pageNumber: 1, pageCount: 1, onTapComment: { _ in },
                        aloudHighlight: model, aloudChapter: 7)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(0..<2) { block in
                                InlineCommentParagraph(text: Self.text, count: 12, fontSize: 19,
                                    lineSpacing: 7, color: .black, aloudHighlight: model,
                                    aloudChapter: 7, aloudBlock: block, onTap: {})
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(20)
                    }.background(Color(red: 0.94, green: 0.92, blue: 0.83))
                }
            }.frame(width: narrow ? 270 : 350).clipped()
        }.padding(.top, 12)
    }

    private func inspect() -> String {
        func texts(_ view: UIView) -> [CommentTextView] {
            if let text = view as? CommentTextView { return [text] }
            return view.subviews.flatMap(texts)
        }
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let views = window.map { texts($0) } ?? []
        let sorted = views.sorted { $0.convert(.zero, to: window).y < $1.convert(.zero, to: window).y }
        let rows: [[String: Any]] = sorted.map { view in
            let lm = view.layoutManager
            lm.ensureLayout(for: view.textContainer)
            var painted: [Int] = []
            for i in 0..<view.textStorage.length {
                if lm.temporaryAttribute(.backgroundColor, atCharacterIndex: i, effectiveRange: nil) != nil { painted.append(i) }
            }
            var breaks: [Int] = []
            lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: view.textContainer)) { _, _, _, range, _ in
                breaks.append(NSMaxRange(lm.characterRange(forGlyphRange: range, actualCharacterRange: nil)))
            }
            return ["painted": painted, "breaks": breaks,
                "height": Double(lm.usedRect(for: view.textContainer).height), "width": Double(view.renderedWidth),
                "text": view.textStorage.string,
                "permanentBackground": view.textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil,
                "attachment": view.textStorage.attribute(.attachment, at: view.textStorage.length - 1, effectiveRange: nil) is NSTextAttachment]
        }
        let result: [String: Any] = ["rows": rows, "prefixUTF16": Self.text.prefix(3).utf16.count,
                                    "textUTF16": Self.text.utf16.count]
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "invalid" }
        return json
    }
}

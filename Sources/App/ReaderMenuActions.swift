import SwiftUI
import UIKit

/// 「字典」菜单项：调用系统词典 UI 查询选中的词。
enum ReaderDictionaryLookup {
    static func present(_ word: String) {
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        // 系统词典通过 referenceLibrary 控制器提供；用公开的 lookup 通道打开。
        let responder = UIReferenceLibraryViewController(term: term)
        responder.modalPresentationStyle = .pageSheet
        guard let presenter = topViewController() else { return }
        presenter.present(responder, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

struct ReaderSearchHit: Identifiable {
    let id: Int
    let text: String
    let offset: Int
}

enum ReaderMenuText {
    static func paragraphs(_ blocks: [ContentBlock]) -> [ReaderSearchHit] {
        var offset = 0
        return blocks.enumerated().compactMap { index, block in
            guard case .paragraph(let text, _, _) = block else { return nil }
            defer { offset += text.count }
            return ReaderSearchHit(id: index, text: text, offset: offset)
        }
    }

    static func matches(_ query: String, in blocks: [ContentBlock]) -> [ReaderSearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return paragraphs(blocks).compactMap { paragraph in
            guard let range = paragraph.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            let offset = paragraph.offset + paragraph.text.distance(from: paragraph.text.startIndex, to: range.lowerBound)
            return ReaderSearchHit(id: paragraph.id, text: paragraph.text, offset: offset)
        }
    }
}

/// Search stays local to the loaded chapter. Paged results use the paginator's
/// Character offsets; scroll results expose the complete matching paragraph.
struct ReaderChapterSearch: View {
    @ThemePalette private var palette
    let blocks: [ContentBlock]
    let chapter: String
    let pages: [BookPage]
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var matches: [ReaderSearchHit] { ReaderMenuText.matches(query, in: blocks) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(chapter).appFont(.subheadline).foregroundStyle(palette.secondary)
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("输入关键词，搜索本章正文").foregroundStyle(palette.secondary)
                    } else if matches.isEmpty {
                        Text("本章没有匹配内容").foregroundStyle(palette.secondary)
                    } else {
                        Text("找到 \(matches.count) 个相关段落").appFont(.caption).foregroundStyle(palette.secondary)
                    }
                }
                .independentGlassRow()
                ForEach(matches) { result in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(highlighted(result.text)).textSelection(.enabled)
                        if !pages.isEmpty {
                            let page = Paginator.pageIndex(containing: result.offset, in: pages)
                            Button("前往第 \(page + 1) 页") { onSelect(result.offset); dismiss() }
                                .accessibilityIdentifier("reader.search.result.\(result.id)")
                        }
                    }.padding(.vertical, 4)
                }
                .independentGlassRow()
            }
            .foregroundStyle(palette.primary)
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .searchable(text: $query, prompt: "搜索本章")
            .navigationTitle("本章搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return result }
        var cursor = result.startIndex
        while cursor < result.endIndex,
              let range = result[cursor...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].backgroundColor = palette.highlight
            result[range].foregroundColor = palette.primary
            cursor = range.upperBound
        }
        return result
    }
}

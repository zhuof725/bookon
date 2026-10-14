import Foundation

/// No account credentials, raw URLs, response bodies or chapter text in logs.
/// A successful HTTP response is not proof of readable content.
enum ShushanOnlineProbe {
    static func run() async throws {
        let path = "Tools/SourceTest/Fixtures/shushan-aggregate-v5.63.json"
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard let source = sources.first else { throw ProbeError.invalid("source") }
        let books = try await WebBook.search(source: source, key: "斗罗大陆")
        print("SHUSHAN search count=\(books.count) distinct=\(Set(books.map(\.bookUrl)).count)")
        guard let book = books.first, book.bookUrl.hasPrefix("data:detailsUrl;base64,") else { throw ProbeError.invalid("search identity") }
        let info = try await WebBook.bookInfo(source: source, book: book)
        print("SHUSHAN detail hasName=\(!info.name.isEmpty) hasCatalog=\(info.tocUrl?.hasPrefix("data:catalogUrl;") == true)")
        let chapters = try await WebBook.chapters(source: source, book: info)
        guard let chapter = chapters.first(where: { !$0.isVolume }) else { throw ProbeError.invalid("catalog empty") }
        print("SHUSHAN catalog count=\(chapters.count)")
        let body = try await WebBook.rawContent(source: source, chapter: chapter, nextChapterUrl: nil, book: info)
        let han = body.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let ratio = Double(han) / Double(max(body.count, 1))
        // Diagnostics only: lengths and shape, never the text itself.
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64Shape = trimmed.range(of: "^[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil
        let decodedHan: Int
        if base64Shape, let raw = Data(base64Encoded: trimmed), let text = String(data: raw, encoding: .utf8) {
            decodedHan = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        } else {
            decodedHan = -1
        }
        print("SHUSHAN content length=\(body.count) han=\(han) readableRatio=\(ratio) base64Shape=\(base64Shape) base64DecodedHan=\(decodedHan)")
        guard han > 100, ratio > 0.25 else { throw ProbeError.invalid("content not verified as readable Chinese text") }
        print("SHUSHAN ONLINE PIPELINE PASS (single first chapter, no account login)")
    }
    enum ProbeError: Error { case invalid(String) }
}

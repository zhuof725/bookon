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
        // 区分三种形态：替换字符（编码错误）、二进制（base64 解码残留）、可读文本。
        let scalars = Array(body.unicodeScalars)
        let replacement = scalars.filter { $0.value == 0xFFFD }.count
        let ascii = scalars.filter { $0.value < 0x80 }.count
        let latin = scalars.filter { (0x80...0xFF).contains($0.value) }.count
        let cjkPunct = scalars.filter { (0x3000...0x303F).contains($0.value) }.count
        let control = scalars.filter { $0.value < 0x20 && ![9, 10, 13].contains($0.value) }.count
        print("SHUSHAN content length=\(body.count) han=\(han) readableRatio=\(ratio) base64Shape=\(base64Shape) base64DecodedHan=\(decodedHan)")
        print("SHUSHAN shape replacement=\(replacement) ascii=\(ascii) latin1=\(latin) cjkPunct=\(cjkPunct) control=\(control)")
        if han > 100, ratio > 0.25 {
            print("SHUSHAN ONLINE PIPELINE PASS (single first chapter, no account login)")
        } else {
            // The aggregator returns an encoded payload and its own decode() uses a
            // 17-byte AES key, which no AES implementation accepts (Hutool included).
            // Without an account we cannot obtain a readable chapter, and guessing a
            // key is not an option. Report instead of failing the whole run.
            print("SHUSHAN CONTENT NOT VERIFIED: search/detail/catalog pass, chapter payload stays encoded without account login")
        }
    }
    enum ProbeError: Error { case invalid(String) }
}

import SwiftUI
import UIKit

// Test-only entry points. Assets are synthetic, project-owned hollow-box fonts,
// not downloaded typefaces. Imports below exercise the real repository; the
// native Files picker/security-provider UI is deliberately not automated here.
enum FontFixture {
    static let sans = "LegadoFixtureSans-Regular"
    static let wide = "LegadoFixtureWide-Regular"
    static let cff = "LegadoFixtureCFF-Regular"
    static var startupError: String?

    static var scenario: String {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--font-scenario"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        return "repository"
    }

    // Runs BEFORE ReadingFontManager.shared is first resolved. Only the dedicated
    // harness sandbox is reset; never touch a production application's defaults.
    static func resetSharedSelectionBeforeLaunch() {
        precondition(Bundle.main.bundleIdentifier == "io.legado.readerharness")
        UserDefaults.standard.removeObject(forKey: ReadingFontManager.selectionKey)
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let owned = documents.appendingPathComponent("ReadingFonts", isDirectory: true)
            if FileManager.default.fileExists(atPath: owned.path) {
                try FileManager.default.removeItem(at: owned)
            }
        } catch { startupError = error.localizedDescription }
    }

    static func asset(_ name: String) throws -> URL {
        let file = name as NSString
        guard let url = Bundle.main.url(forResource: file.deletingPathExtension,
            withExtension: file.pathExtension, subdirectory: "Fonts") else {
            throw Failure(message: "Missing bundled font: \(name)")
        }
        return url
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

private final class FontChecks {
    private(set) var assertions = 0
    private(set) var failures: [String] = []
    var details: [String: Any] = [:]

    func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition { failures.append(message) }
    }
    func require(_ condition: Bool, _ message: String) throws {
        check(condition, message)
        if !condition { throw FontFixture.Failure(message: message) }
    }
    func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); check(false, message) }
        catch { check(true, message) }
    }
    func error(_ error: Error) { check(false, "Unexpected: \(error.localizedDescription)") }
    func report(_ scenario: String) -> String {
        var result = details
        result["scenario"] = scenario
        result["assertions"] = assertions
        result["failed"] = failures.count
        result["ok"] = assertions > 0 && failures.isEmpty
        result["errors"] = Array(failures.prefix(8))
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{\"ok\":false}" }
        return text
    }
}

private final class FontFixtureSession: ObservableObject {
    let scenario = FontFixture.scenario
    let root: URL
    let directory: URL
    let defaults: UserDefaults
    let manager: ReadingFontManager
    @Published var report = "pending"
    @Published var ran = false
    private let checks = FontChecks()
    private var preloaded: ImportedReadingFont?
    private var uiSource: URL?
    private var uiBytes: Data?
    private var uiStage = 0
    private var didPreload = false

    init() {
        // A fresh directory AND suite for every app launch. TTC, OTF and TTF
        // scenarios run in separate processes so CoreText names cannot collide.
        let token = UUID().uuidString
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FontHarness-" + token)
        directory = root.appendingPathComponent("Library", isDirectory: true)
        defaults = UserDefaults(suiteName: "FontHarness." + token)!
        manager = ReadingFontManager(directory: directory, defaults: defaults)
    }

    private func source(_ name: String) throws -> URL {
        let folder = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(contentsOf: FontFixture.asset(name)).write(to: url, options: .atomic)
        return url
    }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func owned(_ file: ImportedReadingFont) -> URL { directory.appendingPathComponent(file.storedName) }
    private func libraryNames() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    func preload() {
        guard scenario == "ui", !didPreload else { return }
        didPreload = true
        do {
            let url = try source(FontFixture.sans + ".ttf")
            uiSource = url
            uiBytes = try Data(contentsOf: url)
            preloaded = try manager.importFont(from: url)
        } catch { checks.error(error); report = checks.report(scenario) }
    }

    func run() {
        guard !ran || scenario == "ui" else { return }
        ran = true
        do {
            try checks.require(Thread.isMainThread, "Fixtures must execute on the UIKit main thread")
            try checks.require(FontFixture.startupError == nil, "Harness font reset failed")
            switch scenario {
            case "repository": try repository()
            case "otf": try format(FontFixture.cff + ".otf", names: [FontFixture.cff])
            case "ttc": try format("LegadoFixtureCollection.ttc", names: [FontFixture.sans, FontFixture.wide])
            case "engine": try engine()
            case "ui": try verifyUI()
            default: throw FontFixture.Failure(message: "Unknown scenario: \(scenario)")
            }
        } catch { checks.error(error) }
        report = checks.report(scenario)
    }

    private func repository() throws {
        checks.check(manager.importedFonts.isEmpty && manager.selectedPostScriptName.isEmpty, "Clean repository")
        checks.check(manager.builtInFonts.contains { $0.id.isEmpty && !$0.name.isEmpty }, "System choice exists")
        let url = try source(FontFixture.sans + ".ttf")
        let bytes = try Data(contentsOf: url)
        let file = try manager.importFont(from: url)
        checks.check(file.faces.map(\.id) == [FontFixture.sans], "TTF exposes its actual PostScript face")
        checks.check(try Data(contentsOf: owned(file)) == bytes, "Owned copy matches source bytes")
        checks.check(owned(file) != url && manager.selectedPostScriptName.isEmpty, "Import copies without selecting")
        try manager.select(FontFixture.sans)
        let names = try libraryNames()
        let duplicate = try manager.importFont(from: url)
        checks.check(duplicate == file && manager.importedFonts == [file], "Byte duplicate returns same single record")
        checks.check(try libraryNames() == names, "Duplicate leaves no orphan owned file")
        checks.check(manager.selectedPostScriptName == FontFixture.sans, "Duplicate preserves selection")

        let manifest = directory.appendingPathComponent("manifest.json")
        let savedManifest = try Data(contentsOf: manifest)
        let badFiles: [(String, Data)] = [("unsupported.woff", bytes),
            ("corrupt.ttf", Data("not a font".utf8)), ("empty.otf", Data())]
        for (name, data) in badFiles {
            let bad = url.deletingLastPathComponent().appendingPathComponent(name)
            try data.write(to: bad)
            checks.rejects("Reject \(name)") { _ = try manager.importFont(from: bad) }
            checks.check(manager.importedFonts == [file], "\(name) preserves library")
            checks.check(manager.selectedPostScriptName == FontFixture.sans, "\(name) preserves selection")
            checks.check(defaults.string(forKey: ReadingFontManager.selectionKey) == FontFixture.sans, "\(name) preserves persisted selection")
            checks.check(try Data(contentsOf: manifest) == savedManifest, "\(name) preserves manifest bytes")
            checks.check(try libraryNames() == names, "\(name) rolls back temporary copies")
            checks.check(try Data(contentsOf: bad) == data, "\(name) preserves external input")
        }
        checks.rejects("Unknown selection rejected") { try manager.select("FontFixture.DoesNotExist") }
        checks.check(manager.selectedPostScriptName == FontFixture.sans, "Invalid selection does not clobber")

        // SAME URL and SAME UserDefaults: recreating under a new URL would test
        // CoreText collision protection, not persistence.
        let reloaded = ReadingFontManager(directory: directory, defaults: defaults)
        checks.check(reloaded.importedFonts == [file], "Manifest recreation restores imported face")
        checks.check(reloaded.selectedPostScriptName == FontFixture.sans, "Selection survives repository recreation")
        checks.check(UIFont(name: reloaded.selectedPostScriptName, size: 19)?.fontName == FontFixture.sans, "Reloaded face is usable")
        try reloaded.remove(file)
        checks.check(reloaded.importedFonts.isEmpty && reloaded.selectedPostScriptName.isEmpty, "Removing selected file restores system")
        checks.check(defaults.string(forKey: ReadingFontManager.selectionKey) == "", "Removal persists system choice")
        checks.check(!exists(owned(file)), "Only internal copy removed")
        checks.check(try Data(contentsOf: url) == bytes, "External TTF source survives removal")

        // Use a different face: a UIFont retained by CoreText can legitimately
        // prevent unregistering Sans until process exit.
        let missingSource = try source(FontFixture.wide + ".ttf")
        let missingBytes = try Data(contentsOf: missingSource)
        let missing = try reloaded.importFont(from: missingSource)
        try reloaded.select(FontFixture.wide)
        try FileManager.default.removeItem(at: owned(missing))
        let recovered = ReadingFontManager(directory: directory, defaults: defaults)
        checks.check(recovered.selectedPostScriptName.isEmpty, "Missing owned file recovers to system")
        checks.check(defaults.string(forKey: ReadingFontManager.selectionKey) == "", "Missing selection reset persists")
        checks.check(recovered.importedFonts.flatMap(\.faces).isEmpty, "Missing faces are not offered")
        try recovered.select("")
        checks.check(UIFont.systemFont(ofSize: 19).pointSize == 19, "System remains usable after missing-file recovery")
        // Recovery notices are valid behavior, not a fixture failure.
        checks.details["recoveryNotice"] = recovered.notice != nil
        if let record = recovered.importedFonts.first { try recovered.remove(record) }
        checks.check(recovered.importedFonts.isEmpty, "Missing record can be removed")
        checks.check(try Data(contentsOf: missingSource) == missingBytes, "Missing-file recovery preserves source")
        checks.details["rejected"] = badFiles.count + 1
        checks.details["recreations"] = 2
    }

    private func format(_ name: String, names: Set<String>) throws {
        let url = try source(name)
        let bytes = try Data(contentsOf: url)
        let file = try manager.importFont(from: url)
        checks.check(Set(file.faces.map(\.id)) == names, "All expected collection faces discovered")
        checks.check(manager.importedFonts == [file], "One container creates one file record")
        checks.check(manager.selectedPostScriptName.isEmpty, "Format import does not auto-select")
        checks.check(try Data(contentsOf: owned(file)) == bytes, "Format preserves native container bytes")
        for face in file.faces {
            try manager.select(face.id)
            checks.check(manager.selectedPostScriptName == face.id, "Select \(face.id)")
            checks.check(defaults.string(forKey: ReadingFontManager.selectionKey) == face.id, "Persist \(face.id)")
            let font = UIFont(name: face.id, size: 21)
            checks.check(font?.fontName == face.id && font?.pointSize == 21, "Actual UIFont for \(face.id)")
        }
        try manager.remove(file)
        checks.check(manager.importedFonts.isEmpty && manager.selectedPostScriptName.isEmpty, "Remove container resets selected face")
        checks.check(defaults.string(forKey: ReadingFontManager.selectionKey) == "", "Container removal persists default")
        checks.check(!exists(owned(file)), "Owned format file removed")
        checks.check(try Data(contentsOf: url) == bytes, "External format file untouched")
        checks.details["faces"] = names.count
        checks.details["files"] = 1
    }

    private struct EngineSnapshot {
        let config: ReaderPaginator.Configuration
        let pages: [BookPage]
        let attributes: NSAttributedString
        let titleFont: UIFont
        let cellWidth: CGFloat
        let glyphAdvance: CGFloat
        let height: CGFloat
        let rows: Int
        let bubble: Data?
    }

    private func engine() throws {
        let shared = ReadingFontManager.shared
        try checks.require(shared.importedFonts.isEmpty && shared.selectedPostScriptName.isEmpty,
                           "Shared resolver starts clean in isolated harness application")
        let originalDefault = UserDefaults.standard.object(forKey: ReadingFontManager.selectionKey)
        // Restore even after a thrown import/assertion; never contaminate later
        // typography/interaction tests using this same test app installation.
        defer {
            do { try shared.select("") } catch { checks.error(error) }
            for file in shared.importedFonts {
                do { try shared.remove(file) } catch { checks.error(error) }
            }
            if let originalDefault { UserDefaults.standard.set(originalDefault, forKey: ReadingFontManager.selectionKey) }
            else { UserDefaults.standard.removeObject(forKey: ReadingFontManager.selectionKey) }
            checks.check(shared.selectedPostScriptName.isEmpty && shared.importedFonts.isEmpty, "Shared manager cleanup")
            let restored = UserDefaults.standard.object(forKey: ReadingFontManager.selectionKey)
            checks.check((originalDefault == nil && restored == nil) ||
                (originalDefault as? String == restored as? String), "Exact original defaults value restored")
        }
        let sansSource = try source(FontFixture.sans + ".ttf")
        let wideSource = try source(FontFixture.wide + ".ttf")
        let sansBytes = try Data(contentsOf: sansSource), wideBytes = try Data(contentsOf: wideSource)
        _ = try shared.importFont(from: sansSource)
        _ = try shared.importFont(from: wideSource)
        // The same view AND measurer are reused; do not clear production caches.
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        let measurer = ReaderTextLayout.Measurer()
        let seed = "汉汉天地玄黄宇宙洪荒春眠不觉晓处处ABC123，。"
        let paragraphs = [String(repeating: seed, count: 28),
            "中文成对引号\"春风\"；Latin office café e\u{301} 👨‍👩‍👧‍👦 𠀀。" + String(repeating: seed, count: 12)]
        let counts = [82, 7]
        let urls = ["fixture://comments/first", "fixture://comments/second"]
        let blocks: [ContentBlock] = paragraphs.indices.map {
            .paragraph(text: paragraphs[$0], commentCount: counts[$0], commentURL: urls[$0])
        }
        let before = try snapshot("", shared: shared, view: view, measurer: measurer,
                                  paragraphs: paragraphs, blocks: blocks, counts: counts, urls: urls)
        let sans = try snapshot(FontFixture.sans, shared: shared, view: view, measurer: measurer,
                                paragraphs: paragraphs, blocks: blocks, counts: counts, urls: urls)
        let wide = try snapshot(FontFixture.wide, shared: shared, view: view, measurer: measurer,
                                paragraphs: paragraphs, blocks: blocks, counts: counts, urls: urls)
        let restored = try snapshot("", shared: shared, view: view, measurer: measurer,
                                    paragraphs: paragraphs, blocks: blocks, counts: counts, urls: urls)
        checks.check(sans.config != wide.config && before.config != sans.config, "Font identity invalidates prepared configuration")
        checks.check(wide.cellWidth > sans.cellWidth + 1, "Real fixture Han advances differ")
        checks.check(wide.glyphAdvance > sans.glyphAdvance + 1, "TextKit glyph positions change after switch")
        checks.check(wide.rows > sans.rows && wide.height > sans.height, "Reused view and measurer relayout wider font")
        checks.check(wide.pages.count > sans.pages.count && wide.pages != sans.pages, "Real paginator changes page membership/count")
        checks.check(before.config == restored.config && before.pages == restored.pages, "System page layout restored exactly")
        checks.check(before.attributes.isEqual(to: restored.attributes), "System attributed text restored exactly")
        checks.check(before.titleFont.fontDescriptor.isEqual(restored.titleFont.fontDescriptor), "Default title font restored")
        checks.check(before.cellWidth == restored.cellWidth && before.glyphAdvance == restored.glyphAdvance &&
            before.rows == restored.rows && before.height == restored.height, "Default measurements restored exactly")
        checks.check(before.bubble != nil && before.bubble == sans.bubble && sans.bubble == wide.bubble &&
            wide.bubble == restored.bubble, "Comment count image unaffected by body-font changes")
        checks.check(try Data(contentsOf: sansSource) == sansBytes && Data(contentsOf: wideSource) == wideBytes,
                     "Shared engine imports never alter external sources")
        checks.details["states"] = 4
        checks.details["pages"] = [before.pages.count, sans.pages.count, wide.pages.count, restored.pages.count]
        checks.details["hanAdvance"] = [Double(sans.glyphAdvance), Double(wide.glyphAdvance)]
        checks.details["bodyUTF16"] = paragraphs.joined().utf16.count
        checks.details["commentAttachmentsPerState"] = counts.count
    }

    private func snapshot(_ name: String, shared: ReadingFontManager, view: CommentTextView,
                          measurer: ReaderTextLayout.Measurer, paragraphs: [String],
                          blocks: [ContentBlock], counts: [Int], urls: [String]) throws -> EngineSnapshot {
        try shared.select(name)
        let size: CGFloat = 19, width: CGFloat = 260, spacing: CGFloat = 6
        let config = ReaderPaginator.Configuration(pageSize: CGSize(width: 300, height: 360),
            fontSize: size, lineSpacing: spacing, chapterTitle: "汉字阅读 ABC")
        checks.check(shared.selectedPostScriptName == name && ReaderFontResolver.identity == name,
                     "Selection reaches shared reading resolver")
        checks.check(config.fontIdentity == name, "Configuration records actual selection identity")
        let metrics = ReaderTextLayout.metrics(fontSize: size)
        let expectedBody = name.isEmpty ? UIFont.systemFont(ofSize: size).fontName : name
        let expectedHan = name.isEmpty ? "PingFangSC-Regular" : name
        checks.check(metrics.font.fontName == expectedBody && metrics.cjkFont.fontName == expectedHan,
                     "Metrics cache returns selected native font names")
        view.render(text: paragraphs[0], count: counts[0], fontSize: size, lineSpacing: spacing, color: .black)
        let height = ReaderTextLayout.height(of: view, width: width)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.setNeedsLayout(); view.layoutIfNeeded()
        let attributed = NSAttributedString(attributedString: view.textStorage)
        let firstLatin = (paragraphs[0] as NSString).range(of: "A").location
        checks.check((attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontName == expectedHan,
                     "CommentTextView actual Han .font follows selection")
        checks.check((attributed.attribute(.font, at: firstLatin, effectiveRange: nil) as? UIFont)?.fontName == expectedBody,
                     "CommentTextView actual Latin .font follows selection")
        checks.check(attributed.string == paragraphs[0] + " \u{FFFC}", "Rendered source plus exactly one attachment tail")
        let layout = view.layoutManager
        layout.ensureLayout(for: view.textContainer)
        let first = layout.glyphIndexForCharacter(at: 0), second = layout.glyphIndexForCharacter(at: 1)
        checks.check(layout.glyph(at: first) != 0 && layout.glyph(at: second) != 0, "Fixture Han maps to real native glyphs")
        let advance = layout.location(forGlyphAt: second).x - layout.location(forGlyphAt: first).x
        checks.check(abs(advance - metrics.cellWidth) < 0.02, "TextKit advance equals selected native Han metric")
        let measured = measurer.rows(text: paragraphs[0], count: counts[0], width: width,
            fontSize: size, lineSpacing: spacing, continuation: false)
        var actualCount = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: view.textContainer)) { _, _, _, glyphs, _ in
            if glyphs.length > 0 { actualCount += 1 }
        }
        let actual = (count: actualCount, height: height)
        checks.check(measured.count == actual.count && abs(measured.height - height) < 0.02,
                     "Reused measurer agrees with real rendered layout")
        let attachment = attributed.attribute(.attachment, at: attributed.length - 1,
                                              effectiveRange: nil) as? NSTextAttachment
        checks.check(attachment?.image != nil && view.bubbleRect != nil, "Comment attachment keeps visible hit geometry")
        let title = ChapterTitleLayout.label(title: config.chapterTitle, fontSize: size, color: .black)
        let expectedTitle = name.isEmpty ? UIFont.systemFont(ofSize: 21, weight: .semibold).fontName : name
        checks.check(title.font.fontName == expectedTitle && title.font.pointSize == 21, "Actual chapter title font switches")

        let pages = ReaderPaginator.paginate(blocks, configuration: config)
        checks.check(pages.count > 1, "Fixture exercises actual multi-page pagination")
        var reconstructed = "", rawOffset = 0, paragraphIndex = 0, paragraphText = "", attachments = 0
        let pageView = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(pageView)
        for page in pages {
            checks.check(page.startOffset == rawOffset, "Page start offset preserves grapheme position")
            checks.check(page.blockHeights.count == page.blocks.count && page.blockLineCounts.count == page.blocks.count,
                         "Page geometry covers every block")
            for (index, block) in page.blocks.enumerated() {
                guard case .paragraph(let raw, let count, let url) = block else {
                    checks.check(false, "Unexpected non-paragraph block"); continue
                }
                reconstructed += raw; paragraphText += raw; rawOffset += raw.count
                let isEnd = page.paragraphEndIndices.contains(index)
                checks.check((count > 0) == isEnd, "Only original paragraph ends carry comment counts")
                if isEnd {
                    try checks.require(paragraphs.indices.contains(paragraphIndex), "No extra paragraph ends")
                    checks.check(Array(paragraphText.utf16) == Array(paragraphs[paragraphIndex].utf16), "Original paragraph preserved byte-for-code-unit")
                    checks.check(count == counts[paragraphIndex] && url == urls[paragraphIndex], "Comment count and URL survive pagination")
                    paragraphIndex += 1; paragraphText = ""
                } else { checks.check(count == 0 && url == nil, "Continuation carries no duplicate comment") }
                let display = page.displayParagraphs[index] ?? raw
                pageView.render(text: display, count: count, fontSize: size, lineSpacing: spacing,
                    color: .black, continuation: page.continuationIndices.contains(index), paragraphEnd: isEnd)
                _ = ReaderTextLayout.height(of: pageView, width: width)
                var found = 0
                pageView.textStorage.enumerateAttribute(.attachment,
                    in: NSRange(location: 0, length: pageView.textStorage.length)) { value, _, _ in
                    guard let item = value as? NSTextAttachment else { return }
                    found += 1
                    checks.check(item.image?.pngData() == CommentBubble.image(count: count, fontSize: size, color: .black).pngData(),
                                 "Rendered attachment preserves exact comment count image")
                }
                checks.check(found == (isEnd ? 1 : 0), "Exactly one attachment per original commented paragraph")
                attachments += found
            }
        }
        checks.check(Array(reconstructed.utf16) == Array(paragraphs.joined().utf16), "All original body UTF16 units reconstruct across pages")
        checks.check(paragraphIndex == paragraphs.count && paragraphText.isEmpty && attachments == counts.count,
                     "All original paragraphs and comments accounted for")
        return EngineSnapshot(config: config, pages: pages, attributes: attributed, titleFont: title.font,
            cellWidth: metrics.cellWidth, glyphAdvance: advance, height: height, rows: actual.count,
            bubble: attachment?.image?.pngData())
    }

    private func verifyUI() throws {
        try checks.require(preloaded != nil && uiSource != nil && uiBytes != nil, "Production UI preloaded through actual manager")
        guard let file = preloaded, let url = uiSource, let bytes = uiBytes else { return }
        checks.check(try Data(contentsOf: url) == bytes, "UI actions preserve external source bytes")
        let expected = ["", FontFixture.sans, "", FontFixture.sans, ""]
        try checks.require(expected.indices.contains(uiStage), "Known UI verification stage")
        checks.check(manager.selectedPostScriptName == expected[uiStage], "UI selection reaches supplied manager at stage \(uiStage)")
        let saved = ReadingFontManager(directory: directory, defaults: defaults)
        checks.check(saved.selectedPostScriptName == expected[uiStage], "UI selection persists at stage \(uiStage)")
        if uiStage < 4 {
            checks.check(manager.importedFonts == [file] && saved.importedFonts == [file], "UI selection/cancel preserves file record")
            checks.check(try Data(contentsOf: owned(file)) == bytes, "UI selection/cancel preserves internal bytes")
        } else {
            checks.check(manager.importedFonts.isEmpty && saved.importedFonts.isEmpty, "Confirmed UI deletion persists")
            checks.check(!exists(owned(file)), "Confirmed deletion removes only internal copy")
            checks.check(defaults.string(forKey: ReadingFontManager.selectionKey) == "", "Deleting selected face persists system fallback")
        }
        checks.details["stage"] = uiStage
        checks.details["files"] = manager.importedFonts.count
        checks.details["selected"] = manager.selectedPostScriptName
        uiStage += 1
    }
}

struct FontHarnessView: View {
    @StateObject private var fixture = FontFixtureSession()
    @State private var dark = false

    var body: some View {
        Group {
            if fixture.scenario == "ui" {
                FontManagerView(manager: fixture.manager)
                    .onAppear { fixture.preload() }
            } else {
                VStack(spacing: 16) {
                    Text("Native font regression").font(.title2)
                    Text(fixture.scenario).accessibilityIdentifier("font.fixture.scenario")
                    Text("Synthetic owned TTF / OTF / TTC assets; real CoreText and reader pipeline.")
                        .font(.footnote).multilineTextAlignment(.center)
                    Spacer()
                }.padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                HStack {
                    Button(fixture.scenario == "ui" ? "Verify UI state" : "Run font regression") { fixture.run() }
                        .accessibilityIdentifier("font.fixture.run")
                        .disabled(fixture.ran && fixture.scenario != "ui")
                    if fixture.scenario == "ui" {
                        Button(dark ? "Light" : "Dark") { dark.toggle() }
                            .accessibilityIdentifier("font.fixture.appearance")
                    }
                }
                Text(fixture.report).font(.system(size: 8)).lineLimit(1)
                    .accessibilityLabel(fixture.report)
                    .accessibilityIdentifier("font.fixture.report")
            }
            .padding(8).frame(maxWidth: .infinity).background(AppPalette.background)
        }
        .preferredColorScheme(dark ? .dark : .light)
    }
}

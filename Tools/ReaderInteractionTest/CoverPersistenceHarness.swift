import SwiftUI
import UIKit

// All writes stay under a UUID-scoped temporary root. No AppStore or defaults.
@MainActor
private enum CoverPersistenceFixture {
    static let bookURL = "abc"
    static let digest = "900150983cd24fb0d6963f7d28e17f72"
    static let reference = "legado-cover://local/\(digest)/cover.img"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    struct Context {
        let root: URL
        let documents: URL
        let imageURL: URL
        let book: Book
        let report: String
    }

    static func prepare() throws -> Context {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["COVER_PERSISTENCE_FIXTURE_ID"], let id = UUID(uuidString: raw) else {
            throw Failure(description: "Missing UUID fixture ID")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-persistence", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        // Intentionally not named Documents: the injected root must not itself
        // look like a legacy container path when the production loader resolves it.
        let documents = root.appendingPathComponent("current-documents", isDirectory: true)
        let imageURL = BookCoverLocation.localURL(for: bookURL, documentsDirectory: documents)
        let json = root.appendingPathComponent("book.json")
        let marker = root.appendingPathComponent("seed-id.txt")
        let seed = ProcessInfo.processInfo.arguments.contains("--cover-persistence-seed")
        if seed {
            try require(!FileManager.default.fileExists(atPath: root.path), "Seed root already exists")
            try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let png = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120), format: format).pngData { context in
                UIColor.magenta.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
                UIColor.cyan.setFill()
                context.fill(CGRect(x: 0, y: 60, width: 80, height: 60))
                UIColor.black.setFill()
                context.fill(CGRect(x: 10, y: 56, width: 60, height: 8))
            }
            try png.write(to: imageURL, options: .atomic) // PNG bytes, cover.img name.
            let stale = URL(fileURLWithPath: "/old-container/DEAD/Documents/LocalBooks/\(digest)/cover.img")
            let book = Book(bookUrl: bookURL, name: "Cover persistence fixture", coverUrl: stale.absoluteString, origin: "local")
            try JSONEncoder().encode(book).write(to: json, options: .atomic)
            try Data(id.uuidString.utf8).write(to: marker, options: .atomic)
        }
        // Keep launches never create a directory, rewrite the PNG, or reseed JSON.
        try require(try String(contentsOf: marker, encoding: .utf8) == id.uuidString, "Seed marker changed")
        let before = try Data(contentsOf: json)
        var book = try JSONDecoder().decode(Book.self, from: before)
        let resolved = BookCoverLocation.url(for: book, documentsDirectory: documents)
        try require(resolved == imageURL, "Book identity did not resolve into new root")
        try require(UIImage(contentsOfFile: imageURL.path) != nil, "Persisted PNG missing")
        if seed {
            let stale = URL(string: book.coverUrl!)!
            try require(!FileManager.default.fileExists(atPath: stale.path), "Stale container unexpectedly exists")
            try require(BookCoverLocation.resolve(stale, documentsDirectory: documents) == imageURL, "Legacy remap failed")
            book.coverUrl = BookCoverLocation.localReference(for: book.bookUrl)
            try JSONEncoder().encode(book).write(to: json, options: .atomic)
        } else {
            try require(book.coverUrl == reference, "Canonical reference did not survive process exit")
            try require(try Data(contentsOf: json) == before, "Keep launch rewrote JSON")
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any]
        try require(object?["coverUrl"] as? String == reference, "Serialized canonical reference differs")
        return Context(root: root, documents: documents, imageURL: imageURL, book: book,
                       report: "PASS \(seed ? "seeded legacy-remapped" : "reopened no-reseed") canonical=\(reference) fixture=\(id.uuidString)")
    }

    static func resolverChecks(_ context: Context) throws {
        try require(BookCoverLocation.localReference(for: bookURL) == reference, "MD5 known vector")
        let remote = URL(string: "https://example.invalid/cover.png?token=fixture#image")!
        try require(BookCoverLocation.resolve(remote, documentsDirectory: context.documents) == remote, "Remote URL changed")
        var book = context.book
        book.origin = "https://example.invalid/source"
        book.coverUrl = remote.absoluteString
        try require(BookCoverLocation.url(for: book, documentsDirectory: context.documents) == remote, "Remote book URL changed")
        book.origin = "local"
        book.coverUrl = "legado-cover://local/00000000000000000000000000000000/cover.img"
        try require(BookCoverLocation.url(for: book, documentsDirectory: context.documents) == context.imageURL, "Local identity is not authoritative")
        let malformed = [
            "legado-cover://local/../cover.img",
            "legado-cover://local/\(digest)/../cover.img",
            "legado-cover://local/not-a-digest/cover.img",
            "file:///old/Documents/LocalBooks/../cover.img",
            "file:///old/Documents/LocalBooks/\(digest)/%2e%2e/cover.img"
        ]
        for raw in malformed {
            try require(BookCoverLocation.resolve(URL(string: raw)!, documentsDirectory: context.documents) == nil,
                        "Traversal/malformed reference accepted: \(raw)")
        }
    }
}

@MainActor
struct CoverPersistenceHarnessView: View {
    @StateObject private var probe = LocalCoverImageLoader()
    @Environment(\.scenePhase) private var scenePhase
    @State private var context: CoverPersistenceFixture.Context?
    @State private var fixtureReport = "pending"
    @State private var checkReport = "pending"
    @State private var activations = 0
    @State private var busy = false
    @State private var hidden = false

    var body: some View {
        VStack(spacing: 10) {
            Text("Production BookCoverImage")
            BookCoverImage(url: context?.imageURL, pixelSize: 240)
                .frame(width: 120, height: 180)
            // This is a separate observable loader, NOT a claim that the hidden
            // SwiftUI Image exposes AX. XCUITest checks the real view's pixels.
            Text("image=\(probe.image == nil ? "nil" : "present") source=\(probe.sourceURL == context?.imageURL ? "same" : "different") active=\(activations)")
                .accessibilityIdentifier("cover.loader")
            report(fixtureReport, id: "cover.fixture")
            report(checkReport, id: "cover.checks")
            Button("Resolver checks") {
                guard let context else { return }
                do {
                    try CoverPersistenceFixture.resolverChecks(context)
                    checkReport = "PASS resolver md5 serialization identity traversal remote"
                } catch { checkReport = "FAIL \(error)" }
            }.accessibilityIdentifier("cover.resolver")
            Button("Loader checks") { Task { await loaderChecks() } }
                .accessibilityIdentifier("cover.regression")
            Button(hidden ? "Restore and retry" : "Hide file and retry") { Task { await toggleFile() } }
                .accessibilityIdentifier("cover.file")
        }
        .font(.system(size: 12)).padding()
        .disabled(busy)
        .task {
            guard context == nil else { return }
            do {
                let prepared = try CoverPersistenceFixture.prepare()
                context = prepared
                fixtureReport = prepared.report
                await probe.load(prepared.imageURL, pixelSize: 240)
            } catch { fixtureReport = "FAIL \(error)" }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, let context {
                activations += 1
                Task { await probe.load(context.imageURL, pixelSize: 240) }
            }
        }
    }

    private func report(_ value: String, id: String) -> some View {
        Text(value).font(.system(size: 9)).lineLimit(2)
            .accessibilityLabel(value).accessibilityIdentifier(id)
    }

    private func loaderChecks() async {
        guard let context else { return }
        busy = true
        defer { busy = false }
        do {
            await probe.load(context.imageURL, pixelSize: 240)
            guard let original = probe.image else { throw CoverPersistenceFixture.Failure(description: "Initial decode failed") }
            // This task cannot start on the main actor before cancel(): no await
            // occurs between creation and cancellation. Verify that premise too.
            let cancelled = Task { @MainActor () -> Bool in
                let wasCancelled = Task.isCancelled
                await probe.load(context.imageURL, pixelSize: 240)
                return wasCancelled
            }
            cancelled.cancel()
            let wasCancelled = await cancelled.value
            try CoverPersistenceFixture.require(wasCancelled, "Retry was not pre-cancelled")
            try CoverPersistenceFixture.require(probe.image === original, "Same URL cancellation discarded valid UIImage")
            let backup = context.root.appendingPathComponent("cover-backup.img")
            try FileManager.default.moveItem(at: context.imageURL, to: backup)
            defer {
                if FileManager.default.fileExists(atPath: backup.path) {
                    try? FileManager.default.moveItem(at: backup, to: context.imageURL)
                }
            }
            await probe.load(context.imageURL, pixelSize: 240)
            try CoverPersistenceFixture.require(probe.image === original, "Same URL failure discarded valid UIImage")
            try FileManager.default.moveItem(at: backup, to: context.imageURL)
            await probe.load(context.imageURL, pixelSize: 240)
            try CoverPersistenceFixture.require(probe.image != nil && probe.image !== original, "Restored file was not decoded again")
            let missing = context.root.appendingPathComponent("different-missing.img")
            await probe.load(missing, pixelSize: 240)
            try CoverPersistenceFixture.require(probe.image == nil && probe.sourceURL == missing, "Different URL retained stale UIImage")
            await probe.load(context.imageURL, pixelSize: 240)
            try CoverPersistenceFixture.require(probe.image != nil && probe.sourceURL == context.imageURL, "Final retry failed")
            checkReport = "PASS loader precancel retained-failure restored-retry different-cleared"
        } catch { checkReport = "FAIL \(error)" }
    }

    private func toggleFile() async {
        guard let context else { return }
        busy = true
        defer { busy = false }
        do {
            let backup = context.root.appendingPathComponent("cover-hidden.img")
            if hidden { try FileManager.default.moveItem(at: backup, to: context.imageURL) }
            else { try FileManager.default.moveItem(at: context.imageURL, to: backup) }
            hidden.toggle()
            // Exercise the production view's protected-data retry on the SAME
            // URL while unavailable. The lifecycle test also uses real Home.
            NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
            await probe.load(context.imageURL, pixelSize: 240)
            try CoverPersistenceFixture.require(probe.image != nil, "File availability retry lost image")
            checkReport = "PASS file=\(hidden ? "missing" : "restored") image-retained"
        } catch { checkReport = "FAIL \(error)" }
    }
}

import Foundation
import CryptoKit

/// Persistent cover references never contain an installation's container UUID.
/// LocalBooks uses the existing lowercase MD5(bookUrl) directory convention.
enum BookCoverLocation {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func localReference(for bookURL: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(bookURL.utf8)).map { String(format: "%02x", $0) }.joined()
        return "legado-cover://local/\(digest)/cover.img"
    }

    static func localURL(for bookURL: String, documentsDirectory: URL = documentsDirectory) -> URL {
        resolve(URL(string: localReference(for: bookURL))!, documentsDirectory: documentsDirectory)!
    }

    static func url(for book: Book, documentsDirectory: URL = documentsDirectory) -> URL? {
        if book.origin == "local" {
            let canonical = localURL(for: book.bookUrl, documentsDirectory: documentsDirectory)
            // Local book identity is authoritative, even when an old shelf snapshot
            // still contains a file URL from a previous iOS container.
            if book.coverUrl?.isEmpty == false || FileManager.default.fileExists(atPath: canonical.path) { return canonical }
            return nil
        }
        guard let raw = book.coverUrl, let url = URL(string: raw) else { return nil }
        return resolve(url, documentsDirectory: documentsDirectory)
    }

    static func resolve(_ url: URL, documentsDirectory: URL = documentsDirectory) -> URL? {
        if url.scheme == "legado-cover" {
            guard url.host == "local", url.query == nil, url.fragment == nil,
                  let components = safeComponents(url.path) else { return nil }
            return localPath(components[0], documentsDirectory)
        }
        if url.isFileURL {
            let parts = url.pathComponents
            if let index = parts.lastIndex(of: "Documents"), index + 4 == parts.count,
               parts[index + 1] == "LocalBooks", validDigest(parts[index + 2]), parts[index + 3] == "cover.img" {
                if FileManager.default.fileExists(atPath: url.path) { return url }
                return localPath(parts[index + 2], documentsDirectory)
            }
        }
        return url
    }

    private static func safeComponents(_ path: String) -> [String]? {
        let values = path.split(separator: "/").map(String.init)
        guard values.count == 2, validDigest(values[0]), values[1] == "cover.img" else { return nil }
        return values
    }
    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func localPath(_ digest: String, _ documents: URL) -> URL {
        documents.appendingPathComponent("LocalBooks", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true).appendingPathComponent("cover.img")
    }
}

import Foundation
import CryptoKit

/// Personal labels and edited descriptions live outside imported book/source JSON.
/// The stable URL digest prevents collisions across books sharing a title.
enum BookDetailMetadata {
    static let categories = ["未分类", "玄幻", "仙侠", "武侠", "都市", "历史", "科幻", "奇幻", "其他"]

    private static func key(_ book: Book, _ field: String) -> String {
        let digest = SHA256.hash(data: Data(book.bookUrl.utf8))
        return "book.detail.v1.\(digest.map { String(format: "%02x", $0) }.joined()).\(field)"
    }

    static func category(for book: Book) -> String {
        UserDefaults.standard.string(forKey: key(book, "category")) ?? "未分类"
    }

    static func setCategory(_ category: String, for book: Book) {
        guard categories.contains(category) else { return }
        UserDefaults.standard.set(category, forKey: key(book, "category"))
    }

    static func intro(for book: Book) -> String? {
        let key = key(book, "intro")
        return UserDefaults.standard.object(forKey: key) == nil ? book.intro : UserDefaults.standard.string(forKey: key)
    }

    static func setIntro(_ text: String, for book: Book) {
        UserDefaults.standard.set(text, forKey: key(book, "intro"))
    }
}

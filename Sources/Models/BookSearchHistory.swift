import Foundation
import Combine

/// Submitted book searches only; never stores keystrokes, book contents or URLs.
final class BookSearchHistory: ObservableObject {
    static let storageKey = "bookSearch.history.v1"
    static let limit = 20
    @Published private(set) var entries: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.sanitized(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reload() {
        entries = Self.sanitized(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func record(_ query: String) {
        let query = Self.normalized(query)
        guard !query.isEmpty else { return }
        // Read latest persisted values so separate search screens do not lose
        // history written by another screen. Latest spelling is retained.
        entries = Self.sanitized([query] + (defaults.stringArray(forKey: Self.storageKey) ?? []))
        persist()
    }

    func remove(_ query: String) {
        entries = Self.sanitized(defaults.stringArray(forKey: Self.storageKey) ?? [])
            .filter { Self.key($0) != Self.key(query) }
        persist()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() { defaults.set(entries, forKey: Self.storageKey) }
    private static func key(_ query: String) -> String {
        normalized(query).folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func sanitized(_ input: [String]) -> [String] {
        var seen = Set<String>()
        return Array(input.map(normalized).filter { !$0.isEmpty && seen.insert(key($0)).inserted }.prefix(limit))
    }
}

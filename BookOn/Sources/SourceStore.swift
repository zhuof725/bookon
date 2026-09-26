import Foundation
import Combine

final class SourceStore: ObservableObject {
    static let shared = SourceStore()
    @Published private(set) var sources: [BookSource] = []

    private let fileURL: URL
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("bookSources.json")
        load()
    }

    private func load() {
        guard let d = try? Data(contentsOf: fileURL), let s = String(data: d, encoding: .utf8) else { return }
        sources = BookSource.parseList(s).sorted { $0.customOrder < $1.customOrder }
    }
    private func save() {
        let arr = sources.map { $0.raw }
        if let d = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }

    var enabledSources: [BookSource] { sources.filter { $0.enabled } }
    var groups: [String] {
        var set: [String] = []
        for s in sources { for g in s.bookSourceGroup.components(separatedBy: CharacterSet(charactersIn: ",;，；")) where !g.isEmpty && !set.contains(g) { set.append(g) } }
        return set
    }

    /// 导入 JSON 文本，返回新增/更新数量
    @discardableResult
    func importJSON(_ text: String) -> (added: Int, updated: Int) {
        let list = BookSource.parseList(text)
        var added = 0, updated = 0
        for s in list {
            if let i = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) { sources[i] = s; updated += 1 }
            else { sources.append(s); added += 1 }
        }
        save()
        return (added, updated)
    }

    func importFromURL(_ url: String) async throws -> (added: Int, updated: Int) {
        guard let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw URLError(.badURL) }
        var req = URLRequest(url: u); req.setValue(HttpClient.defaultUA, forHTTPHeaderField: "User-Agent")
        let (d, _) = try await URLSession.shared.data(for: req)
        let text = String(data: d, encoding: .utf8) ?? Encodings.decode(d, charset: "gbk")
        return await MainActor.run { importJSON(text) }
    }

    func toggle(_ s: BookSource) {
        guard let i = sources.firstIndex(of: s) else { return }
        var raw = sources[i].raw; raw["enabled"] = !sources[i].enabled
        if let ns = BookSource(json: raw) { sources[i] = ns }
        save()
    }
    func delete(_ s: BookSource) { sources.removeAll { $0 == s }; save() }
    func deleteAll() { sources.removeAll(); save() }
    func source(for url: String) -> BookSource? { sources.first { $0.bookSourceUrl == url } }
}

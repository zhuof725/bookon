import SwiftUI

/// A single versioned snapshot keeps the collection and selection consistent.
/// Color/name edits are drafts until save. No book, font or paper preferences
/// are read or rewritten by this repository.
final class AppThemeStore: ObservableObject {
    nonisolated(unsafe) static let shared = AppThemeStore()
    static let storageKey = "app.customThemes.v1"
    static let maximumThemes = 20

    @Published private(set) var customThemes: [AppTheme] = []
    @Published private(set) var selectedID: String = AppTheme.defaultID
    @Published private(set) var notice: String?
    private let defaults: UserDefaults
    private let assets: ThemeAssetStore

    private struct Snapshot: Codable {
        var version = 1
        var themes: [AppTheme]
        var selectedID: String
    }
    enum StoreError: LocalizedError {
        case invalid(String), missing, builtIn, limit
        var errorDescription: String? {
            switch self {
            case .invalid(let reason): return reason
            case .missing: return "主题已不存在，请重新选择。"
            case .builtIn: return "内置主题不能覆盖或删除，请先创建副本。"
            case .limit: return "最多保存 20 个自创主题，请先删除不需要的主题。"
            }
        }
    }

    init(defaults: UserDefaults = .standard, assets: ThemeAssetStore = .shared) {
        self.defaults = defaults
        self.assets = assets
        reload()
    }

    var themes: [AppTheme] { AppTheme.templates + customThemes }
    var selectedTheme: AppTheme { themes.first { $0.id == selectedID } ?? .monochrome }

    func reload() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            customThemes = []; selectedID = AppTheme.defaultID; notice = nil
            return
        }
        guard data.count <= 256_000,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == 1 else {
            customThemes = []; selectedID = AppTheme.defaultID
            notice = "主题数据无法读取，已暂时使用经典黑白；书架和阅读设置不受影响。"
            return
        }
        var seen = Set<String>()
        let valid = snapshot.themes.filter { theme in
            !theme.isBuiltIn && UUID(uuidString: theme.id) != nil
                && theme.validationMessage == nil && seen.insert(theme.id).inserted
        }
        customThemes = Array(valid.prefix(Self.maximumThemes))
        selectedID = themes.contains(where: { $0.id == snapshot.selectedID }) ? snapshot.selectedID : AppTheme.defaultID
        notice = valid.count != snapshot.themes.count || valid.count > Self.maximumThemes
            ? "部分无效主题未载入，其余主题仍可使用。" : nil
    }

    func save(_ theme: AppTheme, apply: Bool = false) throws {
        guard !theme.isBuiltIn else { throw StoreError.builtIn }
        guard UUID(uuidString: theme.id) != nil else { throw StoreError.invalid("主题标识无效。") }
        var value = theme
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = value.validationMessage { throw StoreError.invalid(error) }
        // Load the latest snapshot before mutation, avoiding a stale editor
        // accidentally replacing another window's newly created themes.
        reload()
        var items = customThemes
        if let index = items.firstIndex(where: { $0.id == value.id }) { items[index] = value }
        else {
            guard items.count < Self.maximumThemes else { throw StoreError.limit }
            items.append(value)
        }
        try persist(items, selected: apply ? value.id : selectedID)
    }

    func apply(id: String) throws {
        reload()
        guard themes.contains(where: { $0.id == id }) else { throw StoreError.missing }
        try persist(customThemes, selected: id)
    }

    func delete(id: String) throws {
        guard !id.hasPrefix("builtin.") else { throw StoreError.builtIn }
        reload()
        guard customThemes.contains(where: { $0.id == id }) else { throw StoreError.missing }
        try persist(customThemes.filter { $0.id != id }, selected: selectedID == id ? AppTheme.defaultID : selectedID)
    }

    private func persist(_ items: [AppTheme], selected: String) throws {
        let data = try JSONEncoder().encode(Snapshot(themes: items, selectedID: selected))
        guard data.count <= 256_000 else { throw StoreError.invalid("主题数据过大，无法保存。") }
        // Delete only formerly referenced images after the new snapshot commits.
        // Shared assets survive while any saved theme still references them.
        let previousAssets = Set(customThemes.flatMap { $0.assetIDs })
        let retainedAssets = Set(items.flatMap { $0.assetIDs })
        defaults.set(data, forKey: Self.storageKey)
        customThemes = items
        selectedID = selected
        notice = nil
        for id in previousAssets.subtracting(retainedAssets) { assets.remove(id) }
    }
}

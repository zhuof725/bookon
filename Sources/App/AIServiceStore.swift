import Foundation
import Security
import SwiftUI

/// AI 服务的配置存储。
///
/// - 非敏感字段（地址、模型、温度、启用状态）存 UserDefaults。
/// - API Key 优先进系统钥匙串；无签名安装包可能没有钥匙串权限，
///   此时退化为沙盒内明文文件，并在界面上明确告知。
final class AIServiceStore: ObservableObject {
    /// 项目内其它设置存储同款写法：只从主线程（SwiftUI）访问。
    nonisolated(unsafe) static let shared = AIServiceStore()

    /// 已保存的配置，键为服务 id（自定义服务为 custom-<uuid>）。
    @Published private(set) var configs: [String: AIServiceConfig] = [:]
    /// 有可用密钥的服务 id。
    @Published private(set) var keyedIDs: Set<String> = []
    /// 默认用于「生成推荐语」等服务 id。
    @Published var defaultID: String? {
        didSet { defaults.set(defaultID, forKey: Self.defaultKey) }
    }
    /// 当前安装包无法写入钥匙串（密钥以明文保存在沙盒）。
    @Published private(set) var insecureKeyStorage = false

    private static let defaultsKey = "ai.services.v1"
    private static let defaultKey = "ai.default.v1"
    private static let fallbackKey = "ai.keys.fallback.v1"
    private static let keychainService = "io.github.xianghuo.book.ai"
    private let defaults = UserDefaults.standard

    init() { load() }

    // MARK: 查询

    func config(for id: String) -> AIServiceConfig? { configs[id] }

    func hasKey(for id: String) -> Bool { keyedIDs.contains(id) }

    /// 所有已保存的服务，内置在前、自定义在后，各自按目录顺序。
    var orderedConfigs: [AIServiceConfig] {
        let order = AICatalog.builtins.map(\.id)
        return configs.values.sorted { a, b in
            let ai = order.firstIndex(of: a.id) ?? Int.max
            let bi = order.firstIndex(of: b.id) ?? Int.max
            if ai != bi { return ai < bi }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    var customConfigs: [AIServiceConfig] {
        orderedConfigs.filter { $0.id.hasPrefix(Self.customPrefix) }
    }

    /// 可用于请求的服务：有密钥 + 已启用 + 有模型。
    var usableConfigs: [AIServiceConfig] {
        orderedConfigs.filter { hasKey(for: $0.id) && $0.canUse }
    }

    /// 默认服务；默认项不可用时退回第一个可用服务。
    var activeConfig: AIServiceConfig? {
        if let id = defaultID, let config = configs[id], hasKey(for: id), config.canUse {
            return config
        }
        return usableConfigs.first
    }

    // MARK: 写入

    func save(_ config: AIServiceConfig) {
        var updated = config
        updated.updatedAt = Date()
        configs[updated.id] = updated
        persist()
        if defaultID == nil, hasKey(for: updated.id), updated.canUse {
            defaultID = updated.id
        }
    }

    @discardableResult
    func setKey(_ key: String, for id: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { removeKey(for: id); return true }
        if writeKeychain(trimmed, account: id) {
            keyedIDs.insert(id)
        } else {
            var fallback = fallbackKeys()
            fallback[id] = trimmed
            defaults.set(fallback, forKey: Self.fallbackKey)
            keyedIDs.insert(id)
            insecureKeyStorage = true
        }
        return true
    }

    func apiKey(for id: String) -> String? {
        if let key = readKeychain(id), !key.isEmpty { return key }
        return fallbackKeys()[id]
    }

    func removeKey(for id: String) {
        deleteKeychain(id)
        var fallback = fallbackKeys()
        fallback.removeValue(forKey: id)
        defaults.set(fallback, forKey: Self.fallbackKey)
        keyedIDs.remove(id)
        if defaultID == id { defaultID = nil }
    }

    func delete(_ id: String) {
        guard id.hasPrefix(Self.customPrefix) else { return }
        removeKey(for: id)
        configs.removeValue(forKey: id)
        if defaultID == id { defaultID = nil }
        persist()
    }

    func makeCustomID() -> String { Self.customPrefix + UUID().uuidString }

    static let customPrefix = "custom-"

    // MARK: 持久化

    private func load() {
        defaultID = defaults.string(forKey: Self.defaultKey)
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let list = try? JSONDecoder().decode([AIServiceConfig].self, from: data) else { return }
        configs = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        refreshKeyedIDs()
    }

    private func persist() {
        let list = configs.values.sorted { $0.updatedAt > $1.updatedAt }
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func refreshKeyedIDs() {
        var ids: Set<String> = []
        for id in configs.keys where !(apiKey(for: id) ?? "").isEmpty { ids.insert(id) }
        keyedIDs = ids
    }

    // MARK: 钥匙串

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.keychainService,
         kSecAttrAccount as String: account]
    }

    private func readKeychain(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKeychain(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let base = query(account)
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private func deleteKeychain(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    private func fallbackKeys() -> [String: String] {
        defaults.dictionary(forKey: Self.fallbackKey) as? [String: String] ?? [:]
    }
}

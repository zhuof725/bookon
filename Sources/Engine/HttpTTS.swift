import Foundation

/// 在线朗读引擎（对齐原版 `data/entities/HttpTTS.kt`）。
/// URL 规则与书源 URL 一致：`{{speakText}}`、`{{speakSpeed}}`、`@js:`、`,{...}` 选项都支持。
struct HTTPTTS: Codable, Hashable, Identifiable {
    /// 原版以毫秒时间戳作主键；导入时缺省按当前时间生成。
    var id: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var name: String = ""
    var url: String = ""
    /// 期望返回的 Content-Type 正则（如 `audio/wav`）；留空不校验。
    var contentType: String?
    /// 并发率：`N/M` = 每 M 毫秒最多 N 次请求；`M` = 每 M 毫秒一次。
    var concurrentRate: String? = "0"
    var loginUrl: String?
    var loginUi: String?
    var header: String?
    var jsLib: String?
    var enabledCookieJar: Bool? = false
    var loginCheckJs: String?
    var lastUpdateTime: Int64? = Int64(Date().timeIntervalSince1970 * 1000)

    enum CodingKeys: String, CodingKey {
        case id, name, url, contentType, concurrentRate, loginUrl, loginUi
        case header, jsLib, enabledCookieJar, loginCheckJs, lastUpdateTime
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decode(Int64.self, forKey: .id) { id = n }
        else if let d = try? c.decode(Double.self, forKey: .id) { id = Int64(d) }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        contentType = try? c.decodeIfPresent(String.self, forKey: .contentType)
        if let s = try? c.decode(String.self, forKey: .concurrentRate) { concurrentRate = s }
        else if let n = try? c.decode(Double.self, forKey: .concurrentRate) {
            concurrentRate = n == n.rounded() ? "\(Int(n))" : "\(n)"
        }
        loginUrl = try? c.decodeIfPresent(String.self, forKey: .loginUrl)
        // 原版 loginUi 可以是数组，也可以是 JSON 字符串或 @js: 脚本：统一存成字符串。
        if let s = try? c.decode(String.self, forKey: .loginUi) {
            loginUi = s
        } else if let any = try? c.decode(JSONValue.self, forKey: .loginUi) {
            loginUi = JSONValue.jsonString(any)
        }
        header = try? c.decodeIfPresent(String.self, forKey: .header)
        jsLib = try? c.decodeIfPresent(String.self, forKey: .jsLib)
        enabledCookieJar = try? c.decodeIfPresent(Bool.self, forKey: .enabledCookieJar)
        loginCheckJs = try? c.decodeIfPresent(String.self, forKey: .loginCheckJs)
        if let n = try? c.decode(Int64.self, forKey: .lastUpdateTime) { lastUpdateTime = n }
        else if let d = try? c.decode(Double.self, forKey: .lastUpdateTime) { lastUpdateTime = Int64(d) }
    }

    /// 原版 BaseSource.getKey()：登录信息/登录头按这个键存取。
    var key: String { "httpTts:\(id)" }

    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名引擎" : name }

    var hasLogin: Bool {
        [(loginUrl ?? ""), (loginUi ?? "")].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 登录脚本与请求头复用书源基建：把引擎包装成 BookSource。
    var bookSourceShim: BookSource {
        var s = BookSource(bookSourceUrl: key, bookSourceName: displayName)
        s.loginUrl = loginUrl
        s.loginUi = loginUi
        s.header = header
        s.jsLib = jsLib
        s.enabledCookieJar = enabledCookieJar
        s.loginCheckJs = loginCheckJs
        return s
    }

    /// 并发率解析：返回「最小请求间隔」毫秒；0 = 不限制。
    var requestIntervalMilliseconds: Int {
        let raw = (concurrentRate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "0" else { return 0 }
        if let slash = raw.firstIndex(of: "/") {
            let limit = Int(raw[..<slash]) ?? 0
            let interval = Int(raw[raw.index(after: slash)...]) ?? 0
            guard limit > 0, interval > 0 else { return 0 }
            // N/M：按平均间隔限速（原版是滑动窗口，朗读逐句请求，间隔近似即可）。
            return max(interval / limit, 1)
        }
        return max(Int(raw) ?? 0, 0)
    }
}

/// 宽松 JSON 值，用于 loginUi 数组/对象的原样保留。
indirect enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object((try? c.decode([String: JSONValue].self)) ?? [:]) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    static func jsonString(_ v: JSONValue) -> String {
        guard let d = try? JSONEncoder().encode(v) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
}

/// 朗读引擎 JSON 导入/导出（支持单个对象或数组）。
enum HTTPTTSParser {
    static func parse(_ json: String) -> [HTTPTTS] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([HTTPTTS].self, from: data) {
            return list.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let one = try? decoder.decode(HTTPTTS.self, from: data),
           !one.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [one]
        }
        return []
    }

    static func json(_ engines: [HTTPTTS]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(engines) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

/// 引擎列表存储：Application Support/LegadoReading/httpTTS.json。
/// 与原版 Room 表对应：整份读写，写入时更新时间戳，读不到/损坏时视为空。
final class HTTPTTSStore {
    static let shared = HTTPTTSStore(fileURL: HTTPTTSStore.defaultFileURL())

    let fileURL: URL
    private(set) var engines: [HTTPTTS]
    /// 变化计数：SwiftUI 侧用 onChange 刷新列表。
    private(set) var revision = 0
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
        let loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([HTTPTTS].self, from: $0) } ?? []
        self.engines = loaded
    }

    static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoReading", isDirectory: true)
        return dir.appendingPathComponent("httpTTS.json")
    }

    private func unlocked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    func engine(id: Int64) -> HTTPTTS? { unlocked { engines.first(where: { $0.id == id }) } }

    @discardableResult
    func save(_ engine: HTTPTTS) -> HTTPTTS {
        unlocked {
            var e = engine
            e.lastUpdateTime = Int64(Date().timeIntervalSince1970 * 1000)
            if e.id == 0 { e.id = e.lastUpdateTime ?? e.id }
            if let i = engines.firstIndex(where: { $0.id == e.id }) { engines[i] = e }
            else { engines.append(e) }
            revision += 1
            persistLocked()
            return e
        }
    }

    @discardableResult
    func delete(id: Int64) -> Bool {
        unlocked {
            guard let i = engines.firstIndex(where: { $0.id == id }) else { return false }
            engines.remove(at: i)
            revision += 1
            persistLocked()
            return true
        }
    }

    /// 导入引擎 JSON：返回成功导入的数量。同名同 URL 视为更新，否则追加。
    @discardableResult
    func importJSON(_ json: String) -> Int {
        let parsed = HTTPTTSParser.parse(json)
        guard !parsed.isEmpty else { return 0 }
        return unlocked {
            var count = 0
            for var e in parsed {
                e.lastUpdateTime = Int64(Date().timeIntervalSince1970 * 1000)
                // 原版导入按 id 覆盖；id 命中不了就当新增（时间戳 id）。
                if let i = engines.firstIndex(where: { $0.id == e.id }) {
                    engines[i] = e
                } else if let i = engines.firstIndex(where: { $0.name == e.name && $0.url == e.url }) {
                    e.id = engines[i].id
                    engines[i] = e
                } else {
                    engines.append(e)
                }
                count += 1
            }
            revision += 1
            persistLocked()
            return count
        }
    }

    @discardableResult
    func importDefaults() -> Int {
        importJSON(HttpTTSDefaults.json)
    }

    func exportJSON(ids: Set<Int64>? = nil) -> String {
        unlocked {
            let list = ids.map { wanted in engines.filter { wanted.contains($0.id) } } ?? engines
            return HTTPTTSParser.json(list)
        }
    }

    private func persistLocked() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(engines)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 写盘失败不丢下内存状态；下次启动会少一版，但不会崩。
        }
    }
}

/// 朗读设置：选中引擎与语速、定时默认值。UserDefaults 存字符串，与原版 PreferKey 对应。
enum AloudTTSConfig {
    static let engineKey = "reader.aloud.engine.v1"
    static let speedKey = "reader.aloud.speed.v1"
    static let timerKey = "reader.aloud.timer.v1"
    static let preloadKey = "reader.aloud.preload.v1"
    static let preloadRange = 1...20
    static let defaultPreloadCount = 10

    static func clampedPreloadCount(_ value: Int) -> Int {
        min(max(value, preloadRange.lowerBound), preloadRange.upperBound)
    }

    /// 预加载段落数（在线引擎提前下载后续段落音频）：1–20，默认 10。
    /// 预加载更多段落可减少朗读换段时的网络等待卡顿。
    static var preloadCount: Int {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: preloadKey) != nil else { return defaultPreloadCount }
            let stored = d.integer(forKey: preloadKey)
            let clamped = clampedPreloadCount(stored)
            // 修复旧值或其他入口写入的越界值，持久化状态也保持在范围内。
            if stored != clamped { d.set(clamped, forKey: preloadKey) }
            return clamped
        }
        set { UserDefaults.standard.set(clampedPreloadCount(newValue), forKey: preloadKey) }
    }

    /// 引擎选择：空 = 系统语音；数字字符串 = HttpTTS.id（与原版一致）。
    static var selectedEngineID: String {
        get { UserDefaults.standard.string(forKey: engineKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: engineKey) }
    }

    static var selectedEngine: HTTPTTS? {
        guard let id = Int64(selectedEngineID) else { return nil }
        return HTTPTTSStore.shared.engine(id: id)
    }

    static var engineLabel: String {
        selectedEngine?.displayName ?? "系统语音"
    }

    /// 语速：原版 0–45，默认 5，界面显示 ((value + 5) / 10)。
    static var speechRate: Int {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: speedKey) != nil else { return 5 }
            return min(max(d.integer(forKey: speedKey), 0), 45)
        }
        set { UserDefaults.standard.set(newValue, forKey: speedKey) }
    }

    /// http 引擎用的 speakSpeed（原版 speechRatePlay + 5）。
    static var httpSpeakSpeed: Int { speechRate + 5 }

    /// 系统语音语速倍率（界面显示值）。
    static var rateDisplay: Double { rateDisplay(for: speechRate) }

    static func rateDisplay(for value: Int) -> Double { Double(min(max(value, 0), 45) + 5) / 10.0 }

    /// 默认定时（分钟），启动朗读时套用；0 = 不定时。
    static var timerDefault: Int {
        get { UserDefaults.standard.integer(forKey: timerKey) }
        set { UserDefaults.standard.set(newValue, forKey: timerKey) }
    }
}

/// 原版 AppPattern.notReadAloudRegex：整段只有空白/控制/标点/分隔符时跳过，
/// 只有 Emoji 等符号或纯标点也没有朗读意义，同样跳过。
enum AloudText {
    /// 段落整理成一行后，判断是否还有可读的字母/数字；没有就返回 nil（跳过本段）。
    static func speakText(for unit: String) -> String? {
        let text = unit.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                return text
            default:
                continue
            }
        }
        return nil
    }
}

import Foundation

/// 一次 Legado 规则执行的上下文。
///
/// Legado 的 `source`、`book`、`chapter` 变量会跨多个请求保留。iOS 的旧实现把
/// 所有变量放在一次解析器实例的临时字典里，导致搜索 URL 中 `java.put` 的值在
/// 解析搜索结果、详情和目录时丢失。这里按原版的作用域保存变量：chapter > book >
/// source；实例字典只保存本次上下文的初始值和兼容变量。
final class RuleContext {
    var source: BookSource?
    var book: Book?
    var chapter: BookChapter?
    private var variables: [String: String] = [:]
    // 临时条目只使用实例字典，不向共享表登记临时 URL 或标识。
    private var pendingBookVariables: [String: String]?
    private var inheritedBookVariables: [String: String] = [:]
    /// 无书籍标识时的 book.getVariable/putVariable 暂存，不与其他作用域共享。
    private var localBookVariables: [String: String] = [:]

    /// 复制列表阶段可见变量；每个条目拥有独立写入作用域。
    /// book 属性可逐字段更新，但只有 bindBook 才会提交共享存储。
    func forkForBook(_ book: Book, preservingExisting: Bool = false) -> RuleContext {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let child = RuleContext(source: source, book: book)
        var snapshot = variables
        func overlay(_ values: [String: String]) {
            for (key, value) in values where !value.isEmpty { snapshot[key] = value }
        }
        // A recovered request may not regenerate every book variable. Retain
        // existing values as a base, then prefer the fresh candidate snapshot.
        if preservingExisting, let id = child.bookID {
            Self.load(&Self.bookVariables, scope: "book", id: id)
            overlay(Self.bookVariables[id] ?? [:])
        }
        if let pending = pendingBookVariables {
            overlay(inheritedBookVariables)
            overlay(pending)
        } else {
            if let id = sourceID {
                Self.load(&Self.sourceVariables, scope: "source", id: id)
                overlay(Self.sourceVariables[id] ?? [:])
            }
            if let id = bookID {
                Self.load(&Self.bookVariables, scope: "book", id: id)
                overlay(Self.bookVariables[id] ?? [:])
            }
            if let id = chapterID { overlay(Self.chapterVariables[id] ?? [:]) }
        }
        child.inheritedBookVariables = snapshot
        child.pendingBookVariables = [:]
        return child
    }

    /// 将快照和条目变量绑定到最终 source+book 标识，空 URL 不提交。
    /// 无名称条目直接释放上下文即可，不产生需要清理的共享临时记录。
    func bindBook(_ finalBook: Book) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let pending = pendingBookVariables, !finalBook.bookUrl.isEmpty else { return }
        book = finalBook
        guard let id = bookID else { return }
        var values = inheritedBookVariables
        for (key, value) in pending {
            // 与临时 get 一致：空值回退到继承的列表快照。
            if !value.isEmpty || values[key] == nil { values[key] = value }
        }
        Self.load(&Self.bookVariables, scope: "book", id: id)
        Self.bookVariables[id, default: [:]].merge(values) { _, new in new }
        Self.save(Self.bookVariables, scope: "book", id: id)
        pendingBookVariables = nil
        inheritedBookVariables.removeAll()
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var sourceVariables: [String: [String: String]] = [:]
    private nonisolated(unsafe) static var bookVariables: [String: [String: String]] = [:]
    private nonisolated(unsafe) static var chapterVariables: [String: [String: String]] = [:]
    /// 已从磁盘读回的作用域（每个作用域每进程只读一次）。
    private nonisolated(unsafe) static var loadedScopes = Set<String>()

    /// 原版 source 级 java.put 存 CacheManager、book 级存 Book.variableMap（数据库），重启后仍在。
    /// 这里落到 JavaBridge.store（Application Support 的 JSON），避免重启后 `java.get('bid')`
    /// 之类的值为空导致签名失败。调用方须已持有 lock。
    private static func load(_ table: inout [String: [String: String]], scope: String, id: String) {
        let key = "__ctx_\(scope)_\(id)"
        guard loadedScopes.insert(key).inserted,
              let raw = JavaBridge.store.get(key), let data = raw.data(using: .utf8),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        // 内存里的新值优先于磁盘旧值。
        table[id, default: [:]].merge(saved) { current, _ in current }
    }

    private static func save(_ table: [String: [String: String]], scope: String, id: String) {
        guard let values = table[id],
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        JavaBridge.store.set("__ctx_\(scope)_\(id)", text)
    }

    /// book.getVariable/putVariable 的独立存储，与规则变量表互不影响。
    private nonisolated(unsafe) static var bookVariableStore: [String: [String: String]] = [:]

    init(source: BookSource? = nil, book: Book? = nil, chapter: BookChapter? = nil) {
        self.source = source
        self.book = book
        self.chapter = chapter
        if let raw = source?.bookSourceUrl {
            let clean = RuleContext.cleanSourceURL(raw)
            variables["host"] = clean
            variables["baseUrl"] = raw
        }
    }

    /// 供 JS bridge 保存 source 级变量，例如书源登录信息和跨请求 token。
    static func sourceGet(_ sourceID: String, _ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return sourceVariables[sourceID]?[key] ?? ""
    }

    static func sourcePut(_ sourceID: String, _ key: String, _ value: String) -> String {
        lock.lock(); defer { lock.unlock() }
        sourceVariables[sourceID, default: [:]][key] = value
        return value
    }

    // 仅用于网络地址兼容；存储标识必须保留 # 后缀，避免同站不同源串值。
    private static func cleanSourceURL(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = t.firstIndex(of: "#") else { return t }
        return String(t[..<i])
    }

    private var sourceID: String? {
        guard let source = source else { return nil }
        return source.bookSourceUrl
    }

    private var bookID: String? {
        guard let b = book, !b.bookUrl.isEmpty else { return nil }
        let origin = sourceID ?? b.origin
        return "\(origin.utf8.count):\(origin)\(b.bookUrl)"
    }

    private var chapterID: String? {
        guard let c = chapter, let bookID else { return nil }
        return "\(bookID)#\(c.index):\(c.url)"
    }

    private static func value(_ key: String, in table: [String: [String: String]], id: String?) -> String? {
        guard let id else { return nil }
        return table[id]?[key]
    }

    /// 书源 JS 的 `book.getVariable/putVariable`：Legado 中这是书籍自带的
    /// variableMap，与规则变量 `java.get/put` 是两套独立存储，这里也分开保存。
    func bookVariableGet(_ key: String) -> String {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if let id = bookID, let value = Self.bookVariableStore[id]?[key] { return value }
        return localBookVariables[key] ?? ""
    }

    func bookVariablePut(_ key: String, _ value: String) -> String {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if let id = bookID {
            Self.bookVariableStore[id, default: [:]][key] = value
            return value
        }
        // 没有书籍标识时不写入来源级共享存储，只保留本次求值。
        localBookVariables[key] = value
        return value
    }

    func put(_ key: String, _ value: String) -> String {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        // 有作用域时只写对应存储，避免实例缓存遮蔽其他上下文的新值。
        if pendingBookVariables != nil {
            pendingBookVariables?[key] = value
        } else if let id = chapterID {
            Self.chapterVariables[id, default: [:]][key] = value
        } else if let id = bookID {
            Self.load(&Self.bookVariables, scope: "book", id: id)
            Self.bookVariables[id, default: [:]][key] = value
            Self.save(Self.bookVariables, scope: "book", id: id)
        } else if let id = sourceID {
            Self.load(&Self.sourceVariables, scope: "source", id: id)
            Self.sourceVariables[id, default: [:]][key] = value
            Self.save(Self.sourceVariables, scope: "source", id: id)
        } else {
            variables[key] = value
        }
        return value
    }

    func get(_ key: String) -> String {
        if key == "bookName", let b = book { return b.name }
        if key == "title", let c = chapter { return c.title }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let pending = pendingBookVariables {
            if let value = pending[key], !value.isEmpty { return value }
            return inheritedBookVariables[key] ?? variables[key] ?? ""
        }
        if let value = Self.value(key, in: Self.chapterVariables, id: chapterID), !value.isEmpty { return value }
        if let id = bookID { Self.load(&Self.bookVariables, scope: "book", id: id) }
        if let id = sourceID { Self.load(&Self.sourceVariables, scope: "source", id: id) }
        if let value = Self.value(key, in: Self.bookVariables, id: bookID), !value.isEmpty { return value }
        if let value = Self.value(key, in: Self.sourceVariables, id: sourceID), !value.isEmpty { return value }
        return variables[key] ?? ""
    }

    func putAll(_ values: [String: String]) {
        for (key, value) in values { _ = put(key, value) }
    }
}

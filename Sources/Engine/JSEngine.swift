import Foundation
import JavaScriptCore
import CommonCrypto
import SwiftSoup

/// A single-request result slot. Every access is locked; closing on timeout
/// rejects late completion rather than letting a detached task mutate returned state.
private final class HTTPBridgeWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<HTTPResponseData, Error>?
    private var closed = false

    private func finish(_ value: Result<HTTPResponseData, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, result == nil else { return }
        result = value
        semaphore.signal()
    }

    private func take(timedOut: Bool) -> Result<HTTPResponseData, Error> {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        defer { result = nil }
        if timedOut { return .failure(URLError(.timedOut)) }
        return result ?? .failure(URLError(.unknown))
    }

    static func run(timeout: TimeInterval,
                    operation: @escaping @Sendable () async throws -> HTTPResponseData) throws -> HTTPResponseData {
        let slot = HTTPBridgeWaiter()
        let task = Task.detached {
            do {
                try Task.checkCancellation()
                let response = try await operation()
                try Task.checkCancellation()
                slot.finish(.success(response))
            } catch {
                slot.finish(.failure(error))
            }
        }
        let timedOut = slot.semaphore.wait(timeout: .now() + max(0, timeout)) == .timedOut
        let result = slot.take(timedOut: timedOut)
        if timedOut { task.cancel() }
        return try result.get()
    }
}

@objc protocol TTSResponseExports: JSExport {
    var url: String { get }
    var code: Int { get }
    /// OkHttp body().bytes()：JSEngine 桥，字节按 JS 数组返回。
    func body() -> TTSResponseBodyExports
    func newBuilder() -> TTSResponseBuilderExports
}
@objc protocol TTSResponseBodyExports: JSExport {
    func bytes() -> [Int]
    func string() -> String
    func contentLength() -> Int
    var mediaType: String { get }
}
@objc protocol TTSResponseBuilderExports: JSExport {
    func code(_ c: Int) -> TTSResponseBuilderExports
    func message(_ m: String) -> TTSResponseBuilderExports
    func header(_ k: String, _ v: String) -> TTSResponseBuilderExports
    func body(_ b: JSValue) -> TTSResponseBuilderExports
    func build() -> TTSResponseExports
}
final class TTSResponseBody: NSObject, TTSResponseBodyExports {
    let data: Data
    let mediaType: String
    init(data: Data, mediaType: String = "application/octet-stream") {
        self.data = data; self.mediaType = mediaType
    }
    @objc func bytes() -> [Int] { SourceCrypto.toSigned(data) }
    @objc func string() -> String { String(data: data, encoding: .utf8) ?? "" }
    @objc func contentLength() -> Int { data.count }
}
final class TTSResponseBuilder: NSObject, TTSResponseBuilderExports {
    private var _code = 200
    private var _message = "OK"
    private var _headers: [(String, String)] = []
    private var _body: TTSResponseBody?
    override init() { super.init() }
    @objc func code(_ c: Int) -> TTSResponseBuilderExports { _code = c; return self }
    @objc func message(_ m: String) -> TTSResponseBuilderExports { _message = m; return self }
    @objc func header(_ k: String, _ v: String) -> TTSResponseBuilderExports { _headers.append((k, v)); return self }
    @objc func body(_ b: JSValue) -> TTSResponseBuilderExports {
        if let native = b.toObject() as? TTSResponseBody {
            _body = native
        } else if let arr = b.forProperty("__bytes")?.toArray() as? [NSNumber] {
            _body = TTSResponseBody(data: Data(arr.map { UInt8(truncatingIfNeeded: $0.intValue) }))
        } else {
            _body = TTSResponseBody(data: Data())
        }
        return self
    }
    @objc func build() -> TTSResponseExports {
        let data = _body?.data ?? Data()
        let ct = _headers.last { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame }?.1
            ?? _body?.mediaType ?? "application/octet-stream"
        return TTSResponse(data: data, url: "", code: _code, headers: ["Content-Type": ct])
    }
}
final class TTSResponse: NSObject, TTSResponseExports {
    let data: Data
    let url: String
    let code: Int
    private let headers: [String: String]
    init(data: Data, url: String, code: Int, headers: [String: String]) {
        self.data = data; self.url = url; self.code = code; self.headers = headers
    }
    @objc func body() -> TTSResponseBodyExports {
        TTSResponseBody(data: data, mediaType: headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? "application/octet-stream")
    }
    @objc func newBuilder() -> TTSResponseBuilderExports { TTSResponseBuilder() }
    @objc func isSuccessful() -> Bool { (200...299).contains(code) }
    @objc func header(_ name: String) -> String {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
    }
}

/// Bridge object exposed to book-source JS as `java`.
@objc protocol JavaBridgeExports: JSExport {
    /// Legado 约定：ajax 直接返回响应正文。导出名用 ajaxNative，
    /// JS 侧再把 java.ajax 定义成带第二参数（请求选项/超时）的包装，见 prelude。
    func ajaxNative(_ url: String) -> String
    /// 原生响应对象入口，由 JS 包装为 java.connect。
    func connectNative(_ url: String) -> StrResponse?
    /// ajax 的第二个参数：Legado AjaxWebView 里的超时（毫秒）。iOS 端按请求超时使用，
    /// 缺省沿用桥的默认超时；服务器聚合书源会传 15000 之类的显式值。
    func ajaxWithTimeout(_ url: String, _ timeoutMs: Double) -> String
    func base64Decode(_ s: String) -> String
    func base64Encode(_ s: String) -> String
    func md5Encode(_ s: String) -> String
    func md5Encode16(_ s: String) -> String
    func encodeURI(_ s: String) -> String
    func timeFormat(_ t: Double) -> String
    func log(_ s: String) -> String
    func storePut(_ key: String, _ value: String) -> String
    func storeGet(_ key: String) -> String
    func storeDelete(_ key: String) -> String
    func httpGetNative(_ url: String, _ headersJSON: String) -> StrResponse?
    func httpPostNative(_ url: String, _ body: String, _ headersJSON: String) -> StrResponse?
    func hexDecodeToString(_ s: String) -> String
    func hexEncodeToString(_ s: String) -> String
    func toast(_ s: String) -> String
    func longToast(_ s: String) -> String
    func encodeURIComponent(_ s: String) -> String
    func timeFormatUTC(_ t: Double, _ format: String, _ offset: Int) -> String
    /// java.cacheFile / readTxtFile：脚本缓存目录里的文本文件（相对路径）。
    func cacheFile(_ url: String, _ saveTime: Double) -> String
    func readTxtFile(_ path: String, _ charset: String) -> String
    /// java.htmlFormat(str, redirectUrl)
    func htmlFormat(_ html: String, _ baseUrl: String) -> String
    /// java.toNumChapter
    func toNumChapter(_ text: String) -> String
    /// java.queryTTF / replaceFont 的字体句柄接口。
    func fontQuery(_ data: String, _ useCache: Bool) -> Int
    func fontGlyph(_ id: Int, _ unicode: Int) -> String
    func fontGlyphID(_ id: Int, _ unicode: Int) -> Int
    func fontUnicode(_ id: Int, _ glyph: String) -> Int
    func fontBlank(_ id: Int, _ unicode: Int) -> Bool
    func fontReplace(_ text: String, _ errorID: Int, _ correctID: Int, _ filter: Bool) -> String
    /// java.getVerificationCode：界面注入 handler 后弹输入框，否则返回空串。
    func verificationCode(_ imageUrl: String) -> String
}

@objc final class JavaBridge: NSObject, JavaBridgeExports {
    /// 书源脚本变量（source.getVariable/setVariable、java.put/get、java.cache）：磁盘持久化，
    /// 重启后仍可读回；同一进程内与旧行为一致（返回当前值）。
    static let store = PersistentVariableStore(fileURL: PersistentVariableStore.defaultFileURL())
    let context: RuleContext?
    private let session: URLSession
    /// java.ajax(url, timeout) 会在单次调用里改写它，用完恢复。
    private var responseTimeout: TimeInterval

    init(context: RuleContext? = nil, session: URLSession = .shared,
         responseTimeout: TimeInterval = 25) {
        self.context = context
        self.session = session
        self.responseTimeout = responseTimeout
        super.init()
    }

    func ajaxNative(_ url: String) -> String {
        // AnalyzeUrl owns the existing verification path. Do not load the same
        // challenge again here; failures set the current JavaScript exception.
        return connectNative(url)?.body ?? ""
    }

    /// java.ajax(url, timeout)：超时以毫秒给出（聚合书源常用 15000）。
    /// 只在显式给出正数时生效，且不短于 1 秒，避免把请求卡成必然超时。
    func ajaxWithTimeout(_ url: String, _ timeoutMs: Double) -> String {
        let seconds = timeoutMs / 1000.0
        guard seconds >= 1 else { return ajaxNative(url) }
        let previous = responseTimeout
        responseTimeout = min(seconds, 120)
        defer { responseTimeout = previous }
        return ajaxNative(url)
    }

    func connectNative(_ url: String) -> StrResponse? {
        let au = AnalyzeUrl(rawUrl: url, baseUrl: context?.source?.bookSourceUrl,
                            sourceHeader: context?.source?.header, context: context,
                            jsLib: context?.source?.jsLib)
        return fetchResponse(au, fallbackURL: url)
    }

    func ajaxAllNative(_ urls: [String]) -> [StrResponse] {
        var responses: [StrResponse] = []
        for url in urls {
            guard let response = connectNative(url) else { return [] }
            responses.append(response)
        }
        return responses
    }
    func base64Decode(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.count % 4 != 0 { t += "=" }
        guard let d = Data(base64Encoded: t) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    func base64Encode(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
    func md5Encode(_ s: String) -> String {
        let d = Data(s.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        d.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(d.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    func md5Encode16(_ s: String) -> String {
        let m = md5Encode(s)
        let start = m.index(m.startIndex, offsetBy: 8)
        return String(m[start..<m.index(start, offsetBy: 16)])
    }
    func encodeURI(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
    func timeFormat(_ t: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: t > 1e12 ? t / 1000 : t))
    }
    func log(_ s: String) -> String { print("[JS] \(s)"); return s }
    func storePut(_ key: String, _ value: String) -> String {
        JavaBridge.store.set(key, value); return value
    }
    func storeGet(_ key: String) -> String {
        return JavaBridge.store.get(key) ?? ""
    }
    /// cache.deleteMemory：原版 CacheManager 的内存缓存删除（书源用它清「已渲染」标记）。
    func storeDelete(_ key: String) -> String {
        JavaBridge.store.remove(key); return ""
    }

    func httpGetNative(_ url: String, _ headersJSON: String) -> StrResponse? {
        let au = AnalyzeUrl(rawUrl: url, baseUrl: context?.source?.bookSourceUrl,
                            sourceHeader: headersJSON, context: context, jsLib: context?.source?.jsLib)
        return fetchResponse(au, fallbackURL: url)
    }

    func httpPostNative(_ url: String, _ body: String, _ headersJSON: String) -> StrResponse? {
        var au = AnalyzeUrl(rawUrl: url, baseUrl: context?.source?.bookSourceUrl,
                            sourceHeader: headersJSON, context: context)
        au.method = "POST"
        au.body = body
        return fetchResponse(au, fallbackURL: url)
    }

    private func fetchResponse(_ au: AnalyzeUrl, fallbackURL: String) -> StrResponse? {
        let request = au
        let requestSession = session
        do {
            let response = try HTTPBridgeWaiter.run(timeout: responseTimeout) {
                try await request.fetchResponse(session: requestSession)
            }
            return StrResponse(response)
        } catch {
            // This executes on the calling JS thread, never the detached task.
            // HTTP 4xx/5xx do not enter this branch: they retain body and metadata.
            let nativeError = error as NSError
            let timedOut = nativeError.domain == NSURLErrorDomain
                && nativeError.code == URLError.timedOut.rawValue
            if let jsContext = JSContext.current() {
                let exception = JSValue(newErrorFromMessage: timedOut
                    ? "HTTP request timed out"
                    : "HTTP transport failed: \(nativeError.localizedDescription)", in: jsContext)
                exception?.setObject(timedOut ? "TimeoutError" : "NetworkError",
                                     forKeyedSubscript: "name" as NSString)
                exception?.setObject(nativeError.domain, forKeyedSubscript: "domain" as NSString)
                exception?.setObject(nativeError.code, forKeyedSubscript: "nativeCode" as NSString)
                exception?.setObject(fallbackURL, forKeyedSubscript: "url" as NSString)
                jsContext.exception = exception
            }
            // Direct native callers receive nil, never a fabricated HTTP 200.
            return nil
        }
    }

    func hexDecodeToString(_ s: String) -> String {
        var bytes: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex, let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) {
            if let b = UInt8(s[i..<j], radix: 16) { bytes.append(b) }
            i = j
        }
        return String(data: Data(bytes), encoding: .utf8) ?? ""
    }
    func hexEncodeToString(_ s: String) -> String { s.utf8.map { String(format: "%02x", $0) }.joined() }
    func toast(_ s: String) -> String { ToastCenter.post(s); return s }
    func longToast(_ s: String) -> String { ToastCenter.post(s); return s }
    func encodeURIComponent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? s
    }
    func timeFormatUTC(_ t: Double, _ format: String, _ offset: Int) -> String {
        let f = DateFormatter(); f.dateFormat = format.isEmpty ? "yyyy/MM/dd HH:mm" : format
        f.timeZone = TimeZone(secondsFromGMT: offset * 3600)
        return f.string(from: Date(timeIntervalSince1970: t > 1e12 ? t / 1000 : t))
    }

    // MARK: - 文件 / HTML / 字体

    /// 脚本缓存目录（Application Support 之外用 Caches，系统可清理）。
    static var scriptCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LegadoReading/script-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func cacheFile(_ url: String, _ saveTime: Double) -> String {
        let key = md5Encode16(url)
        let file = Self.scriptCacheDirectory.appendingPathComponent(key + ".txt")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modified)
            if saveTime <= 0 || age < saveTime,
               let text = try? String(contentsOf: file, encoding: .utf8) {
                return text
            }
        }
        let au = AnalyzeUrl(rawUrl: url, baseUrl: context?.source?.bookSourceUrl,
                            context: context, jsLib: context?.source?.jsLib)
        guard let response = fetchResponse(au, fallbackURL: url) else { return "" }
        try? response.body.write(to: file, atomically: true, encoding: .utf8)
        return response.body
    }

    func readTxtFile(_ path: String, _ charset: String) -> String {
        guard let file = Self.resolveScriptPath(path) else { return "" }
        guard let data = try? Data(contentsOf: file) else { return "" }
        let enc = charset.isEmpty ? .utf8 : AnalyzeUrl.encoding(charset)
        return String(data: data, encoding: enc) ?? String(data: data, encoding: .utf8) ?? ""
    }

    /// 脚本可读的文件必须落在允许的目录内（缓存目录 / 文档目录）。
    /// 书源脚本不可信：readTxtFile / importScript 都能读文件，路径穿越会读到应用沙盒外的任意文件。
    /// 这里先把路径标准化（消掉 `..`、`.`、重复分隔符），再做「目录 + 分隔符」的前缀比较——
    /// 只比较字符串前缀会让 `/…/script-cache/../../etc/passwd` 通过检查，
    /// 也会让 `/…/script-cache-evil/x` 冒充缓存目录下的文件。
    static func resolveScriptPath(_ path: String) -> URL? {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") {
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            // 符号链接同样要挡住：软链指向目录外时，标准化路径看不出来。
            let resolved = url.resolvingSymlinksInPath()
            if allowedScriptRoots.contains(where: { isInside(resolved, of: $0) }) { return url }
            // 越界的绝对路径不放行，但保持原版的宽松兜底：仍按文件名去缓存目录里找。
            DebugLog.add("≡脚本文件路径越界，已拒绝：\(raw)")
        }
        let name = URL(fileURLWithPath: raw).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        let candidates = [scriptCacheDirectory.appendingPathComponent(name),
                          documentsDirectory.appendingPathComponent(name),
                          documentsDirectory.appendingPathComponent("LegadoReading/\(name)")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 允许脚本读写的根目录（与原版 JsExtensions.getFile 的「必须在缓存目录内」同口径）。
    /// 两侧都解析符号链接后再比较，否则 /var → /private/var 之类的软链会让本该放行的路径被误拒。
    static var allowedScriptRoots: [URL] {
        [scriptCacheDirectory, documentsDirectory]
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    }

    /// 路径是否位于 root 目录内部（含目录本身）：按路径分隔符比较，避免前缀误判。
    private static func isInside(_ url: URL, of root: URL) -> Bool {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        if target == base { return true }
        return target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func htmlFormat(_ html: String, _ baseUrl: String) -> String {
        SourceJSUtilities.htmlFormat(html, baseUrl: baseUrl.isEmpty ? nil : baseUrl)
    }

    func toNumChapter(_ text: String) -> String {
        SourceJSUtilities.toNumChapter(text)
    }

    func fontQuery(_ data: String, _ useCache: Bool) -> Int {
        guard let bytes = Self.fontBytes(data) else { return 0 }
        return SourceFontRegistry.register(data: bytes) ?? 0
    }

    private static func fontBytes(_ raw: String) -> Data? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("hex:") {
            return try? SourceCrypto.hexDecode(String(s.dropFirst(4)))
        }
        if s.hasPrefix("data:") {
            guard let r = s.range(of: "base64,") else { return nil }
            var payload = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            while payload.count % 4 != 0 { payload += "=" }
            return Data(base64Encoded: payload)
        }
        if s.hasPrefix("http://") || s.hasPrefix("https://") {
            let url = s
            guard let response = try? HTTPBridgeWaiter.run(timeout: 25, operation: {
                try await AnalyzeUrl(rawUrl: url).fetchResponse()
            }) else { return nil }
            return response.rawData ?? Data(response.body.utf8)
        }
        if let file = resolveScriptPath(s), let data = try? Data(contentsOf: file) { return data }
        var payload = s
        while payload.count % 4 != 0 { payload += "=" }
        return Data(base64Encoded: payload)
    }

    func fontGlyph(_ id: Int, _ unicode: Int) -> String {
        SourceFontRegistry.font(id)?.glyphHex(for: unicode) ?? ""
    }

    func fontGlyphID(_ id: Int, _ unicode: Int) -> Int {
        SourceFontRegistry.font(id)?.glyphID(for: unicode) ?? 0
    }

    func fontUnicode(_ id: Int, _ glyph: String) -> Int {
        SourceFontRegistry.font(id)?.unicode(forGlyph: glyph) ?? 0
    }

    func fontBlank(_ id: Int, _ unicode: Int) -> Bool {
        SourceFontRegistry.font(id)?.isBlankUnicode(unicode) ?? false
    }

    func fontReplace(_ text: String, _ errorID: Int, _ correctID: Int, _ filter: Bool) -> String {
        guard let error = SourceFontRegistry.font(errorID),
              let correct = SourceFontRegistry.font(correctID) else { return text }
        return FontDeobfuscation.replace(text: text, error: error, correct: correct, filter: filter)
    }

    func verificationCode(_ imageUrl: String) -> String {
        guard let handler = SourceVerificationBridge.handler else {
            DebugLog.add("◇getVerificationCode：当前界面没有验证码输入入口，返回空")
            return ""
        }
        return handler(imageUrl)
    }
}

/// java.getVerificationCode 的界面注入点：返回用户输入的验证码；没有注入时返回空串。
enum SourceVerificationBridge {
    static var handler: ((String) -> String)?
}

/// JS 里 java.toast / longToast 的消息出口：界面订阅 handler 即可显示；没有订阅者时只丢弃。
/// 发现页控件 action 里脚本发起的界面动作：`java.open(ui, scheme, data)` 与
/// `java.searchBook(key, sourceName)`。原版由 Activity 直接响应，iOS 端把动作收集起来，
/// 由发现页决定要打开登录页还是发起一次书源内搜索。
enum SourceUiAction: Equatable {
    case open(ui: String, scheme: String, data: String)
    case search(key: String, sourceName: String)
}

enum ToastCenter {
    /// 评论页等「打开网页」请求的统一入口。界面收到后弹半屏网页。
    /// content 是书源直接给的 HTML 页面内容（Legado 的 showBrowser(url, content) 语义）：
    /// 有内容就按内容渲染，没有内容才去请求 url。
    private static var browserHandler: ((String, String, String?) -> Void)?
    static func setBrowserHandler(_ h: ((String, String, String?) -> Void)?) { lock.lock(); browserHandler = h; lock.unlock() }
    private static var captures: [((String, String?) -> Void)] = []
    static func pushBrowserCapture(_ f: @escaping (String, String?) -> Void) { lock.lock(); captures.append(f); lock.unlock() }
    static func popBrowserCapture() { lock.lock(); if !captures.isEmpty { captures.removeLast() }; lock.unlock() }
    static func openBrowser(_ url: String, _ title: String, _ content: String? = nil) {
        lock.lock(); let h = browserHandler; let cap = captures.last; lock.unlock()
        // 有捕获者（评论点击）时只交给它，不再弹系统浏览器。
        if let cap = cap { cap(url, content); return }
        h?(url, title, content)
    }
    private static let lock = NSLock()
    /// 发现页控件脚本想要的界面动作。每次执行 action 前清空，执行后读取。
    private static var lastSourceAction: SourceUiAction? = nil

    /// 读取最近一次控件脚本请求的界面动作（执行 action 后调用）。
    static var pendingSourceAction: SourceUiAction? {
        lock.lock(); defer { lock.unlock() }
        return lastSourceAction
    }

    static func resetSourceAction() {
        lock.lock(); lastSourceAction = nil; lock.unlock()
    }

    static func recordSourceAction(_ action: SourceUiAction) {
        lock.lock(); lastSourceAction = action; lock.unlock()
    }
    private static var handler: ((String) -> Void)?
    static func setHandler(_ h: ((String) -> Void)?) { lock.lock(); handler = h; lock.unlock() }
    static func post(_ message: String) {
        lock.lock(); let h = handler; lock.unlock()
        h?(message)
    }
}

final class JSEngine {
    static let shared = JSEngine()
    private let session: URLSession
    private let responseTimeout: TimeInterval

    /// Instance-local injection keeps offline tests away from the shared session.
    init(session: URLSession = .shared, responseTimeout: TimeInterval = 25) {
        self.session = session
        self.responseTimeout = responseTimeout
    }

    /// 登录信息持久化到 Application Support（重启保留），按书源完整标识隔离。
    static let loginStore = SourceLoginStore(
        backing: PersistentLoginBackingStore(fileURL: PersistentLoginBackingStore.defaultFileURL()),
        cookieReplacer: { key, cookie in
            let url = key.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? key
            try SourceCookieStore(storage: HTTPCookieStorage.shared).replaceCookie(url, cookie)
        },
        cookieRemover: { key in
            let url = key.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? key
            try SourceCookieStore(storage: HTTPCookieStorage.shared).removeCookie(url)
        })

    /// 当前正在执行的书源（供 JS 里的 `source` 对象使用）
    static var currentSource: BookSource?

    /// 最近一次脚本异常（按线程保存）。调用方据此区分「脚本抛错」与「脚本返回空」：
    /// 抛错时可以退回规则的文本部分，而不是把整条规则判成空。
    static var lastError: String? {
        get { Thread.current.threadDictionary[lastErrorKey] as? String }
        set { Thread.current.threadDictionary[lastErrorKey] = newValue }
    }
    private static let lastErrorKey = "io.legado.js.lastError"

    /// 书源规则被截断时（复制/编辑书源常丢字符），结尾的字符串/模板字符串会少一个引号，
    /// JSC 只报 “Unexpected EOF”。扫描到结尾仍未闭合的引号补一个再求值。
    static func repairUnterminatedString(_ text: String) -> String? {
        enum Quote { case none, single, double, template }
        var quote: Quote = .none
        var escaped = false
        for ch in text {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            switch quote {
            case .none:
                if ch == "'" { quote = .single }
                else if ch == "\"" { quote = .double }
                else if ch == "`" { quote = .template }
            case .single:
                if ch == "'" { quote = .none }
            case .double:
                if ch == "\"" { quote = .none }
            case .template:
                if ch == "`" { quote = .none }
            }
        }
        // 单/双引号字符串不能跨行：补引号前先去掉尾随换行，否则仍是语法错误。
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch quote {
        case .single: return body + "'"
        case .double: return body + "\""
        case .template: return body + "`"
        case .none: return nil
        }
    }

    private static let prelude = """
    (function(){var __jp=JSON.parse;JSON.parse=function(s,r){if(s!==null&&typeof s==='object'){return s;}return __jp(String(s),r);};})();
    // 原版(Rhino)的规则 JS 里 result 是 Elements 集合，书源普遍写
    // result.select('a').toArray() / result[0].outerHtml() / result.size() / result.attr('href')。
    // 我们的规则 JS 传入的是元素数组，这里给 Array.prototype 补上同名方法（非枚举，
    // 不影响 for-in / Object.keys / JSON.stringify）。
    (function(){
        if(Array.prototype.__legadoElements) return;
        var def=function(n,f){Object.defineProperty(Array.prototype,n,{value:f,enumerable:false,writable:true,configurable:true});};
        def('toArray',function(){return Array.prototype.slice.call(this);});
        def('size',function(){return this.length;});
        // Java List 风格：java.getElements(...).isEmpty() / java.getStringList(...).toArray()
        def('isEmpty',function(){return this.length===0;});
        def('get',function(i){return (i>=0&&i<this.length)?this[i]:null;});
        def('first',function(){return this.length?this[0]:null;});
        def('last',function(){return this.length?this[this.length-1]:null;});
        def('each',function(f){for(var i=0;i<this.length;i++){if(typeof f==='function')f(this[i],i);}return this;});
        // java.util.List 的可变方法：书源脚本会 result.add('有声书') 之类地改结果
        def('add',function(v){this.push(v);return true;});
        def('addAll',function(v){if(v==null)return false;var a=Array.prototype.slice.call(v);if(a.length===0)return false;this.push.apply(this,a);return true;});
        def('set',function(i,v){i=Number(i);var prev=(i>=0&&i<this.length)?this[i]:null;this[i]=v;return prev;});
        def('contains',function(v){return this.indexOf(v)>=0;});
        // jQuery 风格：集合上的 eq/hasClass/parent/next/prev 委托给元素
        def('eq',function(i){return (i>=0&&i<this.length)?this[i]:null;});
        def('hasClass',function(n){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.hasClass==='function'){return !!e.hasClass(n);}}return false;});
        def('parent',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.parent==='function'){return e.parent();}}return null;});
        // DOM 变更（书源正文规则常用：box.select("script").remove()）
        def('remove',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.remove==='function'){e.remove();}}return this;});
        def('empty',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.empty==='function'){e.empty();}}return this;});
        def('append',function(h){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.append==='function'){e.append(String(h));}}return this;});
        def('prepend',function(h){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.prepend==='function'){e.prepend(String(h));}}return this;});
        def('addClass',function(n){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.addClass==='function'){e.addClass(String(n));}}return this;});
        def('removeClass',function(n){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.removeClass==='function'){e.removeClass(String(n));}}return this;});
        def('next',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.next==='function'){return e.next();}}return null;});
        def('prev',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.prev==='function'){return e.prev();}}return null;});
        def('select',function(sel){
            var out=[];
            for(var i=0;i<this.length;i++){
                var e=this[i];
                if(e&&typeof e.select==='function'){
                    var sub=e.select(sel);
                    if(sub&&typeof sub.length==='number'){
                        for(var j=0;j<sub.length;j++){
                            var item=(typeof sub.get==='function')?sub.get(j):null;
                            if(item) out.push(item);
                        }
                    }
                }
            }
            return out;
        });
        def('attr',function(n){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.attr==='function'){var v=e.attr(n);if(v)return v;}}return '';});
        def('text',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.text==='function'){var v=e.text();if(v)return v;}}return '';});
        def('ownText',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.ownText==='function'){var v=e.ownText();if(v)return v;}}return '';});
        def('html',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.html==='function'){var v=e.html();if(v)return v;}}return '';});
        def('outerHtml',function(){for(var i=0;i<this.length;i++){var e=this[i];if(e&&typeof e.outerHtml==='function'){var v=e.outerHtml();if(v)return v;}}return '';});
        Object.defineProperty(Array.prototype,'__legadoElements',{value:true,enumerable:false,configurable:true});
    })();
    var cookie={
        getCookie:function(u){return String(__cookieGet(String(u)));},
        getKey:function(u,k){return String(__cookieGetKey(String(u),String(k)));},
        // Kotlin returns Unit: template side effects must not insert "true" into URLs.
        setCookie:function(u,v){__cookieSet(String(u),v==null?'':String(v));},
        replaceCookie:function(u,v){__cookieReplace(String(u),v==null?'':String(v));},
        removeCookie:function(u){__cookieRemove(String(u));},
        removeCookieByName:function(u,n){__cookieRemoveNamed(String(u),String(n));},
        cookieToMap:function(v){
            var parsed=JSON.parse(String(__cookieToMap(v==null?'':String(v))));
            var map=Object.create(null);
            Object.keys(parsed).forEach(function(k){map[k]=parsed[k];});
            return map;
        },
        mapToCookie:function(v){
            if(v==null){return null;}
            if(typeof v!=='object' || Array.isArray(v)){throw new TypeError('Cookie map must be an object');}
            var map=Object.create(null);
            Object.keys(v).forEach(function(k){
                if(typeof v[k]!=='string'){throw new TypeError('Cookie map values must be strings');}
                map[k]=v[k];
            });
            if(Object.keys(map).length===0){return null;}
            return String(__cookieFromMap(JSON.stringify(map)));
        }
    };
    function __javaMap(){
        var m=Object.create(null);
        function def(n,f){Object.defineProperty(m,n,{value:f,enumerable:false,writable:true,configurable:true});}
        function own(){return Object.keys(m);}
        def('get',function(k){var v=m[String(k)];return v===undefined?null:v;});
        def('getOrDefault',function(k,d){var v=m[String(k)];return v===undefined?d:v;});
        def('put',function(k,v){var o=m[String(k)];m[String(k)]=v;return o===undefined?null:o;});
        def('remove',function(k){var o=m[String(k)];delete m[String(k)];return o===undefined?null:o;});
        def('containsKey',function(k){return Object.prototype.hasOwnProperty.call(m,String(k));});
        def('containsValue',function(v){return own().some(function(k){return m[k]===v;});});
        def('isEmpty',function(){return own().length===0;});
        def('size',function(){return own().length;});
        def('keySet',function(){return own();});
        def('values',function(){return own().map(function(k){return m[k];});});
        def('forEach',function(f){own().forEach(function(k){f(m[k],k);});});
        def('toString',function(){return JSON.stringify(m);});
        return m;
    }
    // 原版 CacheManager 的 JS 视图：get/put 走磁盘，getFromMemory/putMemory/deleteMemory 走内存缓存。
    // deleteMemory 少了会导致书源 imageDecode 里的「清标记」失效（点击被跳过）。
    // cache / source 必须挂到**全局对象**上，不能只是局部 var：
    // 书源脚本里的函数常写 `this.cache.getFromMemory(...)` / `this.source.getVariable()`，
    // 而顶层 this 就是全局对象（Rhino 语义）。只声明成 var 时，函数内的 this 不是全局对象，
    // 这两行会直接抛 TypeError —— 表现为「段评气泡点了没反应」。
    var __legadoCache={get:function(k){return java.storeGet(k)},put:function(k,v){return java.storePut(k,String(v))},getFromMemory:function(k){return java.storeGet(k)},putMemory:function(k,v){return java.storePut(k,String(v))},deleteMemory:function(k){return java.storeDelete(k)},delete:function(k){return java.storeDelete(k)}};
    var cache=__legadoCache;
    try{ globalThis.cache=__legadoCache; }catch(e){ }
    var source={bookSourceUrl:'',bookSourceName:'',bookSourceComment:'',loginUi:'',loginUrl:'',getKey:function(){return this.bookSourceUrl},
    // Rhino 把 Java 的 getKey() 暴露成属性：书源脚本里普遍写 source.key / source.name（群小说 searchUrl）。
    get key(){return this.bookSourceUrl},
    getVariable:function(){return java.storeGet('__var_'+this.bookSourceUrl)},setVariable:function(v){java.storePut('__var_'+this.bookSourceUrl,String(v))},
    // Legado BaseSource.putVariable 与 setVariable 写的是同一份存储（sourceVariable_<key>）。
    putVariable:function(v){return this.setVariable(v)},
    // Legado 的 source.put/get 按书源隔离：v_<书源 URL>_<key>，避免不同书源同名键串值。
    put:function(k,v){return java.storePut('v_'+this.bookSourceUrl+'_'+String(k),String(v))},get:function(k){return java.storeGet('v_'+this.bookSourceUrl+'_'+String(k))},
        getLoginInfoMap:function(){var s=String(__loginInfoMap());var m=__javaMap();try{var o=JSON.parse(s);Object.keys(o).forEach(function(k){m[k]=o[k];});}catch(e){}return m;},
        getLoginInfo:function(){var v=__loginGet();return v==null||v===''?null:String(v);},
        putLoginInfo:function(v){return __loginPut(String(v));},
        removeLoginInfo:function(){__loginRemove();},
        getLoginHeader:function(){var v=__loginHeaderGet();return v==null||v===''?null:String(v);},
        getLoginHeaderMap:function(){var v=__loginHeaderGet();if(v==null||v==='')return null;var m=Object.create(null);try{var o=JSON.parse(String(v));Object.keys(o).forEach(function(k){m[k]=o[k];});}catch(e){return null;}return m;},
        putLoginHeader:function(v){__loginHeaderPut(String(v));},
        removeLoginHeader:function(){__loginHeaderRemove();},
        upLoginData:function(o){
            // Legado BaseSource.upLoginData(map)：把登录表单/登录脚本的键值写进登录信息并刷新界面。
            if(o==null){return null;}
            if(typeof __loginDataPut==='function'){__loginDataPut(JSON.stringify(o));return o;}
            return o;},
        reLoginView:function(){
            if(typeof __loginViewRefresh==='function'){__loginViewRefresh();}
            return '';},
        // Legado BaseSource.refreshExplore()：书源在登录脚本里刷新发现页（重生聚合等服务器聚合源）。
        refreshExplore:function(){
            if(typeof __sourceRefreshExplore==='function'){__sourceRefreshExplore();}
            return '';},
        // Android WebView CookieManager 子集：书源用它直接写/读网页 Cookie
        // （iOS 端走统一 Cookie 存储，与 java.get/cookie.* 同一后端）。
        webViewCookieManager:function(){
            var set=function(u,v){
                try{var parts=String(v||'').split(';');var nv=parts[0]||'';var eq=nv.indexOf('=');if(eq<=0){return '';}
                var name=nv.slice(0,eq);var value=nv.slice(eq+1);
                var expired=/max-age\\s*=\\s*0/i.test(String(v));
                if(expired||!value){cookie.removeCookieByName(String(u),name);}
                else{cookie.setCookie(String(u),name+'='+value);}
                }catch(e){}
                return '';};
            return {setCookie:set,getInstance:function(){return {setCookie:set,flush:function(){return '';},getCookie:function(u){return cookie.getCookie(String(u));}};},
                    getCookie:function(u){return cookie.getCookie(String(u));},flush:function(){return '';},removeAllCookies:function(){return '';},removeAllCookie:function(){return '';}}}};
    // 同 cache：source 也要挂到全局对象上，脚本里 `this.source.xxx` 才取得到。
    try{ globalThis.source=source; }catch(e){ }
    var book={name:'',bookUrl:'',tocUrl:'',type:0,durChapterIndex:0,durChapterTitle:'',
        getVariable:function(k){return (typeof __bookVarGet==='function')?String(__bookVarGet(String(k))):'';},
        putVariable:function(k,v){var s=(v==null?'':String(v));return (typeof __bookVarPut==='function')?String(__bookVarPut(String(k),s)):s;},
        setVariable:function(k,v){return this.putVariable(k,v);},
        // Legado 的阅读配置在 iOS 端没有对应存储：给出可读对象与无副作用的 setter，
        // 书源脚本普遍会读 book.readConfig.useReplaceRule 或调用 book.setUseReplaceRule(false)。
        get readConfig(){return this.__readConfig||(this.__readConfig={useReplaceRule:false,replaceRules:[],replacementMode:0});},
        set readConfig(v){this.__readConfig=v;},
        get replaceRules(){return this.readConfig.replaceRules;},
        set replaceRules(v){this.readConfig.replaceRules=v;},
        setUseReplaceRule:function(){return '';},
        setReplaceRule:function(){return '';},
        getUseReplaceRule:function(){return false;}};
    var chapter={title:'',url:'',index:0};
    var Packages={
        org:{jsoup:{Jsoup:{__name:'Jsoup',parse:function(html){return __jsoupParse(String(html));}},
            // Rhino 里脚本常写 `Packages.org.jsoup.nodes.Document` 做类型判断或取常量。
            nodes:{Document:function(){},Element:function(){},TextNode:function(){},Entities:{}}}},
        java:{
            lang:{
                System:{nanoTime:function(){return Math.round(Date.now()*1e6);},
                        currentTimeMillis:function(){return Math.round(Date.now());},
                        getProperty:function(k){return 'java.version'.length?String(k):'';},
                        getenv:function(){return null;}},
                Thread:{sleep:function(){return '';},currentThread:function(){return {getName:function(){return 'main';}};}}
            },
            util:{
                // Java 集合在脚本里只当容器用：返回带 List/Map 语义的普通对象/数组即可。
                HashMap:function(){return __javaMap();},
                LinkedHashMap:function(){return __javaMap();},
                TreeMap:function(){return __javaMap();},
                Hashtable:function(){return __javaMap();},
                Properties:function(){return __javaMap();},
                ArrayList:function(){var a=[];if(arguments.length===1&&arguments[0]!=null){var src=arguments[0];if(typeof src.length==='number'){for(var i=0;i<src.length;i++)a.push(src[i]);}}return a;},
                LinkedList:function(){return Packages.java.util.ArrayList.apply(null,arguments)},
                Vector:function(){return Packages.java.util.ArrayList.apply(null,arguments)},
                Arrays:{copyOfRange:function(b,a,e){a=a||0;e=(e==null)?b.length:e;var o=[];for(var i=a;i<e&&i<b.length;i++)o.push(b[i]);return o;},
                        asList:function(){return Array.prototype.slice.call(arguments);}},
                UUID:{randomUUID:function(){
                    var hex='0123456789abcdef',s='';
                    for(var i=0;i<36;i++){
                        if(i===8||i===13||i===18||i===23){s+='-';continue;}
                        if(i===14){s+='4';continue;}
                        var r=Math.floor(Math.random()*16);
                        if(i===19){r=(r&0x3)|0x8;}
                        s+=hex.charAt(r);
                    }
                    return s;
                }}
            }
        },
        android:{util:{Base64:{DEFAULT:0,NO_PADDING:1,NO_WRAP:2,CRLF:4,URL_SAFE:8,
            encodeToString:function(b,flags){
                var text=(b!=null&&typeof b.length==='number'&&typeof b!=='string')?java.bytesToStr(b,'ISO-8859-1'):String(b==null?'':b);
                var out=String(java.base64Encode(text));
                if(flags&2){out=out.replace(/[\\r\\n]/g,'');}
                if(flags&8){out=out.replace(/\\+/g,'-').replace(/\\//g,'_');}
                return out;
            },
            decode:function(s,flags){
                var str=String(s==null?'':s);
                if(flags&8){str=str.replace(/-/g,'+').replace(/_/g,'/');}
                var r=java.base64DecodeToByteArray(str);
                return r==null?[]:r;
            }}}},
        cn:{hutool:{
            crypto:{digest:{DigestUtil:{
                md5Hex:function(s){return String(java.digestHex(String(s),'MD5'));},
                sha256Hex:function(s){return String(java.digestHex(String(s),'SHA256'));}}}} ,
            core:{util:{StrUtil:{
                reverse:function(s){return String(s==null?'':s).split('').reverse().join('');},
                isBlank:function(s){return s==null||String(s).replace(/\\s/g,'')==='';},
                emptyToDefault:function(s,d){return (s==null||String(s)==='')?d:s;}}},
                codec:{Base64:{
                    encode:function(s){return String(java.base64Encode(String(s)));},
                    decodeStr:function(s){return String(java.base64Decode(String(s)));}}},
                ZipUtil:{gzip:function(s){return String(java.base64Encode(String(s)));}}}}
        },
        okio:{Buffer:function(){}},
        okhttp3:{
            MediaType:{parse:function(s){return String(s||'');}},
            RequestBody:{
                create:function(mediaType,body){
                    var text=String(body==null?'':body);
                    return {contentType:function(){return mediaType;},__body:text,
                            contentLength:function(){return text.length;},toString:function(){return text;}};
                }
            },
            Request:{
                Builder:function(){
                    var o={__url:'',__method:'GET',__headers:{},__body:''};
                    return {
                        url:function(u){o.__url=String(u||'');return this;},
                        method:function(m,b){o.__method=String(m||'GET');if(b!=null)o.__body=String(b&&b.__body!=null?b.__body:b);return this;},
                        header:function(k,v){o.__headers[String(k)]=String(v);return this;},
                        addHeader:function(k,v){o.__headers[String(k)]=String(v);return this;},
                        get:function(){return o;},
                        build:function(){return {url:function(){return o.__url;},method:function(){return o.__method;},
                                                headers:function(){return o.__headers;},__body:o.__body,
                                                toString:function(){return o.__url;}};}
                    };
                }
            },
            OkHttpClient:function(){
                var self={};
                self.newCall=function(req){
                    var r=(req&&typeof req.url==='function')?{url:req.url(),method:req.method(),headers:req.headers?req.headers():{},body:req.__body}:{url:String(req||''),method:'GET',headers:{},body:''};
                    return {execute:function(){return java.connect(r.url);},enqueue:function(){return '';}};
                };
                return self;
            },
            ResponseBody:{
                create:function(mediaType,total,buf){
                    var b=(buf&&buf.__bytes)?buf.__bytes.slice():[];
                    var len=(typeof total==='number'&&!isNaN(total))?total:b.length;
                    return {mediaType:function(){return mediaType;},contentType:function(){return mediaType;},
                            contentLength:function(){return len;},bytes:function(){return b;},
                            string:function(){return typeof bytesToStr==='function'?bytesToStr(b):'';},
                            __bytes:b,contentLengthOut:len};
                }
            }
        }
    };
    Packages.java.util.HashMap.prototype.put=function(k,v){var prev;if(Object.prototype.hasOwnProperty.call(this,String(k)))prev=this[String(k)];else prev=null;this[String(k)]=v;return prev;};
    Packages.okio.Buffer.prototype.write=function(arr){if(!arr)return;this.__bytes=this.__bytes||[];for(var i=0;i<arr.length;i++)this.__bytes.push(arr[i]);};
    Packages.okio.Buffer.prototype.size=function(){return (this.__bytes||[]).length;};
    // Rhino JavaImporter 子集（七猫正文 AES 解密）：with(importer) 里的 String 是 java.lang.String，
    // String(byte[]) 按 UTF-8 解码；"...".getBytes() 取字节；Cipher/SecretKeySpec/IvParameterSpec 走原生加密桥。
    String.prototype.getBytes=function(cs){return java.strToBytes(String(this),cs==null?'UTF-8':String(cs));};
    Packages.java.lang.String=function(v,cs){
        if(v!=null&&typeof v==='object'&&typeof v.length==='number'){return java.bytesToStr(v,cs==null?'UTF-8':String(cs));}
        return String(v);
    };
    Packages.java.util.Base64={__name:'Base64',
        getDecoder:function(){return {decode:function(s){
            var b=(typeof s==='string')?s:java.bytesToStr(s,'UTF-8');var r=java.base64DecodeToByteArray(b);return r==null?[]:r;}};},
        getEncoder:function(){return {encodeToString:function(b){return String(java.base64Encode(java.bytesToStr(b,'ISO-8859-1')));}};}
    };
    Packages.javax={crypto:{
        spec:{
            SecretKeySpec:function(key,alg){return {__key:key,__alg:String(alg||''),getEncoded:function(){return key;}};},
            IvParameterSpec:function(iv){return {__iv:iv,getIV:function(){return iv;}};}
        },
        Cipher:{ENCRYPT_MODE:1,DECRYPT_MODE:2,getInstance:function(t){
            var c={__t:String(t),__mode:2,__key:null,__iv:null};
            c.init=function(mode,key,iv){c.__mode=Number(mode);c.__key=key&&key.__key!=null?key.__key:key;c.__iv=iv&&iv.__iv!=null?iv.__iv:(iv==null?null:iv);};
            c.doFinal=function(d){
                var sc=java.createSymmetricCrypto(c.__t,c.__key,c.__iv);
                return c.__mode===1?sc.encrypt(d):sc.decrypt(d);
            };
            return c;
        }}
    }};
    Packages.java.lang.String.__name='String';
    Packages.java.util.HashMap.__name='HashMap';
    Packages.javax.crypto.spec.SecretKeySpec.__name='SecretKeySpec';
    Packages.javax.crypto.spec.IvParameterSpec.__name='IvParameterSpec';
    Packages.javax.crypto.Cipher.__name='Cipher';
    function JavaImporter(){for(var i=0;i<arguments.length;i++){this.importPackage(arguments[i]);}}
    Object.defineProperty(JavaImporter.prototype,'importPackage',{enumerable:false,value:function(){
        for(var i=0;i<arguments.length;i++){var p=arguments[i];if(!p)continue;
            for(var k in p){if(Object.prototype.hasOwnProperty.call(p,k)){this[k]=p[k];}}}
    }});
    Object.defineProperty(JavaImporter.prototype,'importClass',{enumerable:false,value:function(){
        for(var i=0;i<arguments.length;i++){var c=arguments[i];if(!c)continue;
            if(c.__name){this[c.__name]=c;continue;}
            for(var k in c){if(Object.prototype.hasOwnProperty.call(c,k)){this[k]=c[k];}}}
    }});
    function importPackage(){JavaImporter.prototype.importPackage.apply(this,arguments);}
    function importClass(){JavaImporter.prototype.importClass.apply(this,arguments);}
    var org=Packages.org;
    // Preserve primitive code and url: neither can also be a same-named
    // method without breaking strict comparisons. code()/url() remain unsupported.
    // connect headers model the read-only Kotlin Headers subset; get/post headers
    // are a plain map, not an OkHttp Headers object or a complete Java Map.
    // 原版 StrResponse：body() / code() / headers() 都是方法。
    // loginCheckJs 的 result 就是它（书源脚本普遍写 result.body()、result.url()）。
    // 兼容两种写法：既支持 result.body()，也支持 result.body.includes(...) 这类字符串用法。
    // 元素列表的混合形态：数组语义（select/toArray/下标/length）+ 字符串语义（match/split）。
    function __legadoList(items, text){
        var s=String(text==null?'':text);
        var strMethods={match:1,replace:1,search:1,split:1,trim:1,substring:1,substr:1,
                        indexOf:1,lastIndexOf:1,startsWith:1,endsWith:1,charAt:1,charCodeAt:1,
                        toLowerCase:1,toUpperCase:1,includes:1};
        try{
            return new Proxy(items,{get:function(t,k){
                if(strMethods[String(k)]===1){
                    var f=s[k];
                    if(typeof f==='function') return function(){return f.apply(s,arguments);};
                }
                var v=t[k];
                return (typeof v==='function')?v.bind(t):v;
            }});
        }catch(e){ return items; }
    }
    function __legadoStrResponse(p){
        var raw=p.headers||{};
        var copy=Object.create(null);
        Object.keys(raw).forEach(function(k){copy[k]=raw[k];});
        var find=function(k){
            k=String(k).toLowerCase();
            var names=Object.keys(copy);
            for(var i=0;i<names.length;i++){if(names[i].toLowerCase()===k)return copy[names[i]];}
            return null;
        };
        // 可调用 + 带字符串方法：result.body() 与 result.body.includes('x') 都能用。
        var callableString=function(text){
            var fn=function(){return text;};
            fn.toString=function(){return text;};
            try{
                return new Proxy(fn,{get:function(t,k){
                    if(k==='length') return text.length;
                    if(k==='toString') return t.toString;
                    if(k in t) return t[k];
                    var v=text[k];
                    return (typeof v==='function')?v.bind(text):v;
                }});
            }catch(e){ return fn; }
        };
        var bodyText=String(p.body||'');
        var urlText=String(p.url||'');
        var headerObj={
            get:function(k){var v=find(k);return v==null?null:String(v);},
            names:function(){return Object.keys(copy);},
            getOrDefault:function(k,d){var v=find(k);return v==null?d:v;}
        };
        var headersFn=function(){return headerObj;};
        headersFn.get=headerObj.get;
        headersFn.names=headerObj.names;
        return {
            __payload:{url:urlText,body:bodyText,code:Number(p.code||0),headers:copy},
            url:callableString(urlText),
            code:p.code,
            length:bodyText.length,
            body:callableString(bodyText),
            bodyAsBytes:function(){return (typeof java.strToBytes==='function')?java.strToBytes(bodyText,'UTF-8'):[];},
            isSuccessful:function(){var c=Number(p.code||0);return c>=200&&c<300;},
            header:function(k){var v=find(k);return v==null?'':String(v);},
            headers:headersFn,
            toString:function(){return bodyText;},
            valueOf:function(){return bodyText;}
        };
    }
    function __response(r,jsoup){        if(!r){throw new Error('HTTP response unavailable');}
        return {
            url:r.url,
            code:r.code,
            length:r.length,
            statusKnown:r.code !== 0,
            body:function(){return r.body},
            // Legado StrResponse.bodyAsBytes()：二进制响应原始字节（TTS 多段合并需要）。
            bodyAsBytes:function(){return r.bodyAsBytes();},
            statusCode:function(){return r.code},
            isSuccessful:function(){return r.isSuccessful()},
            header:function(k){return r.header(String(k))},
            headers:function(){
                var fields=r.headers(), copy=Object.create(null);
                Object.keys(fields).forEach(function(k){copy[k]=fields[k]});
                if(jsoup){return copy;}
                return {
                    get:function(k){
                        k=String(k).toLowerCase();
                        var names=Object.keys(copy);
                        for(var i=0;i<names.length;i++){
                            if(names[i].toLowerCase()===k){return copy[names[i]];}
                        }
                        return null;
                    },
                    names:function(){return Object.keys(copy)}
                };
            },
            toString:function(){return r.body},
            valueOf:function(){return r.body}
        };
    }
    java.connect=function(u){return __response(java.connectNative(String(u)))};
    // java.ajax 的原生实现是 java.ajaxNative（见 JavaBridge）；下面只在 JS 侧
    // 加一层第二参数（请求选项 / 毫秒超时）的包装，不再改写任何原生方法。
    // java.ajax(url, second?)：Legado 的 ajax 只取第一个参数，但服务器聚合书源（重生聚合等）
    // 会把请求选项 JSON 或毫秒超时作为第二个参数传进来。这里按第二个参数的类型分流：
    // 字符串/对象形式的请求选项（method/body/headers）走 Legado 的 `地址,{...}` 写法，
    // 纯对象按 header 映射处理，数字按毫秒超时处理；都没有时与原版一致。
    java.ajax=function(u,opt){
        if(opt!=null&&opt!==undefined){
            if(typeof opt==='number'){return String(java.ajaxWithTimeout(String(u),Number(opt)));}
            if(typeof opt==='string'){
                var t=String(opt).replace(/^\\s+|\\s+$/g,'');
                if(t.charAt(0)==='{'){
                    return String(java.connect(String(u)+','+t).body());
                }
                var parsed=null;
                try{parsed=JSON.parse(t);}catch(e2){parsed=null;}
                if(parsed&&typeof parsed==='object'){return String(java.httpGetNative(String(u),t).body());}
            } else if(typeof opt==='object'){
                return String(java.httpGetNative(String(u),JSON.stringify(opt)).body());
            }
        }
        return String(java.ajaxNative(String(u)));
    };
    java.ajaxAll=function(arr){var o=[];for(var i=0;i<arr.length;i++){o.push(__response(java.connectNative(String(arr[i]))));}return o;};
    java.startBrowserAwait=function(u,t){var s=String(u||'');if(typeof __openBrowser==='function'&&/^https?:/i.test(s)){__openBrowser(s,String(t||''),'');return '';}return java.connect(s)};
    java.showBrowser=function(u,h,js,cfg){if(typeof __openBrowser==='function'){__openBrowser(String(u||''),'',String(h||''));}return '';};
    java.sleep=function(ms){return '';};
    java.getWebViewUA=function(){return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';};
    java.showReadingBrowser=function(u,t){if(typeof __openBrowser==='function'){__openBrowser(String(u||''),String(t||''),'');}return '';};
    java.startBrowserDp=function(u,t){if(typeof __openBrowser==='function'){__openBrowser(String(u||''),String(t||''),'');}return '';};
    // 发现页控件的按钮回调：原版 java.open(ui, scheme, data) 打开登录/书架等界面，
    // java.searchBook(key, sourceName) 用当前书源直接搜索。iOS 端由原生接管（见
    // SourceDiagnostics.applyExploreControl），这里只负责把参数交出去。
    java.open=function(u,sc,data){
        if(typeof __openUi==='function'){__openUi(String(u==null?'':u),String(sc==null?'':sc),String(data==null?'':data));}
        return '';
    };
    java.searchBook=function(k,sn){
        if(typeof __searchBook==='function'){__searchBook(String(k==null?'':k),String(sn==null?'':sn));}
        return '';
    };
    java.qread=function(){return '';};
    java.getThemeConfig=function(){return 'light';};
    java.startBrowser=function(u,t,c){if(typeof __openBrowser==='function'){__openBrowser(String(u),String(t||''),String(c||''));}return ''};
    java.webView=function(h,u,js){
        if(typeof __headlessWeb==='function'){
            var out=String(__headlessWeb(String(h==null?'':h),String(u==null?'':u),String(js==null?'':js)));
            if(out!==''){return out;}
        }
        return java.ajax(String(u));
    };
    var __localRuleVars=Object.create(null);
    java.put=function(k,v){
        k=String(k);v=String(v);
        if(typeof __contextPut==='function'){return __contextPut(k,v);}
        __localRuleVars[k]=v;return v;
    };
    java.get=function(k,h){
        if(arguments.length===1){
            k=String(k);
            if(typeof __contextGet==='function'){return String(__contextGet(k));}
            return Object.prototype.hasOwnProperty.call(__localRuleVars,k)?__localRuleVars[k]:'';
        }
        return __response(java.httpGetNative(String(k),JSON.stringify(h||{})),true);
    };
    java.post=function(u,b,h){return __response(java.httpPostNative(String(u),String(b),JSON.stringify(h||{})),true)};
    java.getCookie=function(u,k){
        if(arguments.length>1 && k!=null){return cookie.getKey(String(u),String(k));}
        return cookie.getCookie(String(u));
    };
    java.getString=function(r,c){
        if(arguments.length>1){return String(__ruleGetStringFrom(String(r),c));}
        return String(__ruleGetString(String(r)));
    };
    java.getStringList=function(r){var s=java.getString(r);return s?s.split('\\n'):[]};
    java.getElement=function(r){return (typeof __ruleGetElements==='function')?__ruleGetElements(String(r))[0]:null};
    java.getElements=function(r){return (typeof __ruleGetElements==='function')?__ruleGetElements(String(r)):[]};
    java.setContent=function(c){__ruleSetContent(c);result=c};
    // ---- crypto / codec (Hutool-compatible subset); byte arrays are signed ints like Java ----
    function __bytes(v,charsetHint){
        if(v==null){return null;}
        if(typeof v==='string'){return JSON.parse(__strToBytes(v,charsetHint||'UTF-8'));}
        if(Array.isArray(v)||(typeof v.length==='number'&&typeof v!=='function')){
            var a=[];for(var i=0;i<v.length;i++){a.push(Number(v[i]));}return a;
        }
        throw new TypeError('Expected a string or byte array');
    }
    function __cryptoKey(v){return typeof v==='string'?JSON.stringify(__bytes(v)):JSON.stringify(__bytes(v));}
    java.strToBytes=function(s,cs){return JSON.parse(__strToBytes(String(s),cs==null?'UTF-8':String(cs)));};
    java.bytesToStr=function(b,cs){return String(__bytesToStr(JSON.stringify(__bytes(b)),cs==null?'UTF-8':String(cs)));};
    // 书源里高频用到的 URL/日志工具（对照原版 java.* 命名空间）
    java.encodeURI=function(s){return encodeURI(String(s));};
    java.encodeURIComponent=function(s){return encodeURIComponent(String(s));};
    java.decodeURI=function(s){try{return decodeURI(String(s));}catch(e){return String(s);}};
    java.decodeURIComponent=function(s){try{return decodeURIComponent(String(s));}catch(e){return String(s);}};
    java.base64Encode=function(s){return String(__base64Encode(String(s)));};
    java.base64Decode=function(s){var b=java.base64DecodeToByteArray(String(s));return b==null?'':java.bytesToStr(b,'UTF-8');};
    java.head=function(u){return String(java.ajax(String(u)+',{"method":"HEAD"}'));};
    java.httpGet=function(u){return String(java.ajax(String(u)));};
    java.postWithOptions=function(u,opt){return String(java.ajax(String(u)+','+JSON.stringify(opt||{})));};
    java.connectWithOptions=function(u,opt){return __response(java.connect(String(u)+','+JSON.stringify(opt||{})));};
    java.refreshBookInfo=function(){return '';};
    java.refreshBookToc=function(){return '';};
    java.setResponseBase64=function(data,mime){__legadoResponseBase64={data:String(data==null?'':data),mime:String(mime==null?'':mime)};return '';};
    var __legadoResponseBase64=null;
    java.log=function(){var parts=[];for(var i=0;i<arguments.length;i++){parts.push(String(arguments[i]));}if(typeof console!=='undefined'&&console.log){console.log(parts.join(' '));}return '';};
    java.base64DecodeToByteArray=function(s){
        if(s==null||String(s).trim()===''){return null;}
        var r=__base64ToBytes(String(s));if(r==null){return null;}return JSON.parse(r);
    };
    java.hexDecodeToByteArray=function(s){return JSON.parse(__hexToBytes(String(s)));};
    java.digestHex=function(d,a){return String(__digest(String(d),String(a),'hex'));};
    java.digestBase64Str=function(d,a){return String(__digest(String(d),String(a),'base64'));};
    java.HMacHex=function(d,a,k){return String(__hmac(String(d),String(a),String(k),'hex'));};
    java.HMacBase64=function(d,a,k){return String(__hmac(String(d),String(a),String(k),'base64'));};
    java.createSymmetricCrypto=function(transformation,key,iv){
        var t=String(transformation);
        var kb=JSON.stringify(__bytes(key));
        var ib=(iv==null)?'':JSON.stringify(__bytes(iv));
        var id=__cipherCreate(t,kb,ib);
        return {
            decrypt:function(d){return JSON.parse(__cipherRun(id,'decrypt',typeof d==='string'?'s':'b',typeof d==='string'?d:JSON.stringify(__bytes(d))));},
            decryptStr:function(d){return String(__cipherRun(id,'decryptStr',typeof d==='string'?'s':'b',typeof d==='string'?d:JSON.stringify(__bytes(d))));},
            encrypt:function(d){return JSON.parse(__cipherRun(id,'encrypt',typeof d==='string'?'s':'b',typeof d==='string'?d:JSON.stringify(__bytes(d))));},
            encryptBase64:function(d){return String(__cipherRun(id,'encryptBase64',typeof d==='string'?'s':'b',typeof d==='string'?d:JSON.stringify(__bytes(d))));},
            encryptHex:function(d){return String(__cipherRun(id,'encryptHex',typeof d==='string'?'s':'b',typeof d==='string'?d:JSON.stringify(__bytes(d))));}
        };
    };
    // Legado JsExtensions：tripleDESEncodeBase64Str(data,key,mode,padding,iv) / tripleDESDecodeStr(data,key,mode,padding,iv)。
    java.tripleDESEncodeBase64Str=function(d,k,mode,pad,iv){
        var t='DESede/'+String(mode)+'/'+String(pad);
        var c=java.createSymmetricCrypto(t,String(k),(iv==null||iv==='')?null:String(iv));
        return String(c.encryptBase64(String(d)));
    };
    java.tripleDESDecodeStr=function(d,k,mode,pad,iv){
        var t='DESede/'+String(mode)+'/'+String(pad);
        var c=java.createSymmetricCrypto(t,String(k),(iv==null||iv==='')?null:String(iv));
        return String(c.decryptStr(String(d)));
    };

    // ---- JsEncodeUtils：AES/DES 旧接口（书源里仍常见） ----
    // 语义逐条对照原版 JsEncodeUtils.kt，包括 aesEncodeToString / desEncodeToString
    // 这两个「名字是加密、实现却不是 Base64」的历史行为，照搬以免书源解析结果不一致。
    function __sc(transformation,key,iv){
        return java.createSymmetricCrypto(String(transformation),String(key),(iv==null||iv==='')?null:String(iv));
    }
    java.aesDecodeToString=function(str,key,transformation,iv){return String(__sc(transformation,key,iv).decryptStr(String(str)));};
    java.aesBase64DecodeToString=function(str,key,transformation,iv){return String(__sc(transformation,key,iv).decryptStr(String(str)));};
    // 原版 aesEncodeToString 的实现就是 decryptStr（上游遗留问题，已对着 Legado 的
    // app/src/main/java/io/legado/app/help/JsEncodeUtils.kt 逐行核对过）：
    //   fun aesEncodeToString(data, key, transformation, iv) =
    //       createSymmetricCrypto(transformation, key, iv).decryptStr(data)
    // 书源若调用它做「加密」，结果必须与原版一致，否则同一书源在两端解析出不同内容，
    // 所以这里照搬，不按名字的字面意思改成 encrypt。
    java.aesEncodeToString=function(data,key,transformation,iv){return String(__sc(transformation,key,iv).decryptStr(String(data)));};
    java.aesEncodeToBase64String=function(data,key,transformation,iv){return String(__sc(transformation,key,iv).encryptBase64(String(data)));};
    java.aesEncodeArgsBase64Str=function(data,key,mode,padding,iv){
        return String(java.createSymmetricCrypto('AES/'+String(mode)+'/'+String(padding),String(key),(iv==null||iv==='')?null:String(iv)).encryptBase64(String(data)));
    };
    java.aesDecodeArgsBase64Str=function(data,key,mode,padding,iv){
        var k=java.base64DecodeToByteArray(String(key));var v=java.base64DecodeToByteArray(String(iv));
        return String(java.createSymmetricCrypto('AES/'+String(mode)+'/'+String(padding),k,(v==null||v.length===0)?null:v).decryptStr(String(data)));
    };
    java.desDecodeToString=function(data,key,transformation,iv){return String(__sc(transformation,key,iv).decryptStr(String(data)));};
    java.desBase64DecodeToString=function(data,key,transformation,iv){return String(__sc(transformation,key,iv).decryptStr(String(data)));};
    // 原版 desEncodeToString = String(encrypt(data))，即密文字节按平台默认编码转字符串。
    java.desEncodeToString=function(data,key,transformation,iv){return java.bytesToStr(__sc(transformation,key,iv).encrypt(String(data)));};
    java.desEncodeToBase64String=function(data,key,transformation,iv){return String(__sc(transformation,key,iv).encryptBase64(String(data)));};

    // ---- 文件 / HTML / 章节号 / 字体 / 验证码 ----
    java.evalJS=function(script){return eval(String(script));};
    java.cacheFile=function(u,t){return String(__cacheFile(String(u),t==null?0:Number(t)));};
    java.readTxtFile=function(path,cs){return String(__readTxtFile(String(path),cs==null?'':String(cs)));};
    java.importScript=function(path){
        var p=String(path);
        var t=/^https?:/i.test(p)?java.cacheFile(p):java.readTxtFile(p);
        if(!t){throw new Error(p+' 内容获取失败或者为空');}
        return t;
    };
    java.htmlFormat=function(s,u){return String(__htmlFormat(String(s==null?'':s),u==null?'':String(u)));};
    java.toNumChapter=function(s){return s==null?null:String(__toNumChapter(String(s)));};
    java.getVerificationCode=function(url){return String(__verificationCode(String(url)));};
    function __fontBytes(data){
        if(typeof data==='string'){return data;}
        if(data&&typeof data.length==='number'&&typeof data!=='function'){
            var hex='';for(var i=0;i<data.length;i++){var b=Number(data[i])&255;hex+=('0'+b.toString(16)).slice(-2);}
            return 'hex:'+hex;
        }
        return String(data==null?'':data);
    }
    java.queryTTF=function(data,useCache){
        var id=__fontQuery(__fontBytes(data),useCache!==false);
        if(!id||id<=0){return null;}
        return {
            __id:id,
            getGlyfByUnicode:function(u){return String(__fontGlyph(id,Number(u)));},
            getGlyfIdByUnicode:function(u){return Number(__fontGlyphID(id,Number(u)));},
            getUnicodeByGlyf:function(g){return Number(__fontUnicode(id,String(g)));},
            isBlankUnicode:function(u){return !!__fontBlank(id,Number(u));}
        };
    };
    java.replaceFont=function(text,errorQueryTTF,correctQueryTTF,filter){
        if(!errorQueryTTF||!correctQueryTTF||!errorQueryTTF.__id||!correctQueryTTF.__id){return String(text);}
        return String(__fontReplace(String(text),Number(errorQueryTTF.__id),Number(correctQueryTTF.__id),filter===true));
    };
    java.getThemeMode=function(){return 6;};
    java.refreshContent=function(){return '';};
    java.refreshExplore=function(){return '';};
    // 只提供 androidId：Legado/阅读Sigma 的 JS 环境里没有 deviceID，
    // 书源用「deviceID 是否存在」区分 iOS 分支，多提供一个会让它们误判成 iOS。
    java.androidId=function(){return String(__deviceId());};
    java.utf8ToGbk=function(s){return s};
    java.t2s=function(s){return s};java.s2t=function(s){return s};
    java.randomUUID=function(){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,function(c){var r=Math.random()*16|0;return (c=='x'?r:(r&3|8)).toString(16)})};
    // 登录脚本常用：java.upLoginData / java.reLoginView / java.webViewCookieManager
    // （Legado JsExtensions 与 android.webkit.CookieManager 的桥接；实现挂在 source 上，这里转发）。
    java.upLoginData=function(o){return source.upLoginData(o)};
    java.reLoginView=function(){return source.reLoginView()};
    java.webViewCookieManager=function(){return source.webViewCookieManager()};
    // 服务器聚合书源（重生聚合等）用 java.postDelayed(fn,ms) 延迟刷新发现页/登录面板。
    // iOS 端没有 Android Handler：延迟回调排进 __delayed 队列，由原生在一次求值结束后立即执行，
    // 脚本语义（先返回、随后刷新）保持不变，也不会把 JSContext 用到别的线程上。
    var __delayedQueue=[];
    java.postDelayed=function(fn,ms){
        if(typeof fn!=='function'){return 0;}
        __delayedQueue.push(fn);
        return 0;};
    // 由原生在脚本求值完成后调用：执行 java.postDelayed 排队的回调（含回调里再排队的，最多 32 轮）。
    function __drainDelayed(){
        for(var round=0;round<32;round++){
            if(!__delayedQueue.length){return;}
            var queue=__delayedQueue;
            __delayedQueue=[];
            for(var i=0;i<queue.length;i++){try{queue[i]();}catch(e){}}
        }
    }
    // java.getSource()：Legado JsExtensions 取当前书源对象（聚合源登录脚本会用它兜底取 source）。
    java.getSource=function(){return source;};
    // java.openUrl(u)：登录脚本里打开网址的旧式兜底（用户中心 / 帮助页）。
    java.openUrl=function(u){if(typeof __openBrowser==='function'){__openBrowser(String(u||''),'','');}return '';};
    """

    /// 书源传给 `cookie.*` 的“地址”经常不是 URL：真实书源会写
    /// `cookie.removeCookie(source.getKey())`（书源 URL 字段填的是中文名），
    /// 登录脚本也会写 `cookie.getKey('fanqienovel.com', 'sessionid')`（裸域名）。
    /// Legado 的 CookieStore 以子域名为键、从不校验，所以这里做同样的兼容：
    /// 裸主机名补 https:// 前缀（与网页登录同步下来的 Cookie 对得上），
    /// 完全解析不了的字符串按原版语义当“无事发生”——读取返回空、写入/删除静默忽略，
    /// 绝不抛异常把整段脚本打断。
    static func cookieTarget(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.contains("://") { return s }
        // 只把 ASCII 主机名（可带端口、路径）当作裸域名，中文书源名不会被当成主机。
        let head = s.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? s
        let host = head.split(separator: ":", maxSplits: 1).first.map(String.init) ?? head
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return "https://" + s
    }

    /// Use the injected session's storage; never fall back to the global jar.
    private func installCookieBindings(_ ctx: JSContext) {
        let store = SourceCookieStore(storage: session.configuration.httpCookieStorage)
        func report(_ error: Error) {
            // Never put cookie values or raw input into exceptions or logs.
            let message: String
            switch error as? SourceCookieStore.StoreError {
            case .invalidURL?: message = "Invalid Cookie URL"
            case .invalidCookie?: message = "Invalid Cookie input"
            case .unavailableStorage?: message = "Cookie storage is unavailable"
            case .storageRejected?: message = "Cookie storage rejected the update"
            default: message = "Cookie operation failed"
            }
            guard let current = JSContext.current() else { return }
            let exception = JSValue(newErrorFromMessage: message, in: current)
            exception?.setObject("CookieError", forKeyedSubscript: "name" as NSString)
            current.exception = exception
        }
        let get: @convention(block) (String) -> String = { url in
            guard let target = JSEngine.cookieTarget(url) else { return "" }
            return store.getCookie(target)
        }
        let getKey: @convention(block) (String, String) -> String = { url, key in
            guard let target = JSEngine.cookieTarget(url) else { return "" }
            return store.getKey(target, key)
        }
        let set: @convention(block) (String, String) -> Bool = { url, value in
            guard let target = JSEngine.cookieTarget(url) else { return false }
            do { try store.setCookie(target, value); return true }
            catch { report(error); return false }
        }
        let replace: @convention(block) (String, String) -> Bool = { url, value in
            guard let target = JSEngine.cookieTarget(url) else { return false }
            do { try store.replaceCookie(target, value); return true }
            catch { report(error); return false }
        }
        let remove: @convention(block) (String) -> Bool = { url in
            guard let target = JSEngine.cookieTarget(url) else { return true }
            do { try store.removeCookie(target); return true }
            catch { report(error); return false }
        }
        let removeNamed: @convention(block) (String, String) -> Bool = { url, name in
            guard let target = JSEngine.cookieTarget(url) else { return true }
            do { try store.removeCookie(target, name: name); return true }
            catch { report(error); return false }
        }
        let toMap: @convention(block) (String) -> String = { value in
            do {
                let map = try SourceCookieStore.cookieToMap(value)
                let data = try JSONSerialization.data(withJSONObject: map, options: [.sortedKeys])
                return String(data: data, encoding: .utf8) ?? "{}"
            } catch { report(error); return "{}" }
        }
        let fromMap: @convention(block) (String) -> String = { json in
            do {
                guard let data = json.data(using: .utf8),
                      let map = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                    throw SourceCookieStore.StoreError.invalidCookie
                }
                return try SourceCookieStore.mapToCookie(map)
            } catch { report(error); return "" }
        }
        ctx.setObject(get, forKeyedSubscript: "__cookieGet" as NSString)
        ctx.setObject(getKey, forKeyedSubscript: "__cookieGetKey" as NSString)
        ctx.setObject(set, forKeyedSubscript: "__cookieSet" as NSString)
        ctx.setObject(replace, forKeyedSubscript: "__cookieReplace" as NSString)
        ctx.setObject(remove, forKeyedSubscript: "__cookieRemove" as NSString)
        ctx.setObject(removeNamed, forKeyedSubscript: "__cookieRemoveNamed" as NSString)
        ctx.setObject(toMap, forKeyedSubscript: "__cookieToMap" as NSString)
        ctx.setObject(fromMap, forKeyedSubscript: "__cookieFromMap" as NSString)
    }

    /// Login values never go to logs or exception text.
    private func installLoginBindings(_ ctx: JSContext, source: BookSource?) {
        let store = JSEngine.loginStore
        let key = source?.bookSourceUrl ?? ""
        let ui = source?.loginUi
        let usable = !key.isEmpty
        func fail(_ message: String) {
            guard let current = JSContext.current() else { return }
            current.exception = JSValue(newErrorFromMessage: message, in: current)
        }
        let map: @convention(block) () -> String = {
            guard usable else { return "{}" }
            let m = store.getLoginInfoMap(key, loginUiJSON: ui)
            guard let d = try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]) else { return "{}" }
            return String(data: d, encoding: .utf8) ?? "{}"
        }
        let get: @convention(block) () -> String = { usable ? (store.getLoginInfo(key) ?? "") : "" }
        let put: @convention(block) (String) -> Bool = { usable ? store.putLoginInfo(key, $0) : false }
        let remove: @convention(block) () -> Void = { if usable { store.removeLoginInfo(key) } }
        let hGet: @convention(block) () -> String = { usable ? (store.getLoginHeader(key) ?? "") : "" }
        let hPut: @convention(block) (String) -> Void = { v in
            guard usable else { return }
            do { try store.putLoginHeader(key, v) } catch { fail("Login header update failed") }
        }
        let hRemove: @convention(block) () -> Void = {
            guard usable else { return }
            do { try store.removeLoginHeader(key) } catch { fail("Login header removal failed") }
        }
        ctx.setObject(map, forKeyedSubscript: "__loginInfoMap" as NSString)
        ctx.setObject(get, forKeyedSubscript: "__loginGet" as NSString)
        ctx.setObject(put, forKeyedSubscript: "__loginPut" as NSString)
        ctx.setObject(remove, forKeyedSubscript: "__loginRemove" as NSString)
        ctx.setObject(hGet, forKeyedSubscript: "__loginHeaderGet" as NSString)
        ctx.setObject(hPut, forKeyedSubscript: "__loginHeaderPut" as NSString)
        ctx.setObject(hRemove, forKeyedSubscript: "__loginHeaderRemove" as NSString)
        // upLoginData：登录脚本把键值合并进登录信息（Legado upLoginData(map)）。
        let dataPut: @convention(block) (String) -> Void = { raw in
            guard usable, let data = raw.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            var map = store.getLoginInfoMap(key, loginUiJSON: nil)
            for (k, v) in obj {
                if let s = v as? String {
                    map[k] = s
                } else if let b = v as? Bool {
                    // login 信息里没有布尔/数字：按 Legado 的字符串语义保存。
                    map[k] = b ? "true" : "false"
                } else if let n = v as? NSNumber {
                    map[k] = n.stringValue
                } else if let a = v as? [Any], let d = try? JSONSerialization.data(withJSONObject: a),
                          let s = String(data: d, encoding: .utf8) {
                    map[k] = s
                } else if let o = v as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: o),
                          let s = String(data: d, encoding: .utf8) {
                    map[k] = s
                } else if v is NSNull {
                    continue
                } else {
                    map[k] = String(describing: v)
                }
            }
            if let d = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
               let s = String(data: d, encoding: .utf8) {
                _ = store.putLoginInfo(key, s)
            }
        }
        ctx.setObject(dataPut, forKeyedSubscript: "__loginDataPut" as NSString)
        let viewRefresh: @convention(block) () -> Void = {
            // Legado reLoginView()：刷新登录界面（重新渲染按钮状态），这里无界面需要重建。
        }
        ctx.setObject(viewRefresh, forKeyedSubscript: "__loginViewRefresh" as NSString)
        // source.refreshExplore()：书源登录脚本刷新发现页。iOS 端没有可立即重建的发现页，
        // 这里只做无副作用的回调（书源脚本本身已把配置落盘，下次进入发现页即可生效）。
        let sourceRefreshExplore: @convention(block) () -> Void = {}
        ctx.setObject(sourceRefreshExplore, forKeyedSubscript: "__sourceRefreshExplore" as NSString)
        // java.postDelayed 由 prelude 排队（__drainDelayed），原生在求值结束后统一执行：
        // 见 runLoginScript / evalBody 里的 drainDelayed 调用。
    }

    /// Crypto errors are thrown as CryptoError with a fixed message; inputs never appear in them.
    private func installCryptoBindings(_ ctx: JSContext) {
        func fail(_ message: String) {
            guard let current = JSContext.current() else { return }
            let e = JSValue(newErrorFromMessage: message, in: current)
            e?.setObject("CryptoError", forKeyedSubscript: "name" as NSString)
            current.exception = e
        }
        func describe(_ error: Error) -> String {
            switch error as? SourceCrypto.CryptoError {
            case .unsupportedTransformation?: return "Unsupported cipher transformation"
            case .invalidKeyLength?: return "Invalid key length"
            case .invalidIVLength?: return "Invalid IV length"
            case .invalidInput?: return "Invalid crypto input"
            case .unsupportedDigest?: return "Unsupported digest algorithm"
            default: return "Crypto operation failed"
            }
        }
        func parseBytes(_ json: String) throws -> Data {
            guard let d = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: d) as? [NSNumber] else {
                throw SourceCrypto.CryptoError.invalidInput
            }
            return try SourceCrypto.fromSigned(arr.map { $0.intValue })
        }
        func bytesJSON(_ data: Data) -> String {
            let arr = SourceCrypto.toSigned(data)
            guard let d = try? JSONSerialization.data(withJSONObject: arr),
                  let s = String(data: d, encoding: .utf8) else { return "[]" }
            return s
        }
        func encoding(_ name: String) -> String.Encoding? {
            switch name.uppercased().replacingOccurrences(of: "-", with: "") {
            case "UTF8": return .utf8
            case "UTF16": return .utf16
            case "ISO88591", "LATIN1": return .isoLatin1
            case "ASCII", "USASCII": return .ascii
            case "GBK", "GB2312", "GB18030":
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            default: return nil
            }
        }
        let strToBytes: @convention(block) (String, String) -> String = { s, cs in
            guard let enc = encoding(cs), let data = s.data(using: enc) else {
                fail("Unsupported charset"); return "[]"
            }
            return bytesJSON(data)
        }
        let bytesToStr: @convention(block) (String, String) -> String = { json, cs in
            do {
                guard let enc = encoding(cs) else { throw SourceCrypto.CryptoError.invalidInput }
                return String(data: try parseBytes(json), encoding: enc) ?? ""
            } catch { fail(describe(error)); return "" }
        }
        let base64ToBytes: @convention(block) (String) -> String? = { s in
            guard let d = SourceCrypto.base64Decode(s) else { return nil }
            return bytesJSON(d)
        }
        let base64Encode: @convention(block) (String) -> String = { s in
            Data(s.utf8).base64EncodedString()
        }
        let hexToBytes: @convention(block) (String) -> String = { s in
            do { return bytesJSON(try SourceCrypto.hexDecode(s)) }
            catch { fail(describe(error)); return "[]" }
        }
        let digest: @convention(block) (String, String, String) -> String = { d, alg, fmt in
            do {
                return fmt == "hex" ? try SourceCrypto.digestHex(d, algorithm: alg)
                                    : try SourceCrypto.digestBase64(d, algorithm: alg)
            } catch { fail(describe(error)); return "" }
        }
        let hmac: @convention(block) (String, String, String, String) -> String = { d, alg, key, fmt in
            do {
                return fmt == "hex" ? try SourceCrypto.hmacHex(d, algorithm: alg, key: key)
                                    : try SourceCrypto.hmacBase64(d, algorithm: alg, key: key)
            } catch { fail(describe(error)); return "" }
        }
        // Ciphers live only as long as this JSContext.
        var ciphers: [Int: SourceCrypto.Cipher] = [:]
        var nextId = 1
        let create: @convention(block) (String, String, String) -> Int = { t, keyJSON, ivJSON in
            do {
                let key = try parseBytes(keyJSON)
                let iv: Data? = ivJSON.isEmpty ? nil : try parseBytes(ivJSON)
                let id = nextId; nextId += 1
                ciphers[id] = try SourceCrypto.Cipher(transformation: t, key: key, iv: iv)
                return id
            } catch { fail(describe(error)); return 0 }
        }
        let run: @convention(block) (Int, String, String, String) -> String = { id, op, kind, payload in
            guard let c = ciphers[id] else { fail("Invalid cipher"); return "" }
            do {
                let isString = kind == "s"
                switch op {
                case "decrypt":
                    let plain = isString ? try c.decryptInput(payload) : try c.decrypt(try parseBytes(payload))
                    return bytesJSON(plain)
                case "decryptStr":
                    if isString { return try c.decryptStr(payload) }
                    guard let s = String(data: try c.decrypt(try parseBytes(payload)), encoding: .utf8) else {
                        throw SourceCrypto.CryptoError.invalidInput
                    }
                    return s
                case "encrypt":
                    return bytesJSON(try c.encrypt(isString ? Data(payload.utf8) : try parseBytes(payload)))
                case "encryptBase64":
                    return try c.encrypt(isString ? Data(payload.utf8) : try parseBytes(payload)).base64EncodedString()
                case "encryptHex":
                    return SourceCrypto.hexEncode(try c.encrypt(isString ? Data(payload.utf8) : try parseBytes(payload)))
                default: throw SourceCrypto.CryptoError.invalidInput
                }
            } catch { fail(describe(error)); return "" }
        }
        // iOS has no ANDROID_ID. A stable per-install identifier plays the same role.
        let deviceId: @convention(block) () -> String = { JSEngine.installIdentifier }
        ctx.setObject(strToBytes, forKeyedSubscript: "__strToBytes" as NSString)
        ctx.setObject(bytesToStr, forKeyedSubscript: "__bytesToStr" as NSString)
        let headlessWeb: @convention(block) (String, String, String) -> String = { html, url, js in
            guard let runner = HeadlessWeb.runner else { return "" }
            let h = html.isEmpty ? nil : html
            let u = h == nil && !url.isEmpty ? url : nil
            return runner.run(html: h, url: u, js: js, timeout: 15) ?? ""
        }
        ctx.setObject(headlessWeb, forKeyedSubscript: "__headlessWeb" as NSString)
        ctx.setObject(base64ToBytes, forKeyedSubscript: "__base64ToBytes" as NSString)
        ctx.setObject(base64Encode, forKeyedSubscript: "__base64Encode" as NSString)
        ctx.setObject(hexToBytes, forKeyedSubscript: "__hexToBytes" as NSString)
        ctx.setObject(digest, forKeyedSubscript: "__digest" as NSString)
        ctx.setObject(hmac, forKeyedSubscript: "__hmac" as NSString)
        ctx.setObject(create, forKeyedSubscript: "__cipherCreate" as NSString)
        ctx.setObject(run, forKeyedSubscript: "__cipherRun" as NSString)
        ctx.setObject(deviceId, forKeyedSubscript: "__deviceId" as NSString)
    }

    /// java.cacheFile / importScript / htmlFormat / queryTTF 等原生入口。
    private func installScriptBindings(_ ctx: JSContext, bridge: JavaBridge) {
        let cacheFile: @convention(block) (String, Double) -> String = { bridge.cacheFile($0, $1) }
        let readTxt: @convention(block) (String, String) -> String = { bridge.readTxtFile($0, $1) }
        let htmlFormat: @convention(block) (String, String) -> String = { bridge.htmlFormat($0, $1) }
        let toNum: @convention(block) (String) -> String = { bridge.toNumChapter($0) }
        let fontQuery: @convention(block) (String, Bool) -> Int = { bridge.fontQuery($0, $1) }
        let fontGlyph: @convention(block) (Int, Int) -> String = { bridge.fontGlyph($0, $1) }
        let fontGlyphID: @convention(block) (Int, Int) -> Int = { bridge.fontGlyphID($0, $1) }
        let fontUnicode: @convention(block) (Int, String) -> Int = { bridge.fontUnicode($0, $1) }
        let fontBlank: @convention(block) (Int, Int) -> Bool = { bridge.fontBlank($0, $1) }
        let fontReplace: @convention(block) (String, Int, Int, Bool) -> String = { bridge.fontReplace($0, $1, $2, $3) }
        let verification: @convention(block) (String) -> String = { bridge.verificationCode($0) }
        ctx.setObject(cacheFile, forKeyedSubscript: "__cacheFile" as NSString)
        ctx.setObject(readTxt, forKeyedSubscript: "__readTxtFile" as NSString)
        ctx.setObject(htmlFormat, forKeyedSubscript: "__htmlFormat" as NSString)
        ctx.setObject(toNum, forKeyedSubscript: "__toNumChapter" as NSString)
        ctx.setObject(fontQuery, forKeyedSubscript: "__fontQuery" as NSString)
        ctx.setObject(fontGlyph, forKeyedSubscript: "__fontGlyph" as NSString)
        ctx.setObject(fontGlyphID, forKeyedSubscript: "__fontGlyphID" as NSString)
        ctx.setObject(fontUnicode, forKeyedSubscript: "__fontUnicode" as NSString)
        ctx.setObject(fontBlank, forKeyedSubscript: "__fontBlank" as NSString)
        ctx.setObject(fontReplace, forKeyedSubscript: "__fontReplace" as NSString)
        ctx.setObject(verification, forKeyedSubscript: "__verificationCode" as NSString)
        // 发现页控件：java.open / java.searchBook 的落点。
        let openUi: @convention(block) (String, String, String) -> Void = { ui, scheme, data in
            ToastCenter.recordSourceAction(.open(ui: ui, scheme: scheme, data: data))
        }
        let searchBook: @convention(block) (String, String) -> Void = { key, sourceName in
            ToastCenter.recordSourceAction(.search(key: key, sourceName: sourceName))
        }
        ctx.setObject(openUi, forKeyedSubscript: "__openUi" as NSString)
        ctx.setObject(searchBook, forKeyedSubscript: "__searchBook" as NSString)
    }

    /// Stable 16-hex-digit identifier, generated once per app install and kept in UserDefaults.
    /// Same shape as Android's ANDROID_ID; not tied to any hardware or account.
    static var installIdentifier: String {
        let key = "SourceInstallIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key), existing.count == 16 { return existing }
        let fresh = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    private func makeContext(_ context: RuleContext? = nil) -> JSContext {
        let ctx = JSContext()!
        installCookieBindings(ctx)
        installCryptoBindings(ctx)
        installLoginBindings(ctx, source: context?.source ?? JSEngine.currentSource)
        ctx.exceptionHandler = { _, e in
            let message = e?.toString() ?? "未知脚本异常"
            let script = JSEngine.currentScript
            let tail = script.isEmpty ? "" : " | 脚本: \(String(script.prefix(160)))"
            print("[JS error] \(message)\(tail)")
            JSEngine.lastError = message
            // 带上出错脚本：书源调试页与 CI 日志都需要它定位。
            DebugLog.add("JS 错误：\(String(message.prefix(240)))\(tail)")
        }
        let bridge = JavaBridge(context: context, session: session,
                                responseTimeout: responseTimeout)
        ctx.setObject(bridge, forKeyedSubscript: "java" as NSString)
        installScriptBindings(ctx, bridge: bridge)
        ctx.evaluateScript(JSEngine.prelude)
        let source = context?.source ?? JSEngine.currentSource
        if let s = source, let src = ctx.objectForKeyedSubscript("source") {
            src.setObject(s.bookSourceUrl, forKeyedSubscript: "bookSourceUrl" as NSString)
            src.setObject(s.bookSourceName, forKeyedSubscript: "bookSourceName" as NSString)
            src.setObject(s.bookSourceComment ?? "", forKeyedSubscript: "bookSourceComment" as NSString)
            src.setObject(s.bookSourceType ?? 0, forKeyedSubscript: "bookSourceType" as NSString)
            src.setObject(s.customButton ?? false, forKeyedSubscript: "customButton" as NSString)
            src.setObject(s.eventListener ?? false, forKeyedSubscript: "eventListener" as NSString)
            src.setObject(s.concurrentRate ?? "", forKeyedSubscript: "concurrentRate" as NSString)
            src.setObject(s.weight ?? 0, forKeyedSubscript: "weight" as NSString)
            src.setObject(s.loginUi ?? "", forKeyedSubscript: "loginUi" as NSString)
            src.setObject(s.loginUrl ?? "", forKeyedSubscript: "loginUrl" as NSString)
        }
        if let b = context?.book, let book = ctx.objectForKeyedSubscript("book") {
            book.setObject(b.bookUrl, forKeyedSubscript: "bookUrl" as NSString)
            book.setObject(b.tocUrl ?? "", forKeyedSubscript: "tocUrl" as NSString)
            book.setObject(b.origin, forKeyedSubscript: "origin" as NSString)
            book.setObject(b.originName, forKeyedSubscript: "originName" as NSString)
            book.setObject(b.name, forKeyedSubscript: "name" as NSString)
            book.setObject(b.author, forKeyedSubscript: "author" as NSString)
            book.setObject(b.kind ?? "", forKeyedSubscript: "kind" as NSString)
            book.setObject(b.intro ?? "", forKeyedSubscript: "intro" as NSString)
            book.setObject(b.durChapterIndex, forKeyedSubscript: "durChapterIndex" as NSString)
            book.setObject(b.durChapterTitle ?? "", forKeyedSubscript: "durChapterTitle" as NSString)
        }
        if let c = context?.chapter, let chapter = ctx.objectForKeyedSubscript("chapter") {
            chapter.setObject(c.url, forKeyedSubscript: "url" as NSString)
            chapter.setObject(c.title, forKeyedSubscript: "title" as NSString)
            chapter.setObject(c.index, forKeyedSubscript: "index" as NSString)
            chapter.setObject(c.url, forKeyedSubscript: "baseUrl" as NSString)
        }
        return ctx
    }

    /// 当前正在求值的脚本（异常日志里带出来，便于定位是哪一段规则出错）。
    /// 批量校验是并发的，必须按线程隔离，否则日志里的脚本会串。
    static var currentScript: String {
        get { (Thread.current.threadDictionary[__currentScriptKey] as? String) ?? "" }
        set { Thread.current.threadDictionary[__currentScriptKey] = newValue }
    }
    private static let __currentScriptKey = "legado.currentScript"

    /// Evaluate a JS snippet with `result`, `baseUrl`, `book`, `chapter`, `key`, `page` in scope.
    /// 每次求值都会新建 JSContext 并产生大量自动释放对象；在并发任务线程上长时间批量运行时
    /// 这些对象不会及时释放，内存持续上涨。这里用 autoreleasepool 包住整次同步求值。
    /// loginLib：loginUrl 里的书源函数库。Legado 的 loginUi 常常是
    /// `@js: result = 某函数()`，而那个函数定义在 loginUrl（登录函数库）里——
    /// 求值 loginUi / 登录脚本时必须把它一起加载，否则报 Can't find variable。
    /// - Parameter srcOverride: 覆盖脚本里的 `src` 变量。原版 imageDecode 按图片逐张调用，
    ///   脚本里的 `src` 是这张图片的地址；其它场景 `src` 是当前内容原文。
    func eval(_ script: String, result: Any? = nil, baseUrl: String? = nil,
              vars: [String: Any] = [:], jsLib: String? = nil,
              loginLib: String? = nil,
              rule: AnalyzeRule? = nil, ruleInput: Any? = nil,
              context: RuleContext? = nil, srcOverride: String? = nil) -> Any? {
        autoreleasepool {
            evalBody(script, result: result, baseUrl: baseUrl, vars: vars, jsLib: jsLib,
                     loginLib: loginLib,
                     rule: rule, ruleInput: ruleInput, context: context, srcOverride: srcOverride)
        }
    }

    private func evalBody(_ script: String, result: Any?, baseUrl: String?,
                          vars: [String: Any], jsLib: String?,
                          loginLib: String?,
                          rule: AnalyzeRule?, ruleInput: Any?,
                          context: RuleContext?, srcOverride: String? = nil) -> Any? {
        // 原版用 Rhino：`let result`、解构箭头参数、形参重声明这三种写法 Rhino 接受、
        // JavaScriptCore 报 SyntaxError。先归一化再求值。
        let originalScript = script
        let script = RuleScriptCompat.normalize(script)
        JSEngine.currentScript = script
        let effectiveContext = context ?? rule?.context
        let ctx = makeContext(effectiveContext)
        if let c = effectiveContext {
            let put: @convention(block) (String, String) -> String = { c.put($0, $1) }
            let get: @convention(block) (String) -> String = { c.get($0) }
            let bookGet: @convention(block) (String) -> String = { c.bookVariableGet($0) }
            let bookPut: @convention(block) (String, String) -> String = { c.bookVariablePut($0, $1) }
            ctx.setObject(put, forKeyedSubscript: "__contextPut" as NSString)
            ctx.setObject(get, forKeyedSubscript: "__contextGet" as NSString)
            ctx.setObject(bookGet, forKeyedSubscript: "__bookVarGet" as NSString)
            ctx.setObject(bookPut, forKeyedSubscript: "__bookVarPut" as NSString)
        }
        // Query state belongs to this eval only; never mutate the supplied analyzer.
        let r = rule ?? AnalyzeRule(content: JSNodeBridge.unwrap(result ?? ""),
                                    baseUrl: baseUrl ?? "", jsLib: jsLib,
                                    context: effectiveContext ?? RuleContext())
        var input: Any = JSNodeBridge.unwrap(ruleInput ?? r.content)
        func queryInput(_ value: JSValue) -> Any {
            // Explicit null/undefined means empty content, not the current document.
            if value.isNull || value.isUndefined {
                return AnalyzeRule.parse("", baseUrl: r.baseUrl)
            }
            let native = JSNodeBridge.unwrap(value.toObject() ?? "")
            if let html = native as? String {
                return AnalyzeRule.parse(html, baseUrl: r.baseUrl)
            }
            return native
        }
        let gs: @convention(block) (String) -> String = { s in
            r.getString(s, from: input)
        }
        let gsFrom: @convention(block) (String, JSValue) -> String = { s, value in
            r.getString(s, from: queryInput(value))
        }
        let setContent: @convention(block) (JSValue) -> Void = { value in
            input = queryInput(value)
        }
        let ge: @convention(block) (String) -> [Any] = { s in
            r.getElements(s, from: input).map { value in
                if let element = value as? Element { return JSNodeBridge(element) }
                if let list = value as? [Element] { return JSNodeListBridge(list) }
                return AnalyzeRule.jsValue(value)
            }
        }
        let parseHTML: @convention(block) (String) -> JSNodeBridge? = { html in
            guard let document = try? SwiftSoup.parse(html, r.baseUrl) else { return nil }
            return JSNodeBridge(document)
        }
        ctx.setObject(gs, forKeyedSubscript: "__ruleGetString" as NSString)
        ctx.setObject(gsFrom, forKeyedSubscript: "__ruleGetStringFrom" as NSString)
        ctx.setObject(setContent, forKeyedSubscript: "__ruleSetContent" as NSString)
        ctx.setObject(ge, forKeyedSubscript: "__ruleGetElements" as NSString)
        ctx.setObject(parseHTML, forKeyedSubscript: "__jsoupParse" as NSString)
        // TTS loginCheckJs：result 是完整 Response（body().bytes()/newBuilder()），不包成 StrResponse。
        if let t = result as? TTSResponse {
            ctx.setObject(t, forKeyedSubscript: "result" as NSString)
        } else if let list = result as? JSNodeListWithText {
            ctx.setObject(list.items, forKeyedSubscript: "__legadoListItems" as NSString)
            ctx.setObject(list.text, forKeyedSubscript: "__legadoListText" as NSString)
            if let proxy = ctx.evaluateScript("__legadoList(__legadoListItems, __legadoListText)") {
                ctx.setObject(proxy, forKeyedSubscript: "result" as NSString)
            } else {
                ctx.setObject(list.items, forKeyedSubscript: "result" as NSString)
            }
        } else if let sr = result as? StrResponse {
            // 原版 StrResponse.body() 是方法：书源脚本普遍写 `result.body()`。
            // 直接把 Swift 对象丢给 JS 时 body 是只读字符串属性，调用会报
            // “result.body is not a function”，这里包一层与原版同形的 JS 响应对象。
            let payload = "({url:\(JSEngine.jsLiteral(sr.url)),body:\(JSEngine.jsLiteral(sr.body)),code:\(sr.code),headers:\(JSEngine.jsLiteralJSON(sr.headers()))})"
            if let wrapper = ctx.evaluateScript("__legadoStrResponse(\(payload))") {
                ctx.setObject(wrapper, forKeyedSubscript: "result" as NSString)
            } else {
                ctx.setObject(sr, forKeyedSubscript: "result" as NSString)
            }
        } else if let collection = result, JSONSerialization.isValidJSONObject(collection),
                  let data = try? JSONSerialization.data(withJSONObject: collection),
                  let text = String(data: data, encoding: .utf8),
                  let native = ctx.evaluateScript("JSON.parse(\(JSEngine.jsLiteral(text)))") {
            // Foundation 的数组/字典塞进 JavaScriptCore 会变成 ObjC 集合代理，
            // 拿不到 Array.prototype 上装的 java.util.List 方法（toArray/add/size…）。
            // 这里在 JS 侧重新 JSON.parse 成原生值，语义与原版 Rhino 一致。
            ctx.setObject(native, forKeyedSubscript: "result" as NSString)
        } else {
            ctx.setObject(result ?? "", forKeyedSubscript: "result" as NSString)
        }
        ctx.setObject(baseUrl ?? "", forKeyedSubscript: "baseUrl" as NSString)
        // src 是「当前内容原文」：原版是字符串。元素结果要拼回 HTML 文本，
        // 否则脚本里的 src.match(...) / src.replace(...) 拿不到字符串。
        // 但 imageDecode 规则里 src 是**这张图片的地址**（原版按图片逐张调用），
        // 番茄系段评的脚本靠它正则提取 createSvg 参数；传整章正文会匹配错。
        if let srcOverride {
            ctx.setObject(srcOverride, forKeyedSubscript: "src" as NSString)
        } else {
            ctx.setObject(JSEngine.srcText(result), forKeyedSubscript: "src" as NSString)
        }
        for (k, v) in vars { ctx.setObject(v, forKeyedSubscript: k as NSString) }
        if let lib = jsLib, !lib.isEmpty, !lib.hasPrefix("{") { ctx.evaluateScript(lib) }
        if let login = loginLib, !login.isEmpty, !login.hasPrefix("{") { ctx.evaluateScript(login) }
        // A rule's let/const bindings must not collide with bridge globals or
        // change the lexical scope captured by jsLib helpers. A block preserves
        // JavaScript completion values (unlike an IIFE without an explicit return).
        // 裸块不允许顶层 return，而 Legado 书源脚本（发现规则、登录脚本等）普遍用 return 结尾。
        // 顶层 return 是解析期就能判定的语法形态，按它选择包裹方式：函数体只在真需要时使用，
        // 不靠「先失败再重试」，避免任何语句被执行两次。
        func wrapScript(_ body: String) -> String {
            RuleScanner.firstTopLevel(body, ["return"]) != nil
                ? "(function(){\n" + body + "\n})()"
                : "{\n" + body + "\n}"
        }
        JSEngine.lastError = nil
        var evaluated = ctx.evaluateScript(wrapScript(script))
        if evaluated == nil, script != originalScript,
           let message = JSEngine.lastError, message.contains("SyntaxError") {
            // 归一化把脚本改坏了（少见）：退回原文再求值一次，别让书源直接失败。
            DebugLog.add("≡脚本归一化后无法解析，已回退原文")
            JSEngine.currentScript = originalScript
            JSEngine.lastError = nil
            evaluated = ctx.evaluateScript(wrapScript(originalScript))
        }
        if evaluated == nil || evaluated!.isUndefined || evaluated!.isNull {
            // 有些书源规则被截断（结尾的模板字符串少了反引号），JSC 只会报 Unexpected EOF。
            // 这是可以确定补齐的语法缺口：未闭合的模板字符串补一个反引号再重新包一层求值。
            if let message = JSEngine.lastError, message.contains("Unexpected EOF"),
               let repaired = JSEngine.repairUnterminatedString(script) {
                JSEngine.lastError = nil
                evaluated = ctx.evaluateScript(wrapScript(repaired))
                if evaluated != nil, evaluated!.isUndefined == false, evaluated!.isNull == false {
                    DebugLog.add("≡脚本结尾的引号缺失，已自动补齐")
                }
            }
        }
        // 依赖浏览器环境（document/window/fetch/DOMParser…）的脚本在 JavaScriptCore 里必然失败，
        // 交给 App 注入的无头 WKWebView 再跑一次（CI/harness 没注入 → 自动跳过）。
        if (evaluated == nil || evaluated!.isUndefined || evaluated!.isNull),
           let message = JSEngine.lastError, HeadlessWeb.needsBrowser(message),
           let out = JSEngine.runInHeadlessWeb(script: script, content: result, baseUrl: baseUrl) {
            DebugLog.add("≡脚本依赖浏览器环境，已用无头 WebView 执行")
            return out
        }
        if (evaluated == nil || evaluated!.isUndefined || evaluated!.isNull),
           let message = JSEngine.lastError, HeadlessWeb.needsBrowser(message), !HeadlessWeb.isAvailable {
            DebugLog.add("≡脚本依赖浏览器环境，但当前环境没有无头 WebView（可用 App 注入后生效）")
        }
        guard let v = evaluated, !v.isUndefined, !v.isNull else {
            // 脚本可能只排了延迟回调（java.postDelayed）而没有返回值：也要执行它们。
            ctx.evaluateScript("if(typeof __drainDelayed==='function')__drainDelayed()")
            if JSEngine.lastError != nil {
                DebugLog.add("JS 脚本失败：\(String(script.prefix(240)))")
            }
            return nil
        }
        if v.isString || v.isNumber || v.isBoolean { return v.toString() }
        if v.isArray { return JSNodeBridge.unwrap(v.toArray() ?? []) }
        if let object = v.toObject() { return JSNodeBridge.unwrap(object) }
        return v.toString()
    }

    /// JS 字面量：把 Swift 字符串安全地嵌进脚本源码。
    /// JS 字面量：JSON 编码任意可序列化值。
    static func jsLiteralJSON(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// JS 字面量：把 Swift 字符串安全地嵌进脚本源码。
    static func jsLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }

    /// 用无头 WebView 执行依赖浏览器环境的脚本；没注入实现（CI/harness）或已在主线程时返回 nil。
    static func runInHeadlessWeb(script: String, content: Any?, baseUrl: String?) -> String? {
        guard let runner = HeadlessWeb.runner else { return nil }
        var html: String?
        if let s = content as? String, s.contains("<") {
            html = s
        } else if let element = content as? Element, let outer = try? element.outerHtml() {
            html = outer
        }
        let url = html == nil ? baseUrl : nil
        let value = runner.run(html: html, url: url, js: script, timeout: 15)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// 规则 JS 里的 src：始终是字符串（元素集合取各元素 outerHtml 拼接）。
    static func srcText(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if let list = value as? JSNodeListWithText { return list.text }
        if let node = value as? JSNodeBridge { return node.outerHtml() }
        if let list = value as? JSNodeListBridge {
            return list.elements.map { (try? $0.outerHtml()) ?? "" }.joined(separator: "\n")
        }
        if let array = value as? [Any] {
            return array.map { item -> String in
                if let s = item as? String { return s }
                if let node = item as? JSNodeBridge { return node.outerHtml() }
                return "\(item)"
            }.joined(separator: "\n")
        }
        return "\(value)"
    }

    func evalString(_ script: String, result: Any? = nil, baseUrl: String? = nil,
                    vars: [String: Any] = [:], jsLib: String? = nil,
                    loginLib: String? = nil,
                    context: RuleContext? = nil, srcOverride: String? = nil) -> String? {
        guard let v = eval(script, result: result, baseUrl: baseUrl, vars: vars,
                           jsLib: jsLib, loginLib: loginLib, context: context,
                           srcOverride: srcOverride) else { return nil }
        if let s = v as? String { return s }
        if let a = v as? [Any] { return a.map { "\($0)" }.joined(separator: "\n") }
        if JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v) {
            return String(data: d, encoding: .utf8)
        }
        return "\(v)"
    }

    /// 阅读器里点击评论气泡的结果：地址、书源直接给的页面内容、或失败原因。
    struct ReviewClickResult {
        var url: String?
        var content: String?
        /// 脚本出错时的原因（书源自己的接口挂了、脚本写错等）；空表示脚本跑通了。
        var error: String?
    }

    /// 「宽松 JSON」补丁：JSON.parse 出来的对象，访问不存在的字段时返回空对象而不是抛异常；
    /// 解析失败时也返回一个空壳。
    ///
    /// 为什么需要：书源脚本常在打开评论页之前先调一个自己的接口
    /// （番茄聚合就是先取 forum_id），那个接口一旦挂了（403），
    /// `resp.data.forum_data.forum_id` 里的 resp.data 是 undefined → 脚本当场抛错 →
    /// 评论页一个都没打开。而评论页的内容其实是书源自己给的那份 HTML，与那个接口无关。
    /// 打了这个补丁，脚本就能继续走到打开页面的那一步（页面照样是白屏，但能打开）。
    private static let deepJSONPatch = """
    (function () {
      if (globalThis.__legadoDeepJSON) return;
      var origParse = JSON.parse;
      function wrap(obj) {
        return new Proxy(obj, {
          get: function (t, k) {
            if (k === 'toString' || k === 'valueOf') return function () { return ''; };
            if (k === 'then') return undefined;
            if (typeof k === 'symbol') return undefined;
            if (!(k in t)) t[k] = wrap({});
            return t[k];
          },
          has: function () { return true; }
        });
      }
      JSON.parse = function (text, reviver) {
        var v;
        try { v = origParse(text, reviver); } catch (e) { return wrap({}); }
        if (v && typeof v === 'object' && !Array.isArray(v)) return wrap(v);
        return v;
      };
      globalThis.__legadoDeepJSON = true;
    })();
    """

    /// 阅读器里点击评论气泡：click 是书源里的函数调用（如 showCmt('书','章','段','数')），
    /// 在书源的 loginUrl 函数库里执行，收集它通过 java.showBrowser/startBrowser 想打开的网址。
    /// content 是书源直接给的页面内容（Legado 的 showBrowser(url, content) 语义）：
    /// 番茄聚合的评论页是 gitee 上的静态 html，服务器按 text/plain 发，
    /// 直接请求网址只会显示源码；按内容渲染才是原版行为。
    func resolveClickURL(source: BookSource, click: String) -> ReviewClickResult {
        let lib = SourceLoginForm.loginScript(source.loginUrl) ?? ""
        var opened: String?
        var pageContent: String?
        let lock = NSLock()
        ToastCenter.pushBrowserCapture { u, c in
            lock.lock()
            if opened == nil, !u.isEmpty { opened = u; pageContent = c }
            lock.unlock()
        }
        defer { ToastCenter.popBrowserCapture() }

        /// 跑一次点击脚本。deepJSON=true 时用「宽松 JSON」补丁。
        func attempt(deepJSON: Bool) -> Result<String, LoginScriptError> {
            lock.lock(); opened = nil; pageContent = nil; lock.unlock()
            return runLoginScript(source: source, library: lib, call: click, deepJSON: deepJSON)
        }

        var outcome = attempt(deepJSON: false)
        lock.lock()
        let needsCacheRetry = opened == nil
        lock.unlock()

        if needsCacheRetry, case .success = outcome {
            // 知秋段评：书源用「已渲染」标记防止重复打开；标记没被清 → 直接跳过。
            // 清掉标记重试一次。
            let keys = JSEngine.reviewCacheKeys(in: click)
            if !keys.isEmpty {
                let script = keys.map { "cache.deleteMemory('\($0)')" }.joined(separator: ";")
                _ = runLoginScript(source: source, library: lib, call: script)
                outcome = attempt(deepJSON: false)
            }
        }

        lock.lock()
        let stillNothing = opened == nil
        lock.unlock()

        if stillNothing {
            // 书源自己的接口挂了（番茄聚合取 forum_id 那个 403）：脚本会当场抛错，
            // 评论页开不了。再跑一次，这次 JSON 解析出的对象「缺字段也不报错」，
            // 脚本就能走到打开页面的那一步（页面内容还是书源给的那份）。
            DebugLog.add("≡段评重试：书源脚本没打开页面，用宽松 JSON 再试一次")
            outcome = attempt(deepJSON: true)
        }

        lock.lock()
        let result = opened
        let content = pageContent
        lock.unlock()
        // 诊断：点击没反应时，靠这几行能立刻看出是脚本报错、还是脚本没调 showBrowser。
        var error: String?
        switch outcome {
        case .failure(let e):
            DebugLog.add("≡段评点击失败：\(e.message)")
            // 失败原因要回到界面上：否则用户点了没反应，完全不知道是书源自己的接口挂了。
            error = "评论打不开：\(e.message)"
        case .success:
            if result == nil {
                // 脚本执行成功但没打开页面：多半是 createSvg 里的守卫
                // （缓存标记未清 / 共享 Token 为空）走了 toast 分支。
                let token = (try? JSEngine.shared.evalString("String(source.getVariable())",
                                                            context: RuleContext(source: source))) ?? ""
                DebugLog.add("≡段评未打开：共享Token=\(token.isEmpty ? "空" : "已设置")，"
                             + "缓存标记=\(click.count > 12 ? String(click.prefix(12)) + "…" : click)")
                error = "评论打不开：书源脚本没有打开任何页面（可能缺少 Token 或接口不可用）"
            } else {
                DebugLog.add("≡段评地址：\(result!)" + (content?.isEmpty == false ? "（带页面内容 \(content!.count) 字）" : ""))
            }
        }
        return ReviewClickResult(url: result, content: content, error: error)
    }

    /// 从书源的点击表达式里取出「已渲染」标记的键。
    /// 形如 createSvg('bid','cid',pid,…) → fq-bid-cid-pid（番茄系段评的约定）。
    static func reviewCacheKeys(in click: String) -> [String] {
        let pattern = "createSvg[0-9]*\\(\\s*['\"](\\d+)['\"]\\s*,\\s*['\"](-?\\d+)['\"]\\s*,\\s*(-?\\d+)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = click as NSString
        var out: [String] = []
        for m in re.matches(in: click, range: NSRange(location: 0, length: ns.length)) {
            let a = ns.substring(with: m.range(at: 1))
            let b = ns.substring(with: m.range(at: 2))
            let c = ns.substring(with: m.range(at: 3))
            out.append("fq-\(a)-\(b)-\(c)")
        }
        return out
    }

    /// 在书源上下文里执行一段 JS（登录按钮、login() 等），返回字符串结果；脚本抛错时返回 .failure。
    /// 脚本 = loginUrl 里的函数库 + 调用语句。toast 通过 ToastCenter 出口。
    /// deepJSON=true 时打「宽松 JSON」补丁：JSON.parse 出来的对象缺字段也返回空对象，
    /// 解析失败也返回空壳 —— 书源脚本在打开评论页前调了一个挂掉的接口时，
    /// 靠它才能走到打开页面的那一步。
    func runLoginScript(source: BookSource, library: String?, call: String,
                        formValues: [String: String] = [:], deepJSON: Bool = false) -> Result<String, LoginScriptError> {
        let context = RuleContext(source: source)
        let ctx = makeContext(context)
        // Legado 执行登录按钮时，`result` 是当前表单值（键为字段名）；`book`/`chapter` 在登录页没有，保持默认。
        ctx.setObject(formValues, forKeyedSubscript: "result" as NSString)
        let openBrowser: @convention(block) (String, String, String) -> Void = { ToastCenter.openBrowser($0, $1, $2.isEmpty ? nil : $2) }
        ctx.setObject(openBrowser, forKeyedSubscript: "__openBrowser" as NSString)
        var thrown: String?
        ctx.exceptionHandler = { _, value in thrown = value?.toString() ?? "脚本错误" }
        // 与规则求值一致：登录脚本里的 java.put/java.get 写入书源作用域（可持久化），
        // 面板按钮把状态写进变量后，搜索/详情阶段的脚本才能读到同一份数据。
        let put: @convention(block) (String, String) -> String = { context.put($0, $1) }
        let get: @convention(block) (String) -> String = { context.get($0) }
        ctx.setObject(put, forKeyedSubscript: "__contextPut" as NSString)
        ctx.setObject(get, forKeyedSubscript: "__contextGet" as NSString)
        if let lib = source.jsLib, !lib.isEmpty, !lib.hasPrefix("{") { ctx.evaluateScript(lib) }
        if let l = library, !l.isEmpty { ctx.evaluateScript(l) }
        if deepJSON { ctx.evaluateScript(JSEngine.deepJSONPatch) }
        let value = ctx.evaluateScript(call)
        // java.postDelayed 排队的回调在脚本返回后执行（与 Android Handler 语义一致）。
        ctx.evaluateScript("if(typeof __drainDelayed==='function')__drainDelayed()")
        if let t = thrown { return .failure(LoginScriptError(message: t)) }
        guard let v = value, !v.isUndefined, !v.isNull else { return .success("") }
        return .success(v.toString() ?? "")
    }
}

struct LoginScriptError: Error { let message: String }

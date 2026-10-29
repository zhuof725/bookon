import Foundation

/// 朗读错误：给用户看的句子不附带原始地址，避免泄漏引擎账号信息。
enum AloudError: LocalizedError {
    case invalidURLOrEmptyAudio
    case serverRejected(String)
    case contentTypeMismatch(String)
    case tooManyFailures(String)
    /// loginCheckJs 把响应 body 重写为字节数组以外的类型（包含脚本 throw 的 nil）。
    case scriptFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidURLOrEmptyAudio: return "引擎地址无效或没有返回音频"
        case .serverRejected(let body): return "TTS 服务器返回错误：\(String(body.prefix(200)))"
        case .contentTypeMismatch(let type): return "返回类型不匹配：\(type)"
        case .tooManyFailures(let last): return "连续多次请求失败，已暂停朗读。\n\(last)"
        case .scriptFailure(let m): return "引擎返回脚本失败：\(m)"
        }
    }
}

/// 在线朗读音频抓取：按引擎 URL 规则合成请求并校验响应类型。
enum AloudAudioFetcher {
    /// 合成并请求一段话的音频。`speed` 是原版 speakSpeed（界面语速值 + 5）。
    static func fetchAudio(engine: HTTPTTS, text: String, speed: Int) async throws -> Data {
        let speakText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speakText.isEmpty else { throw AloudError.invalidURLOrEmptyAudio }
        let vars: [String: Any] = ["speakText": speakText, "speakSpeed": speed]
        // 登录头（loginUrl 脚本通过 source.putLoginHeader 写入）与引擎 header 合并。
        let headerSeed = mergedHeader(engine: engine, vars: vars)
        let urlRaw = engine.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let analyze = AnalyzeUrl(rawUrl: urlRaw, key: nil, page: 1, baseUrl: nil,
                                 sourceHeader: headerSeed.isEmpty ? nil : headerSeed,
                                 context: RuleContext(source: engine.bookSourceShim),
                                 jsLib: engine.jsLib, extraVars: vars)
        let (data, response, _) = try await analyze.fetchData(readTimeout: 120)
        let http = response as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AloudError.serverRejected(body.isEmpty ? "HTTP \(code)" : body)
        }
        // 响应字节 + 原始 Content-Type；有 loginCheckJs 时交给脚本检查/重写（原版 HttpReadAloudService）。
        var checkedData = data
        var contentType = ((http?.value(forHTTPHeaderField: "Content-Type") ?? "")
            .split(separator: ";").first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let js = engine.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines), !js.isEmpty,
           let rewritten = try? rewrite(engine: engine, code: http?.statusCode ?? 200, contentType: contentType,
                                        data: data, vars: vars) {
            if let bytes = rewritten.data {
                checkedData = bytes
                if let ct = rewritten.contentType?.lowercased() { contentType = ct }
            } else if let message = rewritten.message {
                throw AloudError.scriptFailure(message)
            }
        }
        // 原版：返回 JSON/文本就是报错信息；contentType 校验是放宽的正则。
        if contentType == "application/json" || contentType.hasPrefix("text/") || contentType.contains("problem+json") {
            throw AloudError.serverRejected(String(data: checkedData, encoding: .utf8) ?? "")
        }
        if let expect = engine.contentType?.trimmingCharacters(in: .whitespacesAndNewlines), !expect.isEmpty {
            let pattern = try? NSRegularExpression(pattern: "^(?:" + expect + ")$", options: [])
            let range = NSRange(location: 0, length: (contentType as NSString).length)
            let matched = pattern?.firstMatch(in: contentType, options: [], range: range) != nil
            if !matched, !contentType.isEmpty {
                throw AloudError.contentTypeMismatch(contentType)
            }
        }
        guard !checkedData.isEmpty else { throw AloudError.invalidURLOrEmptyAudio }
        return checkedData
    }

    /// loginCheckJs 执行后重写后的字节与最终 Content-Type；文本错误可另走 serverRejected。
    private struct Rewritten { let data: Data?; let contentType: String?; let message: String? }

    /// 与原版一致：每次拿到响应都执行 loginCheckJs，脚本可返回新响应（newBuilder().build()）或文本错误。
    private static func rewrite(engine: HTTPTTS, code: Int, contentType: String,
                                data: Data, vars: [String: Any]) throws -> Rewritten {
        guard let js = engine.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines), !js.isEmpty else {
            return Rewritten(data: data, contentType: contentType, message: nil)
        }
        let shim = engine.bookSourceShim
        let origin = TTSResponse(data: data, url: "", code: code, headers: ["Content-Type": contentType])
        let v = JSEngine.shared.eval(js, result: origin, vars: vars, jsLib: engine.jsLib,
                                     context: RuleContext(source: shim))
        // 脚本产出两种可能：①newBuilder().build() → TTSResponse，按字节+新CT ②字符串 → JSON/文本错误
        if let resp = v as? TTSResponse {
            let bytes = resp.data
            guard !bytes.isEmpty else { return Rewritten(data: nil, contentType: nil, message: "loginCheckJs 返回空字节") }
            let header = resp.header("Content-Type")
            let ct = header.isEmpty ? contentType : header
            return Rewritten(data: bytes, contentType: ct, message: nil)
        }
        if let str = v as? String {
            let ct = str.hasPrefix("{") ? "application/json" : "text/plain"
            return Rewritten(data: str.data(using: .utf8), contentType: ct, message: nil)
        }
        return Rewritten(data: nil, contentType: nil, message: v == nil ? "脚本执行出错" : "返回值不是响应")
    }

    private static func mergedHeader(engine: HTTPTTS, vars: [String: Any]) -> String {
        // 引擎 header 可以带 {{...}} 或 @js:；登录脚本可能通过 httpTts:<id> 键写了登录头，两项合并。
        let engineHeader = engine.header?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let loginJSON = JSEngine.loginStore.getLoginHeader(engine.key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if loginJSON.isEmpty { return engineHeader }
        guard let loginObj = AnalyzeUrl.looseJSON(loginJSON) else { return engineHeader }
        if engineHeader.isEmpty { return loginJSON }
        // 两者合并：登录头的值覆盖同名字段（与原版 getHeaderMap(true) 语义一致）。
        let engineFields = AnalyzeUrl.headerFields(engineHeader, key: nil, page: 1, baseUrl: nil,
                                                   context: RuleContext(source: engine.bookSourceShim),
                                                   jsLib: engine.jsLib, extraVars: vars)
        var merged = engineFields
        for (k, v) in loginObj { merged[k] = "\(v)" }
        return AnalyzeUrl.jsonString(merged) ?? loginJSON
    }
}

/// 音频文件缓存：目录 Caches/httpTTS/<标题md5>_<内容md5>.audio。
/// 键含引擎 URL 与语速，换引擎/语速不串缓存（与原版命名规则一致）。
final class AloudAudioCache: @unchecked Sendable {
    static let shared = AloudAudioCache(directoryURL: AloudAudioCache.defaultDirectoryURL())
    /// 缓存上限：512MB（约 30+ 小时在线朗读），够听完一整本再回头拖进度。
    static let byteLimit = 512 * 1024 * 1024

    let directoryURL: URL
    private let lock = NSLock()

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func defaultDirectoryURL() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("httpTTS", isDirectory: true)
    }

    func key(chapter: String, engineURL: String, speed: Int, text: String) -> String {
        let bridge = JavaBridge()
        let title = bridge.md5Encode16(chapter)
        let content = bridge.md5Encode16("\(engineURL)-|-\(speed)-|-\(text)")
        return "\(title)_\(content)"
    }

    func fileURL(forKey key: String) -> URL { directoryURL.appendingPathComponent(key + ".audio") }

    func cachedFile(forKey key: String) -> URL? {
        let url = fileURL(forKey: key)
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 0 else { return nil }
        return url
    }

    func store(_ data: Data, forKey key: String) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = fileURL(forKey: key)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        pruneLocked()
        return url
    }

    func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(forKey: key))
    }

    /// 清空全部缓存（「朗读引擎管理 → 清空缓存」）。
    func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directoryURL)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    /// 超限后按修改时间淘汰最旧的；最新文件永不被本轮写盘淘汰。
    private func pruneLocked() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var total = 0
        var dated: [(URL, Date, Int)] = []
        for file in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            dated.append((file, values?.contentModificationDate ?? Date.distantPast, size))
            total += size
        }
        guard total > AloudAudioCache.byteLimit else { return }
        for item in dated.sorted(by: { $0.1 < $1.1 }) {
            if total <= AloudAudioCache.byteLimit * 3 / 4 { break }
            try? FileManager.default.removeItem(at: item.0)
            total -= item.2
        }
    }
}

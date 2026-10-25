import Foundation

/// 番茄「真人录播」书的 TTS 通道。
///
/// 真人录播书的 `playinfo` 对任何 `tone_id` 都返回同一个音频（服务端只有一版录音），
/// 但同一本书的**文字版**（toneinfo 里的 `relate_novel_bookid`）会按 `tone_id`
/// 生成不同的 TTS 音频。这里在用户选了合成音色（tone > 0）时：
///   1. 取 toneinfo 拿到文字版 book_id；
///   2. 取文字版目录，按章节标题/序号匹配当前章；
///   3. 用该章 item_id + tone_id 请求 playinfo，返回 TTS 音频地址。
/// 匹配不到时返回 nil，调用方回落到书源自己的正文规则。
enum FanqieTTS {
    struct ToneInfo {
        var relatedBookID: String?
        var toneIDs: [String]
    }

    struct TocItem {
        var id: String
        var title: String
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var toneCache: [String: (Date, ToneInfo)] = [:]
    private nonisolated(unsafe) static var tocCache: [String: (Date, [TocItem])] = [:]
    private static let cacheTTL: TimeInterval = 600

    // MARK: - 对外

    /// 这个源是否支持番茄 TTS（脚本里有签名助手和 toneinfo）。
    static func isSupported(source: BookSource) -> Bool {
        let script = [source.jsLib, source.loginUrl, source.loginUi]
            .compactMap { $0 }.joined(separator: "\n")
        return script.contains("fanqieSignHeaders") && script.contains("toneinfo")
    }

    /// 当前书的文字版 book_id（没有则 nil）。
    static func relatedBookID(source: BookSource, book: Book) async -> String? {
        await toneInfo(source: source, book: book)?.relatedBookID
    }

    /// 源变量里是否选了合成音色（tone > 0 且没有真人专辑）。
    static func selectedSyntheticTone(source: BookSource) -> String? {
        // 规则会按 _ts 在三份存储里挑最新那份，这里也必须看同一份。
        let selection = SourceTone.currentSelection(source: source)
        let abook = selection.abook.trimmingCharacters(in: .whitespacesAndNewlines)
        let tone = selection.tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard abook.isEmpty, let value = Int(tone), value > 0 else { return nil }
        return tone
    }

    /// 用文字版 + 指定音色取当前章的音频地址；不适用时返回 nil。
    static func audioURL(source: BookSource, book: Book, chapter: BookChapter,
                         tone: String? = nil) async -> String? {
        guard isSupported(source: source) else { return nil }
        guard let tone = tone ?? selectedSyntheticTone(source: source), (Int(tone) ?? 0) > 0 else { return nil }
        guard let info = await toneInfo(source: source, book: book),
              let related = info.relatedBookID,
              !related.isEmpty, related != bookID(from: book.bookUrl) else { return nil }
        guard let toc = await toc(source: source, book: book, relatedBookID: related), !toc.isEmpty else { return nil }
        guard let item = match(chapter: chapter, in: toc) else { return nil }
        return await playURL(source: source, book: book, itemID: item.id, tone: tone)
    }

    /// 取某个音色在文字版第一/匹配章上的媒体路径（探测用）。
    static func mediaPath(source: BookSource, book: Book, chapter: BookChapter, tone: String) async -> String? {
        guard let url = await audioURL(source: source, book: book, chapter: chapter, tone: tone) else { return nil }
        return URL(string: url)?.path ?? url
    }

    // MARK: - 数据

    private static func toneInfo(source: BookSource, book: Book) async -> ToneInfo? {
        guard let bid = bookID(from: book.bookUrl) else { return nil }
        if let cached = cachedToneInfo(bid) { return cached }
        let js = """
        (function(){
          try{
            var u = FQ_BASE + "/bookapi/audio/toneinfo/?" + FQ_P + "&book_id=" + String(__bid);
            var h = fanqieSignHeaders(String(u), null);
            h["Cookie"] = "install_id=" + FQ_IID;
            var hm = new Packages.java.util.HashMap();
            for(var k in h){ hm.put(String(k), String(h[k])); }
            return String(java.get(String(u), hm).body());
          }catch(e){ return ""; }
        })()
        """
        guard let body = await eval(js, source: source, book: book, vars: ["__bid": bid]),
              !body.isEmpty, let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TonePayload.self, from: data),
              let info = payload.data else { return nil }
        let value = ToneInfo(relatedBookID: info.relate_novel_bookid?.value,
                             toneIDs: (info.tts_tones ?? []).compactMap { $0.id?.value })
        storeToneInfo(bid, value)
        return value
    }

    private static func toc(source: BookSource, book: Book, relatedBookID: String) async -> [TocItem]? {
        if let cached = cachedToc(relatedBookID) { return cached }
        let js = """
        (function(){
          try{
            var u = FQ_BASE + "/bookapi/directory/all_items/v?" + FQ_P + "&book_id=" + String(__bid);
            var h = fanqieSignHeaders(String(u), null);
            h["Cookie"] = "install_id=" + FQ_IID;
            var hm = new Packages.java.util.HashMap();
            for(var k in h){ hm.put(String(k), String(h[k])); }
            return String(java.get(String(u), hm).body());
          }catch(e){ return ""; }
        })()
        """
        guard let body = await eval(js, source: source, book: book, vars: ["__bid": relatedBookID]),
              !body.isEmpty, let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TocPayload.self, from: data),
              let list = payload.data?.item_data_list else { return nil }
        let items = list.compactMap { raw -> TocItem? in
            guard let id = raw.item_id?.value, !id.isEmpty else { return nil }
            return TocItem(id: id, title: raw.title ?? "")
        }
        guard !items.isEmpty else { return nil }
        storeToc(relatedBookID, items)
        return items
    }

    private static func playURL(source: BookSource, book: Book, itemID: String, tone: String) async -> String? {
        let js = """
        (function(){
          try{
            var u = "https://reading.snssdk.com/reading/reader/audio/playinfo/?tone_id=" + String(__tone)
                  + "&item_ids=" + String(__item) + "&pv_player=-1&aid=3040&device_platform=android";
            var h = fanqieSignHeaders(u, null);
            var hm = new Packages.java.util.HashMap();
            for (var k in h) { hm.put(String(k), String(h[k])); }
            var body = String(java.get(u, hm).body());
            var d = JSON.parse(body).data || [];
            if (d[0] && d[0].main_url) { return String(d[0].main_url); }
            return "";
          }catch(e){ return ""; }
        })()
        """
        guard let url = await eval(js, source: source, book: book,
                                   vars: ["__tone": tone, "__item": itemID]),
              url.hasPrefix("http") else { return nil }
        return url
    }

    /// 刷新/换音色时清掉 toneinfo/目录缓存，保证重新取的是新链接。
    static func clearCache() {
        lock.lock()
        toneCache.removeAll()
        tocCache.removeAll()
        lock.unlock()
    }

    // MARK: - 缓存（NSLock 不能在 async 上下文里直接用，抽成同步函数）

    private static func cachedToneInfo(_ bid: String) -> ToneInfo? {
        lock.lock(); defer { lock.unlock() }
        guard let cached = toneCache[bid], Date().timeIntervalSince(cached.0) < cacheTTL else { return nil }
        return cached.1
    }

    private static func storeToneInfo(_ bid: String, _ info: ToneInfo) {
        lock.lock(); toneCache[bid] = (Date(), info); lock.unlock()
    }

    private static func cachedToc(_ related: String) -> [TocItem]? {
        lock.lock(); defer { lock.unlock() }
        guard let cached = tocCache[related], Date().timeIntervalSince(cached.0) < cacheTTL else { return nil }
        return cached.1
    }

    private static func storeToc(_ related: String, _ items: [TocItem]) {
        lock.lock(); tocCache[related] = (Date(), items); lock.unlock()
    }

    // MARK: - 匹配

    private static func match(chapter: BookChapter, in items: [TocItem]) -> TocItem? {
        let title = normalized(chapter.title)
        if !title.isEmpty {
            if let exact = items.first(where: { normalized($0.title) == title }) { return exact }
            if let partial = items.first(where: {
                let other = normalized($0.title)
                return other.count > 4 && (other.contains(title) || title.contains(other))
            }) { return partial }
        }
        if items.indices.contains(chapter.index) { return items[chapter.index] }
        return nil
    }

    private static func normalized(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "^第?[0-9一二三四五六七八九十百千]+[章节集回]?",
                                         with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[\\s\\p{P}\\p{S}0-9]", with: "",
                                         options: .regularExpression)
        return text
    }

    private static func bookID(from url: String) -> String? {
        if let range = url.range(of: "(?:book_id|bookId)=([0-9]+)", options: .regularExpression) {
            let digits = String(url[range]).replacingOccurrences(of: "[^0-9]", with: "",
                                                                 options: .regularExpression)
            return digits.isEmpty ? nil : digits
        }
        let digits = url.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return digits.isEmpty ? nil : digits
    }

    private static func eval(_ js: String, source: BookSource, book: Book?,
                             vars: [String: String]) async -> String? {
        await Task.detached { () -> String? in
            JSEngine.shared.evalString(js, vars: vars, jsLib: source.jsLib,
                                       context: RuleContext(source: source, book: book))
        }.value
    }

    // MARK: - 解码

    private struct TonePayload: Decodable {
        struct Payload: Decodable {
            var relate_novel_bookid: FlexID?
            var tts_tones: [Tone]?
        }
        struct Tone: Decodable {
            var id: FlexID?
        }
        var data: Payload?
    }

    private struct TocPayload: Decodable {
        struct Payload: Decodable {
            var item_data_list: [Item]?
        }
        struct Item: Decodable {
            var item_id: FlexID?
            var title: String?
        }
        var data: Payload?
    }

    private struct FlexID: Decodable {
        var value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int64.self) {
                value = String(number)
            } else if let text = try? container.decode(String.self) {
                value = text
            } else {
                throw DecodingError.typeMismatch(FlexID.self,
                    .init(codingPath: container.codingPath, debugDescription: "id 不是数字或字符串"))
            }
        }
    }
}

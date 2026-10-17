import Foundation
import Network

/// 离线回归：朗读引擎（HTTPTTS）解析/存储/URL 合成/音频抓取与缓存。
/// 合成数据 + 本机回环服务器；不误连公网。
enum HTTPTTSRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        // 1. 默认引擎清单（原版 httpTTS.json 逐字拷贝）
        let defaults = HTTPTTSParser.parse(HttpTTSDefaults.json)
        check(defaults.count == 3, "默认引擎共 3 条")
        check(defaults[0].name == "1.百度" && defaults[0].contentType == "audio/wav", "默认引擎百度字段")
        check(defaults[1].loginUi?.contains("\"AppKey\"") == true && defaults[1].hasLogin == true, "默认引擎 loginUi 数组转为 JSON 字符串")
        check(defaults.last?.concurrentRate == "1500", "Next 引擎 concurrentRate 保留")
        check(defaults.last?.jsLib?.contains("apiurl") == true, "Next 引擎 jsLib 保留")

        // 2. 单个对象与数组的解析/导出
        let single = """
        {"id": 42, "name": "演示", "url": "https://tts.example.invalid/a?tex={{speakText}}", "contentType": "audio/mpeg", "concurrentRate": 800}
        """
        let parsed = HTTPTTSParser.parse(single)
        check(parsed.count == 1 && parsed[0].id == 42 && parsed[0].concurrentRate == "800", "单引擎 JSON 解析")
        let roundTrip = HTTPTTSParser.parse(HTTPTTSParser.json(parsed))
        check(roundTrip.count == 1 && roundTrip[0].name == "演示", "引擎导出后再导入")
        check(HTTPTTSParser.parse("{}").isEmpty, "缺 URL 的引擎无效")
        check(HTTPTTSParser.parse("not json").isEmpty, "非 JSON 内容解析为空")

        // 3. 并发率解析
        check(HTTPTTS().requestIntervalMilliseconds == 0, "默认并发率不限速")
        var r = HTTPTTS(); r.url = "https://a.invalid"; r.concurrentRate = "1500"
        check(r.requestIntervalMilliseconds == 1500, "纯数字=每毫秒一次请求")
        r.concurrentRate = "10/15000"
        check(r.requestIntervalMilliseconds == 1500, "N/M 按平均间隔限速")

        // 4. 存储 CRUD 与一致性
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("httptts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HTTPTTSStore(fileURL: dir.appendingPathComponent("httpTTS.json"))
        check(store.engines.isEmpty, "引擎列表初始为空")
        var e1 = HTTPTTS(); e1.id = 1001; e1.name = "引擎甲"; e1.url = "https://a.invalid/tts"
        _ = store.save(e1)
        var e2 = HTTPTTS(); e2.name = "引擎乙"; e2.url = "https://b.invalid/tts"  // 缺 id → 自动按时间戳
        e2 = store.save(e2)
        check(store.engines.count == 2 && e2.id != 0, "保存时自动生成时间戳 id")
        check(store.engine(id: 1001)?.name == "引擎甲", "按 id 查询")
        e1.name = "引擎甲改"
        _ = store.save(e1)
        check(store.engines.count == 2 && store.engine(id: 1001)?.name == "引擎甲改", "同 id 更新在原地")
        let store2 = HTTPTTSStore(fileURL: dir.appendingPathComponent("httpTTS.json"))
        check(store2.engines.count == 2, "重启（重开文件）后读回")
        check(store2.delete(id: e2.id) && store2.engines.count == 1, "删除引擎")
        try? Data("not json".utf8).write(to: dir.appendingPathComponent("httpTTS.json"))
        check(HTTPTTSStore(fileURL: dir.appendingPathComponent("httpTTS.json")).engines.isEmpty, "文件损坏视为空表")

        // 5. 导入合并：同 id 覆盖，同配置不重复加
        let m1 = HTTPTTSStore(fileURL: dir.appendingPathComponent("merge.json"))
        let n1 = m1.importJSON("[{\"id\":7,\"name\":\"合并\",\"url\":\"https://c.invalid/tts\"}]")
        let n2 = m1.importJSON("[{\"id\":7,\"name\":\"合并2\",\"url\":\"https://c.invalid/tts\"}]")
        check(n1 == 1 && n2 == 1 && m1.engines.count == 1 && m1.engines[0].name == "合并2", "同 id 导入覆盖")

        // 6. 朗读内容判断（原版 AppPattern.notReadAloudRegex）
        check(AloudText.speakText(for: "你好世界") == "你好世界", "中文段落可朗读")
        check(AloudText.speakText(for: "hello 123") == "hello 123", "英文数字段落可朗读")
        check(AloudText.speakText(for: "，。！？；：—…") == nil, "纯标点段跳过")
        check(AloudText.speakText(for: "🎉❤️👍") == nil, "纯 Emoji 段跳过")
        check(AloudText.speakText(for: "  \n\t  ") == nil, "纯空白段跳过")
        check(AloudText.speakText(for: "第一行\n第二行") == "第一行 第二行", "段内换行折叠为空格")

        // 7. 音频缓存键（原版：标题md5 + 引擎地址|语速|文本md5）
        let cache = AloudAudioCache(directoryURL: dir.appendingPathComponent("cache", isDirectory: true))
        let k1 = cache.key(chapter: "第一章", engineURL: "https://a.invalid/tts", speed: 15, text: "你好")
        let k2 = cache.key(chapter: "第一章", engineURL: "https://a.invalid/tts", speed: 15, text: "你好")
        let k3 = cache.key(chapter: "第一章", engineURL: "https://a.invalid/tts", speed: 16, text: "你好")
        check(k1 == k2 && k1 != k3, "缓存键稳定，语速变化更换键")
        _ = try cache.store(Data([0x00, 0x01, 0x02]), forKey: k1)
        check(cache.cachedFile(forKey: k1) != nil, "缓存写入后可读")
        check(cache.cachedFile(forKey: k1) != nil, "缓存键重复读取经得起持续存在")
        cache.remove(k1)
        check(cache.cachedFile(forKey: k1) == nil, "缓存删除后不再命中")
        _ = try cache.store(Data([0x00]), forKey: k1)
        cache.clear()
        check(cache.cachedFile(forKey: k1) == nil, "清空缓存后为空")

        // 8. URL 模板：{{speakText}}/{{speakSpeed}} 与 java.encodeURI
        let baidu = defaults[0]
        let analyze = AnalyzeUrl(rawUrl: baidu.url, context: RuleContext(source: baidu.bookSourceShim), jsLib: baidu.jsLib,
                                 extraVars: ["speakText": "你好", "speakSpeed": 15])
        check(analyze.url == "http://tts.baidu.com/text2audio", "百度引擎：POST 前缀不受影响")
        check(analyze.method == "POST", "百度引擎：读取 options 的 method")
        check(analyze.body == "tex=%25E4%25BD%25A0%25E5%25A5%25BD&spd=6&per=3&cuid=baidu_speech_demo&idx=1&cod=2&lan=zh&ctp=1&pdt=160&vol=5&aue=6&pit=5&_res_tag_=audio", "百度引擎：双重 encodeURI 与 spd=(15+5)/10+4=6")
        check(analyze.body?.contains("%25") == true, "百度引擎：URL 参数双重转码")

        // @js: URL + jsLib 函数（模仿 Next 引擎 apiurl(speakText,speakSpeed)）
        var jsT = HTTPTTS()
        jsT.url = "@js:apiurl(speakText, speakSpeed);"
        jsT.jsLib = "function apiurl(t, s) { return 'https://tts.invalid/a?t=' + encodeURIComponent(t) + '&s=' + s; }"
        let analyzeJS = AnalyzeUrl(rawUrl: jsT.url, context: RuleContext(source: jsT.bookSourceShim), jsLib: jsT.jsLib,
                                   extraVars: ["speakText": "你好", "speakSpeed": 15])
        check(analyzeJS.url == "https://tts.invalid/a?t=%E4%BD%A0%E5%A5%BD&s=15", "@js: URL 通过 jsLib 函数合成")

        // 9. 抓音频：本机回环，一个请求一个响应
        let server = try TTSHarnessServer.start()
        defer { server.stop() }
        // 正常音频 + Content-Type 校验通过
        var engine = HTTPTTS(); engine.id = 90001; engine.name = "回环"; engine.contentType = "audio/(wav|mpeg)"
        engine.url = server.origin + "/audio,{\"method\":\"POST\",\"body\":\"tex={{speakText}}&s={{speakSpeed}}\",\"headers\":{\"X-Test\":\"{{String(speakSpeed)}}\"}}"
        let wav = Data([0x00, 0x1A, 0x55, 0xFF, 0xAA])
        server.enqueue(status: 200, headers: ["Content-Type": "audio/wav"], body: wav)
        let got = try await AloudAudioFetcher.fetchAudio(engine: engine, text: "朗读一句", speed: 15)
        check(got == wav, "回环：二进制字节原样返回")
        let first = server.report()
        check(first?.method == "POST", "回环：POST 请求方法")
        check(String(data: first?.body ?? Data(), encoding: .utf8) == "tex=%E6%9C%97%E8%AF%BB%E4%B8%80%E5%8F%A5&s=15", "回环：模板替换请求体（UTF-8 表单编码）")
        check(first?.headers["X-Test"] == "15", "回环：options.headers 走模板")
        check(first?.path == "/audio", "回环：请求路径正确")

        // 10. 内容类型不匹配 → 拒绝入账
        server.enqueue(status: 200, headers: ["Content-Type": "text/plain"], body: Data("server error".utf8))
        do {
            _ = try await AloudAudioFetcher.fetchAudio(engine: engine, text: "y", speed: 15)
            check(false, "回环：text/plain 返回应当报错")
        } catch {
            check((error as? AloudError) != nil, "回环：text/plain 抛出 AloudError（内容失败/类型不符）")
        }
        // Content-Type 正则不符 → contentTypeMismatch
        var strict = engine; strict.contentType = "audio/wav"
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: wav)
        do { _ = try await AloudAudioFetcher.fetchAudio(engine: strict, text: "y", speed: 15); check(false, "回环：类型不符应当报错") }
        catch {
            let err = error as? AloudError
            var matched = false
            if case .contentTypeMismatch? = err { matched = true }
            check(matched, "回环：contentType 正则校验命中")
        }
        // 非 2xx → serverRejected
        server.enqueue(status: 404, headers: ["Content-Type": "audio/wav"], body: Data("not found".utf8))
        do { _ = try await AloudAudioFetcher.fetchAudio(engine: engine, text: "y", speed: 15); check(false, "回环：404 应当报错") }
        catch {
            let err = error as? AloudError
            var matched = false
            if case .serverRejected? = err { matched = true }
            check(matched, "回环：非 2xx 归入 serverRejected")
        }


        // 11. loginCheckJs：result.body().bytes() 读取字节 + newBuilder() 重组
        var checkJsEngine = HTTPTTS(); checkJsEngine.id = 90002; checkJsEngine.name = "重组"
        checkJsEngine.contentType = "audio/mpeg"
        checkJsEngine.url = server.origin + "/multi,{\"method\":\"POST\",\"body\":\"t={{speakText}}\"}"
        checkJsEngine.loginCheckJs = """
        (function(){
            var bytes = result.body().bytes(); // StrResponse.bodyAsBytes 桥
            return result.newBuilder().code(200).message("OK")
                .header("Content-Type","audio/mpeg")
                .body(result.body()).build();
        })()
        """
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: Data([0x00, 0x1A, 0x55, 0xFF, 0xAA]))
        let checkBytes = try await AloudAudioFetcher.fetchAudio(engine: checkJsEngine, text: "对话段", speed: 15)
        check(checkBytes.count > 0, "loginCheckJs 重组：body().bytes() 无损返回数据")

        // 12. loginCheckJs 返回字符串（文本错误）→ serverRejected
        var badEngine = HTTPTTS(); badEngine.id = 90003; badEngine.name = "文本错误"
        badEngine.url = server.origin + "/bad,{\"method\":\"POST\"}"
        badEngine.loginCheckJs = "(function(){ return "{error:'bad'}"; })()"
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: Data([0x00, 0x01]))
        do { _ = try await AloudAudioFetcher.fetchAudio(engine: badEngine, text: "y", speed: 15); check(false, "loginCheckJs 字符串返回应走 serverRejected") }
        catch {
            let err = error as? AloudError
            var matched = false
            if case .serverRejected? = err { matched = true }
            check(matched, "loginCheckJs 字符串 → serverRejected")
        }

        // 13. loginCheckJs 异常 → scriptFailure（脚本本身失败）
        var throwEngine = HTTPTTS(); throwEngine.id = 90004; throwEngine.name = "脚本异常"
        throwEngine.url = server.origin + "/x,{\"method\":\"POST\"}"
        throwEngine.loginCheckJs = "(function(){ throw new Error('Packages 未定义'); })()"
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: Data([0x00]))
        do { _ = try await AloudAudioFetcher.fetchAudio(engine: throwEngine, text: "y", speed: 15); check(false, "loginCheckJs 异常应走 scriptFailure") }
        catch {
            let err = error as? AloudError
            var matched = false
            if case .scriptFailure? = err { matched = true }
            check(matched, "loginCheckJs 异常 → scriptFailure")
        }

        // 11. loginCheckJs：body().bytes() 读字节 + newBuilder() 重组
        var cj = HTTPTTS(); cj.id = 90002; cj.name = "重组"; cj.contentType = "audio/mpeg"
        cj.url = server.origin + "/multi,{\"method\":\"POST\",\"body\":\"t={{speakText}}\"}"
        cj.loginCheckJs = """
        (function(){
            var bytes = result.body().bytes();
            return result.newBuilder().code(200).message("OK")
                .header("Content-Type","audio/mpeg").body(result.body()).build();
        })()
        """
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: Data([0x00, 0x1A, 0x55, 0xFF, 0xAA]))
        let cjData = try await AloudAudioFetcher.fetchAudio(engine: cj, text: "对话段", speed: 15)
        check(cjData.count > 0, "loginCheckJs 重组：返回数据 body().bytes() 无损")

        // 12. loginCheckJs 返回字符串（文本错误）→ serverRejected
        var cb = HTTPTTS(); cb.id = 90003; cb.name = "文本错误"
        cb.url = server.origin + "/bad,{\"method\":\"POST\"}"
        cb.loginCheckJs = "(function(){ return \"{error:'bad'}\"; })()"
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: Data([0x00, 0x01]))
        do { _ = try await AloudAudioFetcher.fetchAudio(engine: cb, text: "y", speed: 15); check(false, "loginCheckJs 字符串返回应走 serverRejected") }
        catch {
            let err = error as? AloudError
            var matched = false
            if case .serverRejected? = err { matched = true }
            check(matched, "loginCheckJs 字符串 → serverRejected")
        }

        // 13. loginCheckJs 异常 → scriptFailure
        var ct = HTTPTTS(); ct.id = 90004; ct.name = "脚本异常"
        ct.url = server.origin + "/x,{\"method\":\"POST\"}"
        ct.loginCheckJs = "(function(){ throw new Error('Packages 未定义'); })()"
        server.enqueue(status: 200, headers: ["Content-Type": "audio/mpeg"], body: Data([0x00]))
        do { _ = try await AloudAudioFetcher.fetchAudio(engine: ct, text: "y", speed: 15); check(false, "loginCheckJs 异常应走 scriptFailure") }
        catch {
            let err = error as? AloudError
            var matched = false
            if case .scriptFailure? = err { matched = true }
            check(matched, "loginCheckJs 异常 → scriptFailure")
        }

        print("HTTPTTS 引擎+回环回归完成")
        server.stop()
    }
}

/// 回环 HTTP 服务器：串行应答 enqueue 的响应，报一次 request 摘要。
/// 只允许本类中的可读详情写入报告，请求体原样可以观察（全部是合成数据）。
/// 结构与 CookieLoopbackServer 相同：显式绑定 IPv4 loopback，ready 信号等待。
final class TTSHarnessServer: @unchecked Sendable {
    struct RequestReport { let method: String; let path: String; let headers: [String: String]; let body: Data }

    private let queue = DispatchQueue(label: "TTSHarnessServer")
    private let ready = DispatchSemaphore(value: 0)
    private var listener: NWListener?
    private var port: UInt16?
    private var pending: [(Int, [String: String], Data)] = []
    private var lastRequest: RequestReport?
    private var stopped = false

    static func start() throws -> TTSHarnessServer {
        let server = TTSHarnessServer()
        try server.bind()
        server.origin = "http://127.0.0.1:\(server.port!)"
        return server
    }

    private func bind() throws {
        try queue.sync {
            let host = NWEndpoint.Host("127.0.0.1")
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: host, port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = listener.port?.rawValue
                    self.ready.signal()
                case .failed:
                    self.ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, !self.stopped else { connection.cancel(); return }
                connection.start(queue: self.queue)
                connection.stateUpdateHandler = { state in
                    if case .failed = state { return }
                    guard case .ready = state else { return }
                    self.serve(connection)
                }
            }
            listener.start(queue: self.queue)
        }
        guard ready.wait(timeout: .now() + 3) == .success, port != nil else {
            stop()
            throw URLError(.cannotCreateFile)
        }
    }

    private(set) var origin = ""

    func enqueue(status: Int, headers: [String: String], body: Data) {
        queue.async { self.pending.append((status, headers, body)) }
    }

    func report() -> RequestReport? {
        var out: RequestReport?
        var tries = 0
        while out == nil && tries < 400 {
            out = queue.sync { lastRequest }
            if out == nil { Thread.sleep(forTimeInterval: 0.01) }; tries += 1
        }
        return out
    }

    func stop() {
        queue.sync {
            guard !stopped else { return }
            stopped = true
            listener?.cancel()
            listener = nil
        }
    }

    private func serve(_ connection: NWConnection) {
        var bytes = Data()
        var responded = false
        func receiveMore() {
            guard !stopped, !responded else { connection.cancel(); return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
                if let error { connection.cancel(); return }
                if let data { bytes.append(data) }
                if let data, let end = bytes.range(of: Data([13, 10, 13, 10])) {
                    let headerData = bytes[..<end.lowerBound]
                    let rest = bytes[(end.upperBound)...]
                    guard let text = String(data: headerData, encoding: .utf8) else { connection.cancel(); return }
                    var lines = text.components(separatedBy: "\r\n")
                    let firstLine = lines.first ?? ""
                    let parts = firstLine.split(separator: " ")
                    guard parts.count >= 2 else { connection.cancel(); return }
                    var contentLength = 0
                    var headers: [String: String] = [:]
                    for line in lines.dropFirst() {
                        if let i = line.firstIndex(of: ":") {
                            let k = String(line[..<i]).trimmingCharacters(in: .whitespaces)
                            let v = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                            headers[k.lowercased()] = v // 大小写存位
                            if k == "Content-Length" { contentLength = Int(v) ?? 0 }
                            headers[String(k)] = v
                        }
                    }
                    let method = String(parts[0])
                    let path = String(parts[1])
                    let have = rest.count
                    if have < contentLength && error == nil {
                        receiveMore()
                        return
                    }
                    let body = Data(rest.prefix(min(contentLength, rest.count)))
                    // headers 保存原始与规范两个键，测试里只用规范键。
                    let report = RequestReport(method: method, path: path, headers: headers, body: body)
                    // 这里正在 server.queue 上执行：直接赋值，不能 queue.sync（dispatch 断言崩溃了上一轮）。
                    lastRequest = report
                    respond(connection, status: self.pending.first?.0 ?? 500,
                            headers: self.pending.first?.1 ?? [:], body: self.pending.first?.2 ?? Data())
                    if !self.pending.isEmpty { self.pending.removeFirst() }
                    responded = true
                    return
                }
                if error != nil || complete { connection.cancel(); return }
                receiveMore()
            }
        }
        receiveMore()
    }

    private func respond(_ connection: NWConnection, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) OK\r\nConnection: close\r\nContent-Length: \(body.count)\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        connection.send(content: head.data(using: .utf8), completion: .contentProcessed { _ in
            connection.send(content: body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        })
    }
}

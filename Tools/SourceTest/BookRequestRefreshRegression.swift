import Foundation

/// Deterministic coverage for signed shelf-book recovery.  Every response is
/// supplied by URLProtocol; no fixture reaches a live service.
enum BookRequestRefreshRegression {
    private enum Reply {
        case response(Int, String)
        case failure(URLError)
        case delayed
    }

    private struct Observations {
        let search: Int
        let detail: Int
        let oldDetail: Int
        let freshDetail: Int
        let shapeOK: Bool
        let searchShapeOK: Bool
        let freshHeadersChanged: Bool
        let started: Bool
    }

    private final class Fixture {
        let searchBody: String
        let infoBody: String
        let expectedDetailURL: String?
        let initialStatus: Int
        let searchStatus: Int
        let retryStatus: Int
        let retryBody: String
        let oldHeaders: [String: String]
        let signedHeaders: [String]
        let searchMethod: String
        let searchHasBody: Bool
        let searchHeaders: [String]
        let offline: Bool
        let delayInitial: Bool

        private let lock = NSLock()
        private var searchCount = 0
        private var detailCount = 0
        private var oldDetailCount = 0
        private var freshDetailCount = 0
        private var shapeOK = true
        private var searchShapeOK = true
        private var freshHeadersChanged = false
        private var started = false

        init(searchBody: String = "{\"items\":[]}", infoBody: String = "{}",
             expectedDetailURL: String? = nil, initialStatus: Int = 401,
             searchStatus: Int = 200, retryStatus: Int = 200,
             retryBody: String? = nil, oldHeaders: [String: String] = [:],
             signedHeaders: [String] = [], offline: Bool = false,
             delayInitial: Bool = false, searchMethod: String = "GET",
             searchHasBody: Bool = false, searchHeaders: [String] = []) {
            self.searchBody = searchBody
            self.infoBody = infoBody
            self.expectedDetailURL = expectedDetailURL
            self.initialStatus = initialStatus
            self.searchStatus = searchStatus
            self.retryStatus = retryStatus
            self.retryBody = retryBody ?? infoBody
            self.oldHeaders = oldHeaders
            self.signedHeaders = signedHeaders
            self.searchMethod = searchMethod
            self.searchHasBody = searchHasBody
            self.searchHeaders = searchHeaders
            self.offline = offline
            self.delayInitial = delayInitial
        }

        func reply(for request: URLRequest) -> Reply {
            let path = request.url?.path.lowercased() ?? ""
            let isSearch = path.contains("search")
            lock.lock()
            if isSearch {
                searchCount += 1
                let hasBody = request.httpBody != nil || request.httpBodyStream != nil
                searchShapeOK = searchShapeOK && request.httpMethod?.uppercased() == searchMethod
                    && hasBody == searchHasBody
                    && searchHeaders.allSatisfy { request.value(forHTTPHeaderField: $0)?.isEmpty == false }
                let status = searchStatus
                let body = searchBody
                lock.unlock()
                return .response(status, body)
            }

            detailCount += 1
            let urlOK = expectedDetailURL == nil || request.url?.absoluteString == expectedDetailURL
            let methodOK = request.httpMethod?.uppercased() == "GET" && request.httpBody == nil
            shapeOK = shapeOK && urlOK && methodOK

            let values = signedHeaders.map { key in
                (key, request.value(forHTTPHeaderField: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
            let old = signedHeaders.isEmpty
                ? oldDetailCount == 0
                : values.allSatisfy { oldHeaders[$0.0] == $0.1 }
            let changed = !signedHeaders.isEmpty && values.contains { !$0.1.isEmpty && oldHeaders[$0.0] != $0.1 }
            let fresh = !old && (signedHeaders.isEmpty ? false : values.allSatisfy { !$0.1.isEmpty })
            if old { oldDetailCount += 1 }
            else if fresh {
                freshDetailCount += 1
                freshHeadersChanged = freshHeadersChanged || changed
            } else {
                shapeOK = false
            }
            let firstOld = old && oldDetailCount == 1
            let status = old ? initialStatus : retryStatus
            let body = old ? "{\"error\":\"fixture\"}" : retryBody
            let shouldDelay = firstOld && delayInitial
            if shouldDelay { started = true }
            lock.unlock()

            if offline && old { return .failure(URLError(.notConnectedToInternet)) }
            if shouldDelay { return .delayed }
            return .response(status, body)
        }

        func observations() -> Observations {
            lock.lock(); defer { lock.unlock() }
            return Observations(search: searchCount, detail: detailCount,
                                oldDetail: oldDetailCount, freshDetail: freshDetailCount,
                                shapeOK: shapeOK, searchShapeOK: searchShapeOK,
                                freshHeadersChanged: freshHeadersChanged, started: started)
        }
    }

    private final class Transport: URLProtocol {
        private static let lock = NSLock()
        private static var fixture: Fixture?

        static func install(_ fixture: Fixture) {
            lock.lock(); self.fixture = fixture; lock.unlock()
        }

        static func remove(_ fixture: Fixture) {
            lock.lock()
            if self.fixture === fixture { self.fixture = nil }
            lock.unlock()
        }

        private static func active() -> Fixture? {
            lock.lock(); defer { lock.unlock() }
            return fixture
        }

        override class func canInit(with request: URLRequest) -> Bool {
            let scheme = request.url?.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let fixture = Self.active(), let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            switch fixture.reply(for: request) {
            case .delayed:
                return
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            case .response(let status, let body):
                let response = HTTPURLResponse(url: url, statusCode: status,
                                               httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Transport.self]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static func perform(_ fixture: Fixture, source: BookSource, book: Book) async -> Result<Book, Error> {
        let session = makeSession()
        Transport.install(fixture)
        defer {
            session.invalidateAndCancel()
            Transport.remove(fixture)
        }
        do {
            return .success(try await WebBook.bookInfo(source: source, book: book, session: session))
        } catch {
            return .failure(error)
        }
    }

    private static func performCancellation(_ fixture: Fixture, source: BookSource, book: Book) async -> Result<Book, Error> {
        let session = makeSession()
        Transport.install(fixture)
        defer {
            session.invalidateAndCancel()
            Transport.remove(fixture)
        }
        let task = Task { () -> Result<Book, Error> in
            do {
                return .success(try await WebBook.bookInfo(source: source, book: book, session: session))
            } catch {
                return .failure(error)
            }
        }
        for _ in 0..<100 where !fixture.observations().started {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        task.cancel()
        return await task.value
    }

    private static func source(_ object: [String: Any]) throws -> BookSource {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(BookSource.self, from: data)
    }

    private static func syntheticSource(origin: String = "https://refresh.invalid/source",
                                        marker: String = "candidate") throws -> BookSource {
        let bookURLRule = """
        @js:(function() {
            java.put('candidateMarker', String(result.marker || ''));
            return 'https://refresh.invalid/detail?id=' + String(result.id) + '&edition=1,{"method":"GET","headers":{"X-Sign":"fresh"}}';
        })()
        """
        return try source([
            "bookSourceUrl": origin,
            "bookSourceName": "Request refresh fixture",
            "searchUrl": "https://refresh.invalid/search",
            "ruleSearch": [
                "bookList": "$.items[*]", "name": "$.name", "author": "$.author",
                "bookUrl": bookURLRule
            ],
            "ruleBookInfo": [
                "name": "$.name", "author": "$.author",
                "intro": "@js:java.get('candidateMarker')",
                "coverUrl": "$.cover", "tocUrl": "$.toc"
            ],
            "fixtureMarker": marker
        ])
    }

    private static func searchBody(_ items: [[String: Any]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["items": items])
        return String(decoding: data, as: UTF8.self)
    }

    private static func infoBody(name: String?, author: String?, cover: String? = nil) throws -> String {
        var object: [String: Any] = [:]
        if let name { object["name"] = name }
        if let author { object["author"] = author }
        if let cover { object["cover"] = cover }
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private static func signedURL(_ value: String = "old-sign") -> String {
        "https://refresh.invalid/detail?id=42&edition=1,{\"method\":\"GET\",\"headers\":{\"X-Sign\":\"\(value)\"}}"
    }

    private static func seededBook(source: BookSource, bookURL: String = signedURL()) -> Book {
        var book = Book(bookUrl: bookURL, name: "Target", origin: source.bookSourceUrl)
        book.author = "Writer"
        book.intro = "saved intro"
        book.kind = "saved kind"
        book.coverUrl = "https://covers.invalid/kept.png"
        book.lastChapter = "saved latest"
        book.wordCount = "900"
        book.tocUrl = "https://refresh.invalid/old-toc"
        book.originName = "Saved shelf source"
        book.durChapterIndex = 7
        book.durChapterPos = 1234
        book.durChapterTitle = "Saved chapter"
        book.addedAt = Date(timeIntervalSince1970: 1_234_567)
        book.lastReadAt = Date(timeIntervalSince1970: 1_234_890)
        return book
    }

    private static func replaceHeaders(_ raw: String, _ values: [String: String]) -> String? {
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let prefix = String(raw[..<comma])
        let optionsText = String(raw[raw.index(after: comma)...])
        guard let data = optionsText.data(using: .utf8),
              var options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var headers = options["headers"] as? [String: Any] else { return nil }
        for (key, value) in values { headers[key] = value }
        options["headers"] = headers
        guard let updated = try? JSONSerialization.data(withJSONObject: options),
              let text = String(data: updated, encoding: .utf8) else { return nil }
        return prefix + "," + text
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == URLError.cancelled.rawValue
    }

    private static func isHTTPFailure(_ error: Error, code: Int) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain && ns.code == URLError.badServerResponse.rawValue else { return false }
        let localized = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? ns.localizedDescription
        return localized.contains("\(code)")
            && !localized.contains("old-sign-value")
            && !localized.contains("synthetic-old")
            && !localized.contains("synthetic-info")
            && !localized.contains("1111111111")
    }

    private static func originalFieldsRemain(_ original: Book, _ refreshed: Book) -> Bool {
        refreshed.bookUrl == original.bookUrl
            && refreshed.origin == original.origin
            && refreshed.coverUrl == original.coverUrl
            && refreshed.durChapterIndex == original.durChapterIndex
            && refreshed.durChapterPos == original.durChapterPos
            && refreshed.durChapterTitle == original.durChapterTitle
            && refreshed.addedAt == original.addedAt
            && refreshed.lastReadAt == original.lastReadAt
    }

    static func run(_ check: (Bool, String) -> Void) async throws {
        try await syntheticRecovery(check)
        try await qimoRecovery(check)
        try eligibility(check)
    }

    private static func syntheticRecovery(_ check: (Bool, String) -> Void) async throws {
        let item: [String: Any] = ["id": "42", "name": "Target", "author": "Writer", "marker": "candidate"]
        let validInfo = try infoBody(name: "Target", author: "Writer")
        let validSearch = try searchBody([item])
        func freshSource() throws -> BookSource {
            var source = try syntheticSource(origin: "https://refresh.invalid/source#" + UUID().uuidString)
            source.ruleBookInfo?.kind = "@js:java.get('oldOnly')"
            return source
        }
        for status in [401, 403] {
            let source = try freshSource()
            let saved = seededBook(source: source)
            let book = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(saved))
            let original = RuleContext(source: source, book: book)
            _ = original.put("oldOnly", "kept-variable")
            _ = original.put("candidateMarker", "old-variable")
            let fixture = Fixture(searchBody: validSearch, infoBody: validInfo,
                expectedDetailURL: "https://refresh.invalid/detail?id=42&edition=1", initialStatus: status,
                oldHeaders: ["X-Sign": "old-sign"], signedHeaders: ["X-Sign"])
            let result = await perform(fixture, source: source, book: book)
            switch result {
            case .success(let updated):
                check(originalFieldsRemain(book, updated), "request renewal HTTP \(status): original shelf identity, cover, progress and dates retained")
                check(updated.intro == "candidate" && updated.kind == "kept-variable", "request renewal: fresh and old-only variables are available during parsing")
                check(original.get("candidateMarker") == "candidate", "request renewal: variables committed to original book only after success")
                let decoded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(updated))
                check(originalFieldsRemain(book, decoded), "request renewal: successful result survives Codable without identity migration")
            case .failure:
                check(false, "request renewal HTTP \(status): expected recovery")
            }
            let counts = fixture.observations()
            check(counts.search == 1 && counts.detail == 2 && counts.oldDetail == 1 && counts.freshDetail == 1,
                  "request renewal HTTP \(status): exactly one search and one new detail request")
            check(counts.shapeOK && counts.searchShapeOK && counts.freshHeadersChanged,
                  "request renewal: actual transport uses same endpoint with changed headers")
            var other = source; other.bookSourceUrl += "-other"
            check(RuleContext(source: other, book: book).get("candidateMarker").isEmpty, "request renewal: no cross-source variable publication")
        }

        var wrongID = item; wrongID["id"] = "43"
        var wrongName = item; wrongName["name"] = "Other"
        var wrongAuthor = item; wrongAuthor["author"] = "Other"
        let rejected: [(String, [[String: Any]])] = [
            ("different ID", [wrongID]), ("different name", [wrongName]),
            ("different author", [wrongAuthor]), ("duplicate candidate", [item, item]), ("empty results", [])
        ]
        for (label, items) in rejected {
            let source = try freshSource()
            let book = seededBook(source: source)
            let original = RuleContext(source: source, book: book)
            _ = original.put("candidateMarker", "unchanged")
            let fixture = Fixture(searchBody: try searchBody(items), infoBody: validInfo,
                oldHeaders: ["X-Sign": "old-sign"], signedHeaders: ["X-Sign"])
            switch await perform(fixture, source: source, book: book) {
            case .success: check(false, "request renewal rejects \(label)")
            case .failure(let error): check(isHTTPFailure(error, code: 401), "request renewal rejects \(label) with original HTTP status")
            }
            let counts = fixture.observations()
            check(counts.search == 1 && counts.detail == 1, "request renewal \(label): never requests another book")
            check(original.get("candidateMarker") == "unchanged", "request renewal \(label): original variables unchanged")
        }
        for status in [404, 429, 500, 503] {
            let source = try freshSource()
            let book = seededBook(source: source)
            let fixture = Fixture(searchBody: validSearch, infoBody: validInfo, initialStatus: status,
                oldHeaders: ["X-Sign": "old-sign"], signedHeaders: ["X-Sign"])
            switch await perform(fixture, source: source, book: book) {
            case .success: check(false, "request renewal HTTP \(status) must remain failure")
            case .failure(let error): check(isHTTPFailure(error, code: status), "request renewal reports actual HTTP \(status) without headers")
            }
            check(fixture.observations().search == 0 && fixture.observations().detail == 1,
                  "request renewal HTTP \(status): no additional search or detail retry")
        }
        for (searchStatus, retryStatus, expectedStatus, expectedDetails) in [(500, 200, 500, 1), (200, 403, 403, 2)] {
            let source = try freshSource()
            let book = seededBook(source: source)
            let fixture = Fixture(searchBody: validSearch, infoBody: validInfo,
                searchStatus: searchStatus, retryStatus: retryStatus,
                oldHeaders: ["X-Sign": "old-sign"], signedHeaders: ["X-Sign"])
            switch await perform(fixture, source: source, book: book) {
            case .success: check(false, "request renewal must report recovery-stage failure")
            case .failure(let error): check(isHTTPFailure(error, code: expectedStatus), "request renewal reports actual failed stage HTTP status")
            }
            check(fixture.observations().search == 1 && fixture.observations().detail == expectedDetails,
                  "request renewal failure never loops")
        }
        for body in ["", "{}", "{\"error\":\"expired\"}", try infoBody(name: "Other", author: "Writer")] {
            let source = try freshSource()
            let book = seededBook(source: source)
            let original = RuleContext(source: source, book: book)
            _ = original.put("candidateMarker", "original")
            let fixture = Fixture(searchBody: validSearch, infoBody: validInfo, retryBody: body,
                oldHeaders: ["X-Sign": "old-sign"], signedHeaders: ["X-Sign"])
            switch await perform(fixture, source: source, book: book) {
            case .success: check(false, "request renewal must not accept empty/wrong HTTP 200 metadata")
            case .failure(let error):
                check((error as? URLError)?.code == .cannotParseResponse, "request renewal validates extracted identity, not saved fallback fields")
            }
            check(original.get("candidateMarker") == "original", "request renewal invalid details do not commit pending candidate variables")
            check(fixture.observations().search == 1 && fixture.observations().detail == 2, "request renewal invalid details stop after one retry")
        }
        let source = try freshSource()
        let plain = seededBook(source: source, bookURL: "https://refresh.invalid/detail?id=42&edition=1")
        let plainFixture = Fixture(searchBody: validSearch, infoBody: validInfo)
        if case .failure(let error) = await perform(plainFixture, source: source, book: plain) {
            check(isHTTPFailure(error, code: 401), "plain detail still reports authentication error")
        } else { check(false, "plain detail cannot silently recover") }
        check(plainFixture.observations().search == 0, "plain detail without saved options never triggers renewal")
        let saved = seededBook(source: source)
        let offline = Fixture(offline: true)
        if case .failure(let error) = await perform(offline, source: source, book: saved) {
            check((error as? URLError)?.code == .notConnectedToInternet, "request renewal propagates transport failure")
        } else { check(false, "offline detail must fail") }
        check(offline.observations().search == 0, "offline request does not re-search")
        let cancelled = Fixture(delayInitial: true)
        if case .failure(let error) = await performCancellation(cancelled, source: source, book: saved) {
            check(isCancellation(error), "request renewal cancellation remains cancellation")
        } else { check(false, "cancelled detail must not succeed") }
        check(cancelled.observations().search == 0, "cancelled detail cannot start recovery")
    }

    private static func qimoRecovery(_ check: (Bool, String) -> Void) async throws {
        var source = try QimoSourceRegression.loadFixture()
        source.bookSourceUrl += "#request-renewal-" + UUID().uuidString
        let searchJSON = #"{"Data":{"CardList":[{"Body":[{"ItemType":0,"ItemData":{"BookId":1043123456,"BookName":"Target","AuthorName":"Writer"}}]}]}}"#
        let searchURL = "https://druidv6.if.qidian.com/argus/api/v2/booksearch/searchbooks"
        let found = WebBook.parseBookList(source: source, body: searchJSON, baseUrl: searchURL, rule: source.ruleSearch!)
        check(found.count == 1, "Qimo renewal uses the real search rule")
        guard var book = found.first else { return }
        let old = ["QDSign": "synthetic-old", "QDInfo": "synthetic-info", "tstamp": "1111111111"]
        guard let signed = replaceHeaders(book.bookUrl, old) else {
            check(false, "Qimo renewal fixture requires generated header options"); return
        }
        book.bookUrl = signed
        book.durChapterIndex = 7; book.durChapterPos = 123
        book.durChapterTitle = "Saved chapter"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("bookshelf.json")
        try JSONEncoder().encode([book]).write(to: file, options: .atomic)
        let restored = try JSONDecoder().decode([Book].self, from: Data(contentsOf: file))[0]
        let replay = AnalyzeUrl(rawUrl: restored.bookUrl, baseUrl: source.bookSourceUrl,
            sourceHeader: source.header, context: RuleContext(source: source, book: restored), jsLib: source.jsLib)
        check(old.allSatisfy { replay.headers[$0.key] == $0.value }, "Qimo old shelf headers replay unchanged without renewal")
        let detailJSON = #"{"Status":0,"Data":{"BookId":1043123456,"BookName":"Target","Author":"Writer","Description":"renewed","FreshManSimple":{"IsInBlackList":0},"WordsCnt":100}}"#
        for status in [401, 403] {
            let fixture = Fixture(searchBody: searchJSON, infoBody: detailJSON,
                expectedDetailURL: replay.url, initialStatus: status, oldHeaders: old,
                signedHeaders: ["QDSign", "QDInfo", "tstamp"], searchMethod: "POST",
                searchHasBody: true, searchHeaders: ["QDSign", "QDInfo", "tstamp"])
            switch await perform(fixture, source: source, book: restored) {
            case .success(let result):
                check(originalFieldsRemain(restored, result), "Qimo renewal HTTP \(status): original shelf ID, cover and progress preserved")
                check(result.intro == "renewed" && result.tocUrl?.contains("chapterlist") == true,
                      "Qimo renewal actually parses new details and catalog request")
            case .failure:
                check(false, "Qimo renewal HTTP \(status): expected production-rule recovery")
            }
            let observed = fixture.observations()
            check(observed.search == 1 && observed.oldDetail == 1 && observed.freshDetail == 1,
                  "Qimo renewal HTTP \(status): exactly one search and one fresh detail")
            check(observed.shapeOK && observed.searchShapeOK && observed.freshHeadersChanged,
                  "Qimo renewal recomputes headers using real signers, preserving method and book endpoint")
        }
    }

    private static func eligibility(_ check: (Bool, String) -> Void) throws {
        let source = try syntheticSource()
        let saved = seededBook(source: source)
        func request(_ book: Book) -> AnalyzeUrl {
            AnalyzeUrl(rawUrl: book.bookUrl, baseUrl: source.bookSourceUrl,
                       sourceHeader: source.header, context: RuleContext(source: source, book: book))
        }
        let original = request(saved)
        check(BookInfoRequestRefresh.canRefresh(source: source, book: saved, request: original), "saved literal signed GET qualifies for renewal")
        for raw in ["https://refresh.invalid/detail", "https://refresh.invalid/detail,{'headers':{'X-Sign':'old'}}",
                    "https://refresh.invalid/detail,{\"headers\":{}}", "https://refresh.invalid/{{id}},{\"headers\":{\"X\":\"y\"}}"] {
            check(!BookInfoRequestRefresh.hasSavedHeaders(raw), "renewal eligibility rejects plain/loose/empty/dynamic options conservatively")
        }
        var changed = saved
        changed.origin += "#other"
        check(!BookInfoRequestRefresh.canRefresh(source: source, book: changed, request: original), "renewal eligibility rejects another source")
        changed = saved; changed.author = ""
        check(!BookInfoRequestRefresh.canRefresh(source: source, book: changed, request: original), "renewal eligibility requires author identity")
        for key in ["method", "body", "webView", "query", "source", "name", "author"] {
            var candidate = saved
            var candidateRequest = original
            switch key {
            case "method": candidateRequest.method = "POST"
            case "body": candidateRequest.body = "x=1"
            case "webView": candidateRequest.webView = true
            case "query": candidateRequest.url += "&different=1"
            case "source": candidate.origin += "#other"
            case "name": candidate.name = "Other"
            default: candidate.author = "Other"
            }
            check(!BookInfoRequestRefresh.matches(candidate, saved: saved, request: candidateRequest, savedRequest: original),
                  "renewal identity rejects changed \(key)")
        }
        check(!BookInfoRequestRefresh.headersChanged(original, from: original), "unchanged headers cannot trigger pointless retry")
    }
}

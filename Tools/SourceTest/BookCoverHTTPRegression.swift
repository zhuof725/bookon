import Foundation

/// Uses the real request -> response -> bookInfo path; never contacts a site.
enum BookCoverHTTPRegression {
    private final class Transport: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "cover-http.invalid"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            if url.lastPathComponent == "offline" {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let status = Int(url.lastPathComponent) ?? 200
            // Even error responses can have superficially valid image metadata.
            let body = Data(#"{"Data":{"BookId":1043123457,"BookName":"HTTP fixture"}}"#.utf8)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static func run(_ check: (Bool, String) -> Void) async throws {
        let raw = #"{"bookSourceUrl":"https://cover-http.invalid","bookSourceName":"Offline cover fixture","ruleBookInfo":{"name":"$.Data.BookName","coverUrl":"https://covers.invalid/{{$.Data.BookId}}.png"}}"#
        let source = try JSONDecoder().decode(BookSource.self, from: Data(raw.utf8))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Transport.self]
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for code in [200, 401, 404, 500] {
            let saved = Book(bookUrl: "https://cover-http.invalid/\(code)", name: "Saved book",
                             coverUrl: "https://covers.invalid/1043123456.png", origin: source.bookSourceUrl)
            do {
                let info = try await WebBook.bookInfo(source: source, book: saved, session: session)
                check(code == 200, "cover HTTP \(code): errors do not parse/overwrite metadata")
                check(info.coverUrl == "https://covers.invalid/1043123457.png", "cover HTTP 200: valid new cover updates")
            } catch let error as URLError {
                check(code != 200 && error.code == .badServerResponse, "cover HTTP \(code): reports badServerResponse")
                check(saved.coverUrl == "https://covers.invalid/1043123456.png", "cover HTTP \(code): saved cover unchanged")
            } catch { check(false, "cover HTTP \(code): unexpected error") }
        }
        let offline = Book(bookUrl: "https://cover-http.invalid/offline", name: "Offline",
                           coverUrl: "https://covers.invalid/kept.png", origin: source.bookSourceUrl)
        do {
            _ = try await WebBook.bookInfo(source: source, book: offline, session: session)
            check(false, "cover offline must throw")
        } catch let error as URLError {
            check(error.code == .notConnectedToInternet && offline.coverUrl == "https://covers.invalid/kept.png",
                  "cover offline: transport failure preserves prior book")
        }
    }
}

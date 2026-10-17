import SwiftUI
import Network

/// 音频书测试台的本机回环音频服务器：为三个章节提供打包的静音 m4a，
/// 支持 Range 请求（AVPlayer 的流式播放前提）。只在测试 App 中使用，不访问外网。
final class AudioFixtureServer {
    static let shared = AudioFixtureServer()

    private let queue = DispatchQueue(label: "io.legado.audio-fixture-server")
    private var listener: NWListener?
    private var payloads: [String: Data] = [:]
    /// 监听就绪后的基地址（http://127.0.0.1:<port>）；主线程读取。
    private(set) var baseURL: URL?

    private init() {}

    func start() {
        guard listener == nil else { return }
        guard let directory = Bundle.main
            .url(forResource: "ch0", withExtension: "m4a", subdirectory: "audio")?
            .deletingLastPathComponent() else { return }
        for name in ["ch0", "ch1", "ch2"] {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("\(name).m4a")) {
                payloads["/\(name).m4a"] = data
            }
        }
        guard !payloads.isEmpty else { return }
        do {
            let listener = try NWListener(using: .tcp)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .ready = state, let port = self?.listener?.port?.rawValue else { return }
                let url = URL(string: "http://127.0.0.1:\(port)")
                DispatchQueue.main.async { self?.baseURL = url }
            }
            listener.start(queue: queue)
        } catch {
            listener = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) == nil, !isComplete, error == nil, buffer.count < 64 * 1024 {
                self.receiveRequest(connection, buffer: buffer)
                return
            }
            self.respond(to: connection, request: buffer)
        }
    }

    private func respond(to connection: NWConnection, request: Data) {
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        let path = requestLine.count >= 2 ? requestLine[1] : "/"
        var rangeStart: Int?
        var rangeEnd: Int?
        for line in lines where line.lowercased().hasPrefix("range:") {
            let raw = line.components(separatedBy: ":").dropFirst().joined(separator: ":")
            let value = raw.replacingOccurrences(of: "bytes=", with: "")
                .trimmingCharacters(in: .whitespaces)
            let parts = value.components(separatedBy: "-")
            rangeStart = parts.first.flatMap(Int.init)
            if parts.count > 1 { rangeEnd = Int(parts[1]) }
        }
        guard let payload = payloads[path] else {
            send(connection, header: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", body: Data())
            return
        }
        let total = payload.count
        if rangeStart != nil || rangeEnd != nil {
            let start = min(max(rangeStart ?? 0, 0), total - 1)
            let end = min(max(rangeEnd ?? (total - 1), start), total - 1)
            let slice = payload.subdata(in: start..<(end + 1))
            let header = "HTTP/1.1 206 Partial Content\r\nContent-Type: audio/mp4\r\n"
                + "Content-Length: \(slice.count)\r\nContent-Range: bytes \(start)-\(end)/\(total)\r\n"
                + "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n"
            send(connection, header: header, body: slice)
        } else {
            let header = "HTTP/1.1 200 OK\r\nContent-Type: audio/mp4\r\n"
                + "Content-Length: \(total)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
            send(connection, header: header, body: payload)
        }
    }

    private func send(_ connection: NWConnection, header: String, body: Data) {
        var data = Data(header.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// 音频书播放测试台：真实 BookAudioPlayer + 本机回环音频源，验证
/// 起播、下一章预载入队、点「下一章」走队列快路径、章末自动连播与停止清理。
struct AudioHarnessView: View {
    @StateObject private var player = BookAudioPlayer()
    @State private var readerIndex = 0
    @State private var adoptedLog: [String] = []
    @State private var via = "none"
    @State private var serverState = "waiting"
    @State private var booted = false

    private static let titles = ["第1章 测试起点", "第2章 测试续章", "第3章 测试收束"]

    var body: some View {
        VStack(spacing: 14) {
            Text("audio-harness").font(.footnote)
            Text(stateText)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("audio.state")
            HStack(spacing: 8) {
                Button("播放第一章") { playChapter(0) }
                    .accessibilityIdentifier("audio.start")
                Button("下一章") { nextChapter() }
                    .accessibilityIdentifier("audio.next")
                Button("暂停/继续") { player.toggle() }
                    .accessibilityIdentifier("audio.toggle")
                Button("停止") { player.stop() }
                    .accessibilityIdentifier("audio.stop")
            }
            .font(.system(size: 13))
        }
        .padding()
        .onAppear(perform: boot)
    }

    private var stateText: String {
        "server=\(serverState);chapter=\(player.chapterIndex)"
            + ";queued=\(player.queuedChapterIndex.map(String.init) ?? "nil")"
            + ";playing=\(player.isPlaying);buffering=\(player.isBuffering)"
            + ";reader=\(readerIndex);via=\(via)"
            + ";adopted=\(adoptedLog.joined(separator: "+"));time=\(Int(player.currentTime))"
    }

    /// 与阅读器一致的最小接线：预载来源、自动接管回调与「下一章」快路径。
    private func boot() {
        guard !booted else { return }
        booted = true
        AudioFixtureServer.shared.start()
        player.onChapterChanged = { newIndex in
            readerIndex = newIndex
            adoptedLog.append(String(newIndex))
        }
        player.onFinish = { adoptedLog.append("finish") }
        player.nextChapterProvider = { current in
            guard let base = AudioFixtureServer.shared.baseURL,
                  current + 1 < Self.titles.count else { return nil }
            return BookAudioPlayer.NextChapter(
                index: current + 1,
                url: base.appendingPathComponent("ch\(current + 1).m4a").absoluteString,
                title: Self.titles[current + 1])
        }
        Task { @MainActor in
            var waited = 0
            while AudioFixtureServer.shared.baseURL == nil, waited < 100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                waited += 1
            }
            guard AudioFixtureServer.shared.baseURL != nil else {
                serverState = "failed"
                return
            }
            serverState = "ready"
            playChapter(0)
        }
    }

    private func playChapter(_ index: Int) {
        guard let base = AudioFixtureServer.shared.baseURL,
              Self.titles.indices.contains(index) else { return }
        player.play(chapterIndex: index,
                    url: base.appendingPathComponent("ch\(index).m4a").absoluteString,
                    title: Self.titles[index], album: "测试音频书")
    }

    private func nextChapter() {
        let next = readerIndex + 1
        guard next < Self.titles.count else { return }
        if player.advanceToQueued(chapterIndex: next) {
            via = "queue"
        } else {
            via = "load"
            playChapter(next)
        }
    }
}

import SwiftUI

/// 分享导入排查用：记录 AppDelegate / onOpenURL / Inbox 扫描收到什么。
/// 只写本机 Documents/ImportDiagnostics.log，可在「我的 → 本机数据」里看。
@MainActor
final class ImportDiagnostics: ObservableObject {
    static let shared = ImportDiagnostics()
    @Published private(set) var lines: [String] = []

    private let fileURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("ImportDiagnostics.log")
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            lines = text.split(separator: "\n").suffix(200).map(String.init)
        }
    }

    func note(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        lines.append("\(formatter.string(from: Date())) \(text)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func clear() {
        lines.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    var inboxFiles: [String] {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "-"
            return "\(url.lastPathComponent)  \(date)"
        }
    }
}

struct ImportDiagnosticsView: View {
    @ObservedObject private var diagnostics = ImportDiagnostics.shared
    @State private var inbox: [String] = []

    var body: some View {
        List {
            Section("收件箱 Documents/Inbox") {
                if inbox.isEmpty {
                    Text("没有文件").foregroundStyle(.secondary)
                } else {
                    ForEach(inbox, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
                Button("刷新") { inbox = diagnostics.inboxFiles }
            }
            Section("事件") {
                if diagnostics.lines.isEmpty {
                    Text("还没有收到分享文件").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(diagnostics.lines.reversed()), id: \.self) { line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
                Button("清空日志", role: .destructive) { diagnostics.clear() }
            }
        }
        .navigationTitle("分享导入诊断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inbox = diagnostics.inboxFiles }
    }
}

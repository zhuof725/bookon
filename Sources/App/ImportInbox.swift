import UIKit
import Combine

/// 系统把分享/文件打开的 URL 交给 AppDelegate；先放进收件箱，
/// 等 SwiftUI 根视图出现后再处理，避免冷启动时 onOpenURL 丢事件。
@MainActor
final class ImportInbox: ObservableObject {
    static let shared = ImportInbox()
    @Published var pendingFile: URL?

    private init() {}

    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        ImportDiagnostics.shared.note("收件箱收到 \(url.lastPathComponent)")
        pendingFile = url
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.isFileURL {
            ImportDiagnostics.shared.note("AppDelegate open \(url.lastPathComponent)")
            ImportInbox.shared.receive(url)
            return true
        }
        return false
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if let url = launchOptions?[.url] as? URL, url.isFileURL {
            ImportDiagnostics.shared.note("didFinishLaunching \(url.lastPathComponent)")
            ImportInbox.shared.receive(url)
        }
        return true
    }
}

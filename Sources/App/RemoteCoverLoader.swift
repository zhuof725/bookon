import SwiftUI
import UIKit

/// 带 coverDecodeJs 的书源封面：下载原始字节 → 执行脚本 → 解码图片。
/// 没有解密规则的书源继续走 AsyncImage，不改变原有加载路径。
@MainActor
final class RemoteCoverLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false
    private var generation = UUID()
    private static let cache = NSCache<NSString, UIImage>()

    func load(_ url: URL?, sourceKey: String?, pixelSize: Int) async {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let source = sourceKey.flatMap { AppStore.shared.source(for: $0) }
        guard let source, let script = source.coverDecodeJs, !script.isEmpty else { return }
        let key = "\(url.absoluteString)|\(script.hashValue)|\(pixelSize)" as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached; didFail = false
            return
        }
        let token = UUID()
        generation = token
        do {
            let request = AnalyzeUrl(rawUrl: url.absoluteString, sourceHeader: source.header,
                                     context: RuleContext(source: source), jsLib: source.jsLib)
            let (data, _, _) = try await request.fetchData()
            try Task.checkCancellation()
            let decoded = SourceImageDecoder.decode(data, src: url.absoluteString, source: source)
            guard let ui = UIImage(data: decoded) else {
                throw NSError(domain: "RemoteCoverLoader", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "解密后的封面不是图片"])
            }
            guard !Task.isCancelled, generation == token else { return }
            Self.cache.setObject(ui, forKey: key, cost: Int(ui.size.width * ui.size.height))
            image = ui
            didFail = false
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            DebugLog.add("◇封面解密加载失败：\(error.localizedDescription)")
            image = nil
            didFail = true
        }
    }
}

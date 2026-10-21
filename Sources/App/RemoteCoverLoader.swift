import SwiftUI
import UIKit

/// 带 coverDecodeJs 的书源封面：下载原始字节 → 执行脚本 → 解码图片。
/// 没有解密规则的书源继续走 AsyncImage，不改变原有加载路径。
/// 通过 `CoverDecodeRuntime` 注入，使 BookCoverImage 不直接依赖 AppStore/引擎（测试工程不含这些文件）。
enum RemoteCoverLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func install() {
        CoverDecodeRuntime.needsDecode = { origin in
            guard let source = AppStore.shared.source(for: origin) else { return false }
            return !(source.coverDecodeJs?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        CoverDecodeRuntime.load = { url, origin, pixelSize in
            await load(url: url, origin: origin, pixelSize: pixelSize)
        }
    }

    private static func load(url: URL, origin: String, pixelSize: Int) async -> UIImage? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let source = AppStore.shared.source(for: origin),
              let script = source.coverDecodeJs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !script.isEmpty else { return nil }
        let key = "\(url.absoluteString)|\(script.hashValue)|\(pixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        do {
            let request = AnalyzeUrl(rawUrl: url.absoluteString, sourceHeader: source.header,
                                     context: RuleContext(source: source), jsLib: source.jsLib)
            let (data, _, _) = try await request.fetchData()
            try Task.checkCancellation()
            let decoded = SourceImageDecoder.decode(data, src: url.absoluteString, source: source)
            guard let image = UIImage(data: decoded) else {
                DebugLog.add("◇封面解密后的数据不是图片")
                return nil
            }
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height))
            return image
        } catch {
            if !Task.isCancelled {
                DebugLog.add("◇封面解密加载失败：\(error.localizedDescription)")
            }
            return nil
        }
    }
}

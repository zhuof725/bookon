import SwiftUI
import UIKit

/// 带 coverDecodeJs 的书源封面：下载原始字节 → 执行脚本 → 解码图片。
/// 没有解密规则的书源改走「带书源请求头的普通下载」（图床常校验 Referer）。
/// 两种方式都会把结果落到本机缓存（CoverDiskCache），换网络/开 VPN 也显示得出来。
/// 通过 `CoverDecodeRuntime` 注入，使 BookCoverImage 不直接依赖 AppStore/引擎（测试工程不含这些文件）。
enum RemoteCoverLoader {
    /// 内存缓存存「解密后的图片字节」，命中时不用重新编码。
    private static let cache = NSCache<NSString, NSData>()

    static func install() {
        CoverDecodeRuntime.needsDecode = { origin in
            await MainActor.run {
                guard let source = AppStore.shared.source(for: origin) else { return false }
                return !(source.coverDecodeJs?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
        }
        CoverDecodeRuntime.load = { url, origin in
            await loadDecoded(url: url, origin: origin)
        }
        CoverDecodeRuntime.loadPlain = { url, origin in
            await loadPlain(url: url, origin: origin)
        }
    }

    /// 解密书源：下载原始字节 → 脚本解密 → 落盘。
    private static func loadDecoded(url: URL, origin: String) async -> Data? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let source = await MainActor.run { AppStore.shared.source(for: origin) }
        guard let source,
              let script = source.coverDecodeJs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !script.isEmpty else { return nil }
        let key = "\(url.absoluteString)|\(script.hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
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
            cache.setObject(decoded as NSData, forKey: key, cost: decoded.count)
            // 解密后的字节才是能显示的图，缓存里存它。
            CoverDiskCache.store(decoded, for: url)
            return decoded
        } catch {
            if !Task.isCancelled {
                DebugLog.add("◇封面解密加载失败：\(error.localizedDescription)")
            }
            return nil
        }
    }

    /// 普通封面：带书源请求头下载（聚合站/图床常校验 Referer、UA），落盘后返回字节。
    private static func loadPlain(url: URL, origin: String) async -> Data? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let source = await MainActor.run { AppStore.shared.source(for: origin) }
        guard let source else { return nil }
        do {
            let request = AnalyzeUrl(rawUrl: url.absoluteString, sourceHeader: source.header,
                                     context: RuleContext(source: source), jsLib: source.jsLib)
            let (data, _, _) = try await request.fetchData()
            try Task.checkCancellation()
            guard !data.isEmpty else { return nil }
            CoverDiskCache.store(data, for: url)
            return data
        } catch {
            if !Task.isCancelled {
                DebugLog.add("◇封面加载失败：\(error.localizedDescription)")
            }
            return nil
        }
    }
}

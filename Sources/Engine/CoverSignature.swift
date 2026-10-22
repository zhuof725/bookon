import Foundation

/// 番茄系封面地址带签名：`x-expires`（过期时刻，Unix 秒）+ `x-signature`。
/// 过期后就是 403 的死链 —— CDN 会回 `es-exit: x_signature auth failed`。
/// 番茄的发现页（首页/分类）给的封面签名只有几天有效期，
/// 所以「缓存里的书」不能放得比封面签名更久，否则封面白屏。
enum CoverSignature {
    /// 地址里的 x-expires 对应的过期时刻；不是签名地址返回 nil。
    static func expiry(of urlString: String) -> Date? {
        guard let comps = URLComponents(string: urlString), let items = comps.queryItems else { return nil }
        guard let raw = items.first(where: { $0.name == "x-expires" })?.value,
              let seconds = Double(raw), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 一批书里最早的封面过期时刻；没有签名地址返回 nil。
    static func earliestExpiry(of books: [Book]) -> Date? {
        var earliest: Date?
        for book in books {
            guard let raw = book.coverUrl, let date = expiry(of: raw) else { continue }
            if earliest == nil || date < earliest! { earliest = date }
        }
        return earliest
    }

    /// 这个地址是否已经过期（签名地址且过期时刻已过）。
    static func isExpired(_ urlString: String, now: Date = Date()) -> Bool {
        guard let date = expiry(of: urlString) else { return false }
        return date <= now
    }
}
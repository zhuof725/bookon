import Foundation

/// 发现页封面签名回归。
///
/// 番茄系的封面地址带签名（x-expires + x-signature），过期后 CDN 直接回 403
/// （`es-exit: x_signature auth failed`）。发现页的板块数据会被缓存，
/// 缓存有效期一旦超过封面签名，缓存里的书就全是白屏的封面。
enum CoverSignatureRegression {
    private static func book(_ cover: String) -> Book {
        Book(bookUrl: "https://b.invalid/1", name: "书", origin: "s", coverUrl: cover)
    }

    static func run(_ check: (Bool, String) -> Void) {
        let signed = "https://p3-fanqiesdk-sign.fanqiesdkpic.com/novel-pic/abc~tplv-resize:225:0.image"
            + "?lk3s=6dbdd468&x-expires=1793247828&x-signature=Ep3d3F%2BJwG6dIL0m5MeLgw3ko0o%3D"
        let plain = "https://example.invalid/cover.jpg"

        let expiry = CoverSignature.expiry(of: signed)
        check(expiry != nil, "封面签名：解析出 x-expires")
        check(expiry.map { abs($0.timeIntervalSince1970 - 1793247828) < 1 } == true,
              "封面签名：过期时刻与地址里的一致")
        check(CoverSignature.expiry(of: plain) == nil, "封面签名：普通地址没有过期时刻")
        check(CoverSignature.isExpired(signed, now: Date(timeIntervalSince1970: 1793247829)),
              "封面签名：过了 x-expires 就算过期")
        check(!CoverSignature.isExpired(signed, now: Date(timeIntervalSince1970: 1793247827)),
              "封面签名：还没到 x-expires 不算过期")
        check(!CoverSignature.isExpired(plain), "封面签名：普通地址永不过期")

        // 缓存有效期不能超过封面签名
        let now = Date(timeIntervalSince1970: 1792643065)
        let books = [book(signed), book(plain)]
        let ttl = DiscoverBlockCache.validInterval(books: books, now: now)
        let untilExpiry = 1793247828 - 1792643065
        check(ttl <= untilExpiry, "发现缓存：有效期不超过封面签名（实际 \(Int(ttl))s，签名还有 \(untilExpiry)s）")
        check(ttl > 0, "发现缓存：签名还有效时缓存仍然可用")
        // 签名已经过了 → 缓存直接作废（否则就是一堆 403 的封面）
        let after = Date(timeIntervalSince1970: 1793247829)
        check(DiscoverBlockCache.validInterval(books: books, now: after) <= 0,
              "发现缓存：封面签名过期后缓存立即失效")
    }
}

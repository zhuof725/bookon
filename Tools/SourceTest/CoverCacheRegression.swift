import Foundation

/// 封面本地缓存回归（纯离线，不发网络请求）：
/// 键的稳定性、写入/读回、空数据与超大数据不落盘、清空缓存。
enum CoverCacheRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let urlA = URL(string: "https://cdn.example.invalid/a/cover.jpg")!
        let urlB = URL(string: "https://cdn.example.invalid/b/cover.jpg")!

        // 同一个地址永远映射到同一个文件；不同地址不同文件。
        check(CoverDiskCache.fileURL(for: urlA) == CoverDiskCache.fileURL(for: urlA),
              "封面缓存：同一地址的缓存路径稳定")
        check(CoverDiskCache.fileURL(for: urlA) != CoverDiskCache.fileURL(for: urlB),
              "封面缓存：不同地址的缓存路径不同")
        check(CoverDiskCache.fileURL(for: urlA).pathExtension == "img",
              "封面缓存：缓存文件是 .img")

        // 写入 → 读回内容一致。
        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
        CoverDiskCache.store(payload, for: urlA)
        check(CoverDiskCache.data(for: urlA) == payload, "封面缓存：写入后能读回同样的字节")
        check(CoverDiskCache.diskBytes() > 0, "封面缓存：占用空间可统计")

        // 空数据不落盘。
        CoverDiskCache.store(Data(), for: urlB)
        check(CoverDiskCache.data(for: urlB) == nil, "封面缓存：空数据不写盘")

        // 超大数据不落盘（免得个别大图撑爆缓存）。
        let huge = Data(repeating: 0, count: CoverDiskCache.maxCoverBytes + 1)
        CoverDiskCache.store(huge, for: urlB)
        check(CoverDiskCache.data(for: urlB) == nil, "封面缓存：超过上限的封面不写盘")

        // 清空。
        CoverDiskCache.removeAll()
        check(CoverDiskCache.data(for: urlA) == nil, "封面缓存：清空后读不到")
        check(CoverDiskCache.diskBytes() == 0, "封面缓存：清空后占用为 0")
    }
}

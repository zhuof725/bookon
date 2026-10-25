import Foundation

/// 漫画图片 / 有声书音频磁盘缓存回归（纯离线）。
/// 对应原版 BookHelp.saveImage（图片落盘）与 ExoPlayer SimpleCache（音频落盘）。
enum MediaCacheRegression {
    static func run(_ check: (Bool, String) -> Void) {
        // 漫画图片：同一地址路径稳定、扩展名跟着地址走。
        let imageA = "https://img.example.invalid/p/1.webp?sign=abc"
        let imageB = "https://img.example.invalid/p/2.jpg"
        check(MangaImageDiskCache.fileURL(for: imageA) == MangaImageDiskCache.fileURL(for: imageA),
              "漫画缓存：同一地址路径稳定")
        check(MangaImageDiskCache.fileURL(for: imageA) != MangaImageDiskCache.fileURL(for: imageB),
              "漫画缓存：不同地址路径不同")
        check(MangaImageDiskCache.fileURL(for: imageA).pathExtension == "webp",
              "漫画缓存：扩展名按地址后缀")

        let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
        MangaImageDiskCache.store(imageBytes, for: imageA)
        check(MangaImageDiskCache.data(for: imageA) == imageBytes, "漫画缓存：写入后能读回")
        MangaImageDiskCache.store(Data(), for: imageB)
        check(MangaImageDiskCache.data(for: imageB) == nil, "漫画缓存：空数据不写盘")
        MangaImageDiskCache.store(Data(repeating: 0, count: MangaImageDiskCache.maxImageBytes + 1),
                                  for: imageB)
        check(MangaImageDiskCache.data(for: imageB) == nil, "漫画缓存：超过上限的不写盘")

        // 有声书音频。
        let audioA = "https://cdn.example.invalid/a/ch1.m4a?sign=1"
        let audioB = "https://cdn.example.invalid/a/ch2.m4a"
        check(AudioDiskCache.cachedFile(for: audioA) == nil, "音频缓存：未下载时没有缓存")
        let audioBytes = Data(repeating: 7, count: 1024)
        AudioDiskCache.store(audioBytes, for: audioA, ext: "mp3")
        check(AudioDiskCache.cachedFile(for: audioA) != nil, "音频缓存：缓存后能找到文件")
        check(AudioDiskCache.cachedFile(for: audioB) == nil, "音频缓存：不同地址互不影响")
        AudioDiskCache.store(Data(), for: audioB, ext: "mp3")
        check(AudioDiskCache.cachedFile(for: audioB) == nil, "音频缓存：空数据不写盘")

        check(MangaImageDiskCache.diskBytes() > 0, "漫画缓存：占用空间可统计")
        check(AudioDiskCache.diskBytes() > 0, "音频缓存：占用空间可统计")

        MangaImageDiskCache.removeAll()
        AudioDiskCache.removeAll()
        check(MangaImageDiskCache.data(for: imageA) == nil, "漫画缓存：清空后读不到")
        check(AudioDiskCache.cachedFile(for: audioA) == nil, "音频缓存：清空后读不到")
    }
}

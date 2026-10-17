import Foundation

/// 音频书源（喜马拉雅类，bookSourceType == 1）的识别与内容加载短路，不访问网络。
enum AudioChapterRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        var audio = BookSource(bookSourceUrl: "https://www.ximalaya.com", bookSourceName: "喜马拉雅（优+）")
        audio.bookSourceType = 1
        let chapter = BookChapter(url: "https://vod.xmcdn.com/storages/x.m4a?buy_key=abc", title: "第1集", index: 0)
        check(AudioChapter.isAudio(source: audio, chapter: chapter), "音频源章节识别：类型 1")
        check(AudioChapter.isAudio(source: nil, chapter: chapter), "音频源章节识别：地址直链（无书源上下文）")
        check(AudioChapter.isAudio(source: audio, chapter: BookChapter(url: "https://a.example/x.mp3", title: "", index: 0)),
              "mp3 直链识别")
        check(!AudioChapter.isAudio(source: audio, chapter: BookChapter(url: "  ", title: "", index: 0)),
              "空地址不算音频章节")

        var text = BookSource(bookSourceUrl: "https://t.example", bookSourceName: "文字源")
        text.bookSourceType = 0
        let html = BookChapter(url: "https://t.example/chapter/1.html", title: "", index: 0)
        check(!AudioChapter.isAudio(source: text, chapter: html), "文字源 html 章节不识别")
        check(!AudioChapter.isDirectAudioURL("https://t.example/chapter/1.html"), "html 不是音频直链")
        check(!AudioChapter.isDirectAudioURL("/album/123"), "相对地址不是音频直链")
        check(!AudioChapter.isDirectAudioURL("ftp://x.example/a.mp3"), "非 http(s) 不算直链")
        check(AudioChapter.isDirectAudioURL("https://x.example/a.M4A?z=1"), "扩展名大小写与查询参数")
        check(AudioChapter.isDirectAudioURL("http://x.example/a/b.m4a#frag"), "锚点不影响判定")
        check(AudioChapter.isDirectAudioURL("https://x.example/play/10086.mp3"), "带路径的直链")
        check(AudioChapter.firstAudioURL(in: "  \nhttps://x.example/a.mp3?k=1\nhttps://x.example/b.m4a\n")
              == "https://x.example/a.mp3?k=1", "多行取第一个音频地址")
        check(AudioChapter.firstAudioURL(in: "https://x.example/page.html") == nil, "非音频返回 nil")

        // 音频章节的正文加载：直接返回章节地址，不触网、不写缓存。
        let book = Book(bookUrl: "https://mobile.ximalaya.com/album/1", name: "测试专辑", origin: audio.bookSourceUrl)
        let loaded = try await ChapterContentLoader.content(source: audio, book: book, chapter: chapter,
                                                            nextChapterURL: nil)
        check(loaded == chapter.url, "音频章节内容加载直接返回直链")

        let volume = BookChapter(url: "", title: "第一卷", index: 1, isVolume: true)
        let volumeText = try await ChapterContentLoader.content(source: audio, book: book, chapter: volume,
                                                                nextChapterURL: nil)
        check(volumeText == "第一卷", "卷标题仍按本地展示")
    }
}

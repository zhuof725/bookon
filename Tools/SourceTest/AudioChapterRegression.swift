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

        // 播放地址：正文规则为空时就是章节链接（原版 getContentAwait 的短路）。
        var noRule = audio
        noRule.ruleContent = ContentRule(content: "  ")
        check(AudioChapter.hasContentRule(noRule) == false, "空正文规则视为没有规则")
        let directURLs = try await AudioChapter.playURLs(source: noRule, book: book, chapter: chapter)
        check(directURLs == [chapter.url], "没有正文规则时播放地址 = 章节链接")
        check(AudioChapter.hasContentRule(audio) == false, "缺省书源没有正文规则")

        // 有正文规则时，规则结果是播放地址（原版 durPlayUrl = content.trim()）。
        check(AudioChapter.playURLs(fromContent: " https://cdn.example/a.m4a?sign=1 \n")
              == ["https://cdn.example/a.m4a?sign=1"], "单行地址去空白")
        check(AudioChapter.playURLs(fromContent: "https://cdn.example/api/getAudio?id=9")
              == ["https://cdn.example/api/getAudio?id=9"], "无扩展名的接口地址也算可播放")
        check(AudioChapter.playURLs(fromContent: #"["https://cdn.example/1.mp3","https://cdn.example/2.mp3"]"#)
              == ["https://cdn.example/1.mp3", "https://cdn.example/2.mp3"], "JSON 数组按段播放")
        check(AudioChapter.playURLs(fromContent: #"{"code":0,"data":{"audioUrl":"https://cdn.example/a.m4a"}}"#)
              == ["https://cdn.example/a.m4a"], "JSON 对象取 audioUrl")
        check(AudioChapter.playURLs(fromContent: #"{"data":[{"url":"https://cdn.example/x.mp3"}]}"#)
              == ["https://cdn.example/x.mp3"], "JSON 嵌套数组取 url")
        check(AudioChapter.playURLs(fromContent: "第一行说明\nhttps://cdn.example/b.mp3\n第三行")
              == ["https://cdn.example/b.mp3"], "多行里挑音频直链")
        check(AudioChapter.playURLs(fromContent: "").isEmpty, "空正文解析不出地址")
        check(AudioChapter.playURLs(fromContent: "未获取到资源链接").isEmpty, "提示文字不当地址")

        // 播放记忆：按书记住章 + 秒，同章才续播。
        let suite = "audio-progress-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let bookURL = "https://mobile.ximalaya.com/album/1"
        check(AudioProgress.load(bookUrl: bookURL, defaults: defaults) == nil, "第一次没有播放记忆")
        AudioProgress.save(bookUrl: bookURL, chapter: 3, seconds: 92.5, defaults: defaults)
        check(AudioProgress.load(bookUrl: bookURL, defaults: defaults)
              == AudioProgress.Position(chapter: 3, seconds: 92.5), "记忆章号与秒数")
        check(AudioProgress.resumeSeconds(bookUrl: bookURL, chapter: 3, defaults: defaults) == 92.5,
              "同一章从上次位置续播")
        check(AudioProgress.resumeSeconds(bookUrl: bookURL, chapter: 4, defaults: defaults) == 0,
              "换章从章首开始")
        check(AudioProgress.resumeSeconds(bookUrl: "https://other/book", chapter: 3, defaults: defaults) == 0,
              "不同书互不影响")
        AudioProgress.save(bookUrl: bookURL, chapter: 3, seconds: -1, defaults: defaults)
        check(AudioProgress.load(bookUrl: bookURL, defaults: defaults)?.seconds == 92.5,
              "非法秒数不覆盖已有记忆")
        AudioProgress.clear(bookUrl: bookURL, defaults: defaults)
        check(AudioProgress.load(bookUrl: bookURL, defaults: defaults) == nil, "清空后没有记忆")
        defaults.removePersistentDomain(forName: suite)

        // 刷新目录后按标题重定位（音频直链每次抓取都会重新签名，URL 必然变化）。
        let refreshed = [
            BookChapter(url: "https://vod.xmcdn.com/x.m4a?sign=new1", title: "第1集", index: 0),
            BookChapter(url: "https://vod.xmcdn.com/y.m4a?sign=new2", title: "第2集", index: 1),
        ]
        check(AudioChapter.relocatedIndex(in: refreshed, title: "第2集", fallback: 0) == 1,
              "刷新后按标题定位到新链接的同一章")
        check(AudioChapter.relocatedIndex(in: refreshed, title: "不存在", fallback: 9) == 1,
              "标题找不到时退回原序号并按新目录长度钳制")
        check(AudioChapter.relocatedIndex(in: refreshed, title: nil, fallback: 0) == 0,
              "无标题时用原序号")
        check(AudioChapter.relocatedIndex(in: [], title: "第1集", fallback: 0) == nil,
              "空目录返回 nil")
    }
}

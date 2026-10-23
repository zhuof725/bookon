import Foundation

/// 阅读模式识别（文本 / 漫画 / 音频）的纯逻辑回归，不访问网络。
enum BookKindRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        // 书源类型 → 模式；0/缺省表示未声明，交给正文识别。
        check(BookKind.from(sourceType: 0) == nil, "类型 0 未声明")
        check(BookKind.from(sourceType: nil) == nil, "类型缺省未声明")
        check(BookKind.from(sourceType: 1) == .audio, "类型 1 = 音频")
        check(BookKind.from(sourceType: 2) == .image, "类型 2 = 漫画")
        check(BookKind.from(sourceType: 3) == .file, "类型 3 = 文件")
        check(BookKind.from(sourceType: 4) == .video, "类型 4 = 视频")
        check(BookKind.from(sourceType: 9) == nil, "未知类型不猜")

        // 正文识别：成组 <img> 且几乎没字 → 漫画。
        let manga = (1...6).map { "<img src=\"https://img.example/p\($0).jpg\">" }.joined(separator: "\n")
        check(BookKind.detect(inContent: manga) == .image, "多张图片且无文字识别为漫画")
        let mangaWithAlt = "<div>" + (1...4).map { "<img src='https://img.example/\($0).webp' alt='第\($0)页'>" }.joined() + "</div>"
        check(BookKind.detect(inContent: mangaWithAlt) == .image, "单引号 src 也识别")
        check(BookKind.detect(inContent: "<p>只有一张图</p><img src=\"https://img.example/1.jpg\">") == .text,
              "文字插图不算漫画")
        check(BookKind.detect(inContent: "正文第一段。\n正文第二段。") == .text, "纯文字是文本")
        let longText = String(repeating: "这是一段很长的正文内容，讲了很多事情。", count: 30)
        let illustrated = longText
            + "<img src=\"https://img.example/a.jpg\"><img src=\"https://img.example/b.jpg\">"
            + "<img src=\"https://img.example/c.jpg\">"
        check(longText.count > 500, "样例正文足够长")
        check(BookKind.detect(inContent: illustrated) == .text, "长篇正文里的插图不算漫画")

        // 正文识别：整段就是音频地址（或地址数组）→ 音频。
        check(BookKind.detect(inContent: "https://cdn.example/a.m4a?sign=1") == .audio, "单条音频地址识别为音频")
        check(BookKind.detect(inContent: "https://cdn.example/api/get?id=9") == .audio, "接口形状的音频地址")
        check(BookKind.detect(inContent: #"["https://cdn.example/1.mp3","https://cdn.example/2.mp3"]"#) == .audio,
              "音频地址数组")
        // 音频代理地址很长（带签名参数），不能按字数把它当正文。
        let longAudio = "https://fqapi.example:8080/api/media/stream?url=https%3A%2F%2Fvod.example%2F"
            + String(repeating: "abcdef0123456789", count: 40) + "&mime_type=audio_mpeg"
        check(longAudio.count > 600, "长地址样例足够长")
        check(BookKind.detect(inContent: longAudio) == .audio, "超长音频代理地址识别为音频")
        check(BookKind.detect(inContent: "https://cdn.example/book/1.html") == .text, "网页地址仍是文本")
        check(BookKind.detect(inContent: "https://cdn.example/play/index.php?id=1") == .text, "php 页面不算音频")
        check(BookKind.detect(inContent: "本章内容请到 https://cdn.example/a.m4a 收听") == .text, "正文里提到音频地址仍是文本")
        check(BookKind.detect(inContent: "") == .text, "空正文按文本")
        check(BookKind.imageTagCount("<img src=a><IMG src=b><imgs src=c>") == 2, "只数 <img 标签")
        check(BookKind.strippedText("<p>你好&nbsp;世界</p>") == "你好 世界", "去标签并还原 nbsp")

        // 不联网的快速判断：书源名 + 目录章节名。
        let comicSource = BookSource(bookSourceUrl: "https://comic.example", bookSourceName: "番茄漫画")
        check(BookKind.guess(source: comicSource, chapters: []) == .image, "书源名带「漫画」直接判漫画")
        let audioSource = BookSource(bookSourceUrl: "https://audio.example", bookSourceName: "七猫听书[官方]m1.1")
        check(BookKind.guess(source: audioSource, chapters: []) == .audio, "书源名带「听书」直接判音频")
        let textSource = BookSource(bookSourceUrl: "https://text.example", bookSourceName: "书山聚合")
        let comicChapters = (0..<10).map { BookChapter(url: "https://c/\($0)", title: "第\($0 + 1)话 剧情", index: $0) }
        check(BookKind.guess(source: textSource, chapters: comicChapters) == .image, "章节名「第N话」判漫画")
        let audioChapters = (0..<10).map { BookChapter(url: "https://a/\($0)", title: "第\($0 + 1)集 口播", index: $0) }
        check(BookKind.guess(source: textSource, chapters: audioChapters) == .audio, "章节名「第N集」判音频")
        let textChapters = (0..<10).map { BookChapter(url: "https://t/\($0)", title: "第\($0 + 1)章 正文", index: $0) }
        check(BookKind.guess(source: textSource, chapters: textChapters) == nil, "普通章节名不猜")
        let mixed = (0..<10).map { BookChapter(url: "https://m/\($0)", title: $0 < 3 ? "第\($0 + 1)话" : "第\($0 + 1)章", index: $0) }
        check(BookKind.guess(source: textSource, chapters: mixed) == nil, "话/章混用不硬猜")

        // 书本身/地址里的标记（照 Yuedu 的 OnlineBookContentInference）。
        check(BookKind.kind(fromURL: "https://agg.example/api?tab=%E6%BC%AB%E7%94%BB") == .image,
              "地址参数 tab=漫画")
        check(BookKind.kind(fromURL: "https://agg.example/api?type=2&id=1") == .image, "地址参数 type=2")
        check(BookKind.kind(fromURL: "https://agg.example/api?media=audio") == .audio, "地址参数 media=audio")
        check(BookKind.kind(fromURL: "https://agg.example/api?id=1") == nil, "没有类型参数不猜")
        let payload = try JSONSerialization.data(withJSONObject: ["tab": "听书", "id": 7])
        let embedded = "data:;base64," + payload.base64EncodedString() + ",其他"
        check(BookKind.kind(fromURL: embedded) == .audio, "地址里内嵌 base64 JSON")
        check(BookKind.kind(fromMetadataText: "当前模式：漫画") == .image, "简介里的当前模式标记")
        check(BookKind.kind(fromMetadataText: "当前模式：听书 第1集") == .audio, "简介里的听书标记")
        check(BookKind.kind(fromMetadataText: "漫画") == .image, "等值类型名")
        check(BookKind.kind(fromTypeNumber: 32) == .audio, "Legado 位标记 32 = 音频")
        check(BookKind.kind(fromTypeNumber: 64) == .image, "Legado 位标记 64 = 图片")
        check(BookKind.kind(fromTypeNumber: 8) == .text, "Legado 位标记 8 = 文本")

        var aggBook = Book(bookUrl: "https://agg.example/play?id=1&tab=%E6%BC%AB%E7%94%BB", name: "测试", origin: "agg")
        check(BookKind.infer(source: textSource, book: aggBook) == .image, "书地址里的 tab 决定漫画")
        aggBook.bookUrl = "https://agg.example/play?id=1"
        check(BookKind.infer(source: textSource, book: aggBook) == nil, "没有信号时不硬猜")
        check(BookKind.infer(source: comicSource, book: aggBook) == nil, "书源名不参与 infer（交给 guess）")

        // 聚合源把当前模式存在源变量里（小六项目番茄书源：type=漫画模式）。
        check(BookKind.kind(fromRuntimeVariables: #"{"type":"漫画模式","module":"8"}"#) == .image,
              "源变量 type=漫画模式")
        check(BookKind.kind(fromRuntimeVariables: #"{"type":"听书模式"}"#) == .audio, "源变量 type=听书模式")
        check(BookKind.kind(fromRuntimeVariables: #"{"type":"小说模式","module":"3"}"#) == .text,
              "源变量 type=小说模式")
        check(BookKind.kind(fromRuntimeVariables: #"{"more":{"tab":2}}"#) == .image, "源变量嵌套 tab=2")
        check(BookKind.kind(fromRuntimeVariables: "不是 JSON") == nil, "源变量不是 JSON 时不猜")
        var plainBook = Book(bookUrl: "data:;base64,MTIzNDU2Nzg5,{}", name: "测试", origin: "小六")
        check(BookKind.infer(source: textSource, book: plainBook,
                             sourceVariables: #"{"type":"漫画模式"}"#) == .image, "源变量能让无标记的书判成漫画")
        check(BookKind.infer(source: textSource, book: plainBook,
                             sourceVariables: #"{"type":"小说模式"}"#) == nil, "小说模式不强制（继续看正文）")

        // 每本书的识别结果缓存。
        let suite = "book-kind-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let url = "https://book.example/1"
        check(BookKindStore.saved(bookUrl: url, defaults: defaults) == nil, "未识别时没有缓存")
        BookKindStore.save(.image, bookUrl: url, defaults: defaults)
        check(BookKindStore.saved(bookUrl: url, defaults: defaults) == .image, "缓存漫画识别结果")
        BookKindStore.clear(bookUrl: url, defaults: defaults)
        check(BookKindStore.saved(bookUrl: url, defaults: defaults) == nil, "清空后重新识别")
        defaults.removePersistentDomain(forName: suite)
    }
}

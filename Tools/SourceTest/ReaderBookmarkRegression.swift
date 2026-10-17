import Foundation

/// 书签存储与正文图片解码的离线回归。
enum ReaderBookmarkRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bookmarks-\(UUID().uuidString).json")
        let store = ReaderBookmarkStore(fileURL: url)
        let bookmark = ReaderBookmark(id: "b1", bookURL: "book", bookName: "书",
                                      chapterIndex: 3, chapterTitle: "第三章",
                                      text: "  一段选中的文字 ",
                                      position: 240, createdAt: Date(timeIntervalSince1970: 100))
        check(store.toggle(bookmark), "书签：首次加入返回新增")
        check(store.contains(bookURL: "book", chapterIndex: 3, text: "一段选中的文字"), "书签：忽略首尾空白后命中")
        check(!store.contains(bookURL: "book", chapterIndex: 4, text: "一段选中的文字"), "书签：其它章节不算已存在")
        check(store.list(bookURL: "book").count == 1, "书签：按书查询")
        check(!store.toggle(bookmark), "书签：同一段再点一次即取消")
        check(store.list(bookURL: "book").isEmpty, "书签：取消后列表为空")

        var second = bookmark
        second.id = "b2"; second.chapterIndex = 1; second.text = "更早的段落"
        _ = store.toggle(second)
        _ = store.toggle(bookmark)
        check(store.list(bookURL: "book").map(\.chapterIndex) == [1, 3], "书签：按章节排序")
        check(store.list(bookURL: "book").first?.label == "更早的段落", "书签：有文字时显示选段")

        store.flush()
        let reloaded = ReaderBookmarkStore(fileURL: url)
        check(reloaded.list(bookURL: "book").count == 2, "书签：重启后读回")
        reloaded.remove(id: "b1")
        check(reloaded.list(bookURL: "book").map(\.id) == ["b2"], "书签：删除单条")

        var empty = bookmark
        empty.text = "   "
        check(empty.label == "第三章", "书签：未选中文字时显示章节名")
        try? FileManager.default.removeItem(at: url)

        // 正文图片解码：base64 与百分号编码两种 data: 形式都应得到原始字节。
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let base64 = "data:image/png;base64," + bytes.base64EncodedString()
        check(DataURIDecode.data(base64) == bytes, "图片：base64 data URI 解码")
        // 百分号编码按 UTF-8 解码（真实 data: URI 的写法），中文与符号都能还原。
        let source = "<svg>中文 &amp; 符号</svg>"
        let encoded = "data:image/png," + (source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        check(DataURIDecode.data(encoded) == Data(source.utf8), "图片：百分号编码 data URI 解码")
        check(DataURIDecode.data("data:image/png;base64," + bytes.base64EncodedString()
            .replacingOccurrences(of: "A", with: "A\n")) == bytes, "图片：base64 中的换行被忽略")
        check(DataURIDecode.data("data:image/svg+xml,<svg></svg>") == nil, "图片：SVG 气泡不作为位图导出")
        check(DataURIDecode.data("data:image/png;base64,@@@") == nil, "图片：坏 base64 安全返回 nil")
    }
}

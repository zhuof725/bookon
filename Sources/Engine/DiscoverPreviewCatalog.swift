import Foundation

/// 模板预览用的内置示例书目。
///
/// 选的全部是**公有领域**作品：作者逝世超过 50 年，在多数司法辖区已进入公有领域，
/// 可以随 App 一起分发而不涉及版权问题。
/// 封面不内置任何图片——由 `DiscoverPreviewCover` 按书名哈希现画。
enum DiscoverPreviewCatalog {
    struct Sample: Identifiable, Hashable {
        let title: String
        let author: String
        let kind: String

        var id: String { title }
    }

    /// 24 本公版书。
    static let samples: [Sample] = [
        Sample(title: "西游记", author: "吴承恩", kind: "古典小说"),
        Sample(title: "红楼梦", author: "曹雪芹", kind: "古典小说"),
        Sample(title: "三国演义", author: "罗贯中", kind: "古典小说"),
        Sample(title: "水浒传", author: "施耐庵", kind: "古典小说"),
        Sample(title: "聊斋志异", author: "蒲松龄", kind: "志怪"),
        Sample(title: "镜花缘", author: "李汝珍", kind: "古典小说"),
        Sample(title: "呐喊", author: "鲁迅", kind: "短篇集"),
        Sample(title: "朝花夕拾", author: "鲁迅", kind: "散文"),
        Sample(title: "骆驼祥子", author: "老舍", kind: "长篇小说"),
        Sample(title: "边城", author: "沈从文", kind: "中篇"),
        Sample(title: "巴黎圣母院", author: "雨果", kind: "浪漫主义"),
        Sample(title: "悲惨世界", author: "雨果", kind: "浪漫主义"),
        Sample(title: "战争与和平", author: "托尔斯泰", kind: "史诗"),
        Sample(title: "安娜·卡列尼娜", author: "托尔斯泰", kind: "长篇小说"),
        Sample(title: "罪与罚", author: "陀思妥耶夫斯基", kind: "心理"),
        Sample(title: "傲慢与偏见", author: "简·奥斯汀", kind: "英国文学"),
        Sample(title: "简·爱", author: "夏洛蒂·勃朗特", kind: "英国文学"),
        Sample(title: "呼啸山庄", author: "艾米莉·勃朗特", kind: "英国文学"),
        Sample(title: "双城记", author: "狄更斯", kind: "英国文学"),
        Sample(title: "老人与海", author: "海明威", kind: "中篇"),
        Sample(title: "了不起的盖茨比", author: "菲茨杰拉德", kind: "美国文学"),
        Sample(title: "变形记", author: "卡夫卡", kind: "现代主义"),
        Sample(title: "局外人", author: "加缪", kind: "存在主义"),
        Sample(title: "雪国", author: "川端康成", kind: "日本文学")
    ]

    /// 转成卡片条目。
    static func cards(count: Int = 12) -> [DeckItem] {
        samples.prefix(max(0, count)).map { sample in
            DeckItem(id: "preview://\(sample.title)",
                     title: sample.title,
                     caption: sample.author,
                     cover: previewURL(for: sample.title))   // 自绘封面，不请求网络
        }
    }

    /// 自绘封面的地址：`preview://cover?title=书名`。
    /// 只有 scheme 是 preview 时 `DeckCoverImage` 才会走现画分支。
    static func previewURL(for title: String) -> URL? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "preview://cover?title=\(encoded)")
    }

    /// 一批用于轮播大图的示例（标题 + 副标题）。
    static func heroSamples(count: Int = 4) -> [Sample] {
        Array(samples.prefix(max(0, count)))
    }
}

// MARK: - 自绘封面

/// 按书名生成封面配色：同一本书每次结果一致，进程无关。
///
/// 不内置任何图片资源，也不请求网络——预览用的是纯计算出来的抽象图形。
enum DiscoverPreviewCover {
    /// 一组深浅配对的底色，取自偏沉稳的色调，避免预览看起来像玩具。
    static let palettes: [(String, String)] = [
        ("2D4A6B", "16283D"), ("6B3A2D", "3D1F16"),
        ("2D6B52", "163D2E"), ("4A2D6B", "28163D"),
        ("6B5A2D", "3D3216"), ("2D6B6B", "163D3D"),
        ("6B2D4A", "3D1628"), ("3A4A2D", "1F2A16"),
        ("2D3A6B", "161F3D"), ("6B4A2D", "3D2816")
    ]

    /// 稳定哈希（FNV-1a），不用 `hashValue`——后者每次启动都不同。
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }

    /// 取配色：返回两个十六进制字符串。
    static func colors(for title: String) -> (start: String, end: String) {
        let palette = palettes[Int(stableHash(title) % UInt64(palettes.count))]
        return palette
    }

    /// 三个装饰圆的相对位置（0...1），按书名固定。
    static func orbs(for title: String) -> [(x: Double, y: Double, r: Double)] {
        let hash = stableHash(title)
        return (0..<3).map { index in
            let shifted = hash >> UInt64(index * 7)
            let x = Double((shifted & 0x3F) % 88) / 100 + 0.06
            let y = Double(((shifted >> 6) & 0x3F) % 78) / 100 + 0.10
            let r = 0.08 + Double((shifted >> 12) & 0x0F) / 100
            return (x, y, r)
        }
    }
}

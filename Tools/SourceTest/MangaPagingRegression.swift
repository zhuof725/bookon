import Foundation

/// 漫画阅读方式（从右到左 / 从左到右 / 纵向翻页 / 条漫）的页码映射与手势语义。
/// 纯计算，不依赖 UIKit，可在 CLI 回归里直接验证。
enum MangaPagingRegression {
    static func run(_ check: (Bool, String) -> Void) {
        // 阅读方式本身：顺序、文案、存储值稳定（AppStorage 里存的是 rawValue）。
        check(MangaReadingMode.allCases == [.rightToLeft, .leftToRight, .vertical, .webtoon],
              "漫画阅读方式：四种模式与顺序")
        check(MangaReadingMode.rightToLeft.rawValue == "rightToLeft"
              && MangaReadingMode.webtoon.rawValue == "webtoon",
              "漫画阅读方式：rawValue 稳定（@AppStorage 依赖）")
        check(MangaReadingMode(rawValue: "vertical") == .vertical
              && MangaReadingMode(rawValue: "unknown") == nil,
              "漫画阅读方式：可从存储值还原，未知值回退默认")
        check(MangaReadingMode.fallback == .webtoon, "漫画阅读方式：默认条漫（保持原阅读体验）")
        check(MangaReadingMode.webtoon.isPaged == false
              && MangaReadingMode.rightToLeft.isPaged
              && MangaReadingMode.leftToRight.isPaged
              && MangaReadingMode.vertical.isPaged,
              "漫画阅读方式：只有条漫走连续滚动")
        check(MangaReadingMode.rightToLeft.isHorizontal && MangaReadingMode.leftToRight.isHorizontal
              && !MangaReadingMode.vertical.isHorizontal && !MangaReadingMode.webtoon.isHorizontal,
              "漫画阅读方式：横/纵轴判定")
        check(MangaReadingMode.rightToLeft.title == "从右到左"
              && MangaReadingMode.leftToRight.title == "从左到右"
              && MangaReadingMode.vertical.title == "纵向翻页"
              && MangaReadingMode.webtoon.title == "条漫",
              "漫画阅读方式：菜单文案")

        // 页码 ↔ 列表下标：从右到左整章倒序；其余按原序。
        let count = 5
        check(MangaPaging.itemIndex(forPage: 0, count: count, mode: .leftToRight) == 0
              && MangaPaging.itemIndex(forPage: 4, count: count, mode: .leftToRight) == 4,
              "分页：从左到右按原序铺开")
        check(MangaPaging.itemIndex(forPage: 0, count: count, mode: .vertical) == 0,
              "分页：纵向翻页按原序铺开")
        check(MangaPaging.itemIndex(forPage: 0, count: count, mode: .rightToLeft) == 4
              && MangaPaging.itemIndex(forPage: 1, count: count, mode: .rightToLeft) == 3
              && MangaPaging.itemIndex(forPage: 4, count: count, mode: .rightToLeft) == 0,
              "分页：从右到左倒序（第 0 页在最右）")
        for mode in MangaReadingMode.allCases {
            for page in 0..<count {
                let index = MangaPaging.itemIndex(forPage: page, count: count, mode: mode)
                check(MangaPaging.page(forItem: index, count: count, mode: mode) == page,
                      "分页：\(mode.title) 第 \(page) 页下标/页码互逆")
            }
        }
        // 越界钳制与空章。
        check(MangaPaging.itemIndex(forPage: 99, count: count, mode: .rightToLeft) == 0
              && MangaPaging.itemIndex(forPage: -3, count: count, mode: .rightToLeft) == 4,
              "分页：页码越界被钳制")
        check(MangaPaging.itemIndex(forPage: 0, count: 0, mode: .rightToLeft) == 0
              && MangaPaging.page(forItem: 3, count: 0, mode: .leftToRight) == 0,
              "分页：空章不越界")
        check(MangaPaging.itemIndex(forPage: 0, count: 1, mode: .rightToLeft) == 0,
              "分页：单页章节下标为 0")

        // 越过列表两端时切章：从右到左的前端是章末。
        check(MangaPaging.chapterStep(atLeadingEdge: true, mode: .leftToRight) == -1
              && MangaPaging.chapterStep(atLeadingEdge: false, mode: .leftToRight) == 1,
              "切章：从左到右 前端=上一章 末端=下一章")
        check(MangaPaging.chapterStep(atLeadingEdge: true, mode: .vertical) == -1
              && MangaPaging.chapterStep(atLeadingEdge: false, mode: .vertical) == 1,
              "切章：纵向翻页 前端=上一章 末端=下一章")
        check(MangaPaging.chapterStep(atLeadingEdge: true, mode: .rightToLeft) == 1
              && MangaPaging.chapterStep(atLeadingEdge: false, mode: .rightToLeft) == -1,
              "切章：从右到左 前端=下一章 末端=上一章")
        check(MangaPaging.chapterStep(atLeadingEdge: true, mode: .webtoon) == -1,
              "切章：条漫不走回弹切章（占位值仍自洽）")

        // 点按分区：左/右、上/下、中间。
        check(MangaPaging.tapStep(fraction: 0.1, mode: .leftToRight) == -1
              && MangaPaging.tapStep(fraction: 0.9, mode: .leftToRight) == 1
              && MangaPaging.tapStep(fraction: 0.5, mode: .leftToRight) == 0,
              "点按：从左到右 左=上一页 右=下一页 中间=面板")
        check(MangaPaging.tapStep(fraction: 0.1, mode: .rightToLeft) == 1
              && MangaPaging.tapStep(fraction: 0.9, mode: .rightToLeft) == -1
              && MangaPaging.tapStep(fraction: 0.5, mode: .rightToLeft) == 0,
              "点按：从右到左 左=下一页 右=上一页 中间=面板")
        check(MangaPaging.tapStep(fraction: 0.1, mode: .vertical) == -1
              && MangaPaging.tapStep(fraction: 0.9, mode: .vertical) == 1
              && MangaPaging.tapStep(fraction: 0.5, mode: .vertical) == 0,
              "点按：纵向 上=上一页 下=下一页 中间=面板")
        check(MangaPaging.tapStep(fraction: 0.1, mode: .webtoon) == 0
              && MangaPaging.tapStep(fraction: 0.9, mode: .webtoon) == 0,
              "点按：条漫整屏都归面板/翻屏逻辑")
        check(MangaPaging.tapStep(fraction: -5, mode: .leftToRight) == -1
              && MangaPaging.tapStep(fraction: 5, mode: .rightToLeft) == -1,
              "点按：相对位置越界被钳制")
        // 呼出面板必须灵敏：中间 60% 都归面板，两端各只有 20% 用来翻页。
        for mode in [MangaReadingMode.leftToRight, .rightToLeft, .vertical] {
            for fraction in [0.25, 0.5, 0.75] {
                check(MangaPaging.tapStep(fraction: fraction, mode: mode) == 0,
                      "点按：\(mode.title) \(fraction) 处呼出面板")
            }
        }
        check(MangaPaging.tapStep(fraction: 0.19, mode: .vertical) == -1
              && MangaPaging.tapStep(fraction: 0.81, mode: .vertical) == 1,
              "点按：纵向两端 20% 留给翻页")
    }
}

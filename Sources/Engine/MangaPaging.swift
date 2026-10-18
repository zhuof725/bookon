import Foundation

/// 漫画阅读方式。原版只有横向翻页（右→左 / 左→右由 isRtl 决定），这里扩展为四种：
/// 从右到左、从左到右、纵向翻页、条漫（纵向连续滚动）。
enum MangaReadingMode: String, CaseIterable, Identifiable {
    case rightToLeft
    case leftToRight
    case vertical
    case webtoon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightToLeft: return "从右到左"
        case .leftToRight: return "从左到右"
        case .vertical: return "纵向翻页"
        case .webtoon: return "条漫"
        }
    }

    var detail: String {
        switch self {
        case .rightToLeft: return "整页横滑，向右滑看下一页"
        case .leftToRight: return "整页横滑，向左滑看下一页"
        case .vertical: return "整页纵翻，向上滑看下一页"
        case .webtoon: return "纵向连续滚动"
        }
    }

    var symbol: String {
        switch self {
        case .rightToLeft: return "arrow.left"
        case .leftToRight: return "arrow.right"
        case .vertical: return "arrow.up.arrow.down"
        case .webtoon: return "rectangle.portrait"
        }
    }

    /// 是否整页翻页（需要分页容器）。条漫走连续滚动。
    var isPaged: Bool { self != .webtoon }
    var isHorizontal: Bool { self == .rightToLeft || self == .leftToRight }

    static let storageKey = "reader.manga.mode.v1"
    static var fallback: MangaReadingMode { .webtoon }
}

/// 分页模式下的「页码 ↔ 集合视图下标」映射与边界/点按语义。
/// 这层是纯计算，放在引擎里方便离线回归（UICollectionView 的行为在 CLI 里验不了）。
enum MangaPaging {
    /// 阅读顺序第 page 页在集合视图里的下标。
    /// 从右到左把整章倒序铺开：第 0 页在最右边，手指向右滑（内容右移）进入下一页，
    /// 与纸质漫画/原版 isRtl 的手感一致。
    static func itemIndex(forPage page: Int, count: Int, mode: MangaReadingMode) -> Int {
        guard count > 0 else { return 0 }
        let clamped = min(max(page, 0), count - 1)
        switch mode {
        case .rightToLeft: return count - 1 - clamped
        default: return clamped
        }
    }

    /// 集合视图下标对应的阅读顺序页码。
    static func page(forItem index: Int, count: Int, mode: MangaReadingMode) -> Int {
        guard count > 0 else { return 0 }
        let clamped = min(max(index, 0), count - 1)
        switch mode {
        case .rightToLeft: return count - 1 - clamped
        default: return clamped
        }
    }

    /// 拖过列表某一端（回弹超出阈值）时切到哪一章：返回 +1 下一章 / -1 上一章。
    /// 从右到左是倒序排列，所以列表「前端」在阅读顺序上其实是章末。
    static func chapterStep(atLeadingEdge: Bool, mode: MangaReadingMode) -> Int {
        switch mode {
        case .rightToLeft: return atLeadingEdge ? 1 : -1
        default: return atLeadingEdge ? -1 : 1
        }
    }

    /// 点按分区：返回 -1 上一页 / +1 下一页 / 0 呼出或收起面板。
    /// fraction 是手指在翻页轴上的相对位置（0…1）。
    /// 只把两端各 20% 留给翻页，中间 60% 都呼出面板——翻页本来就有滑动，
    /// 面板必须一按就出（用户反馈四种阅读方式下呼出面板要灵敏）。
    static func tapStep(fraction: Double, mode: MangaReadingMode) -> Int {
        let f = min(max(fraction, 0), 1)
        switch mode {
        case .vertical:
            if f < 0.20 { return -1 }
            if f > 0.80 { return 1 }
            return 0
        case .leftToRight:
            if f < 0.20 { return -1 }
            if f > 0.80 { return 1 }
            return 0
        case .rightToLeft:
            if f < 0.20 { return 1 }
            if f > 0.80 { return -1 }
            return 0
        case .webtoon:
            return 0
        }
    }
}

import SwiftUI

/// 全局视觉几何令牌。
///
/// 页面边距、卡片圆角、控件高度以前散落在各个视图里手写（16/18/22/24 混用），
/// 同一屏的页头与内容常常差 8pt，看起来“没对齐”。新增界面一律从这里取值，
/// 改一处即全局生效。
enum AppLayout {
    // MARK: 页面骨架

    /// 页面内容左右边距。页头、列表、网格、选择条统一使用。
    static let pageInset: CGFloat = 16
    /// 页头（胶囊筛选、圆形更多按钮）顶部留白。
    static let headerTopInset: CGFloat = 6
    /// 页面底部留白。
    static let pageBottomInset: CGFloat = 24

    // MARK: 间距阶梯

    /// 4 —— 图标与文字的间隙。
    static let gapXS: CGFloat = 4
    /// 8 —— 行内元素。
    static let gapS: CGFloat = 8
    /// 12 —— 卡片之间。
    static let gapM: CGFloat = 12
    /// 16 —— 区块之间。
    static let gapL: CGFloat = 16
    /// 24 —— 大区块之间。
    static let gapXL: CGFloat = 24

    // MARK: 圆角阶梯

    /// 6 —— 小部件（色块、进度条）。
    static let radiusXS: CGFloat = 6
    /// 11 —— 书籍封面。
    static let radiusCover: CGFloat = 11
    /// 12 —— 输入框、小控件。
    static let radiusControl: CGFloat = 12
    /// 20 —— 卡片、列表行（与主题系统的默认卡片圆角一致）。
    static let radiusCard: CGFloat = 20
    /// 24 —— 面板、大容器、设置分组。
    static let radiusPanel: CGFloat = 24

    // MARK: 控件

    /// 44 —— iOS 最小触控高度，也是页头胶囊/主按钮高度。
    static let controlHeight: CGFloat = 44
    /// 34 —— 紧凑胶囊（搜索选项）。
    static let compactHeight: CGFloat = 34
    /// 0.5 —— 描边线宽。
    static let hairline: CGFloat = 0.5
}

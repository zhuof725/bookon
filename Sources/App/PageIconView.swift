import SwiftUI

/// 页面图标：有相册图就画图，没有就画 emoji。首页胶囊与页面管理都走这里，
/// 保证两处显示一致、圆角一致。
struct PageIconView: View {
    let page: CustomDiscoverPage
    var size: CGFloat = 22
    /// 圆角（图标本身不裁圆时传 0）
    var corner: CGFloat = 0

    private var image: UIImage? { PageIconStore.load(named: page.iconImageFile) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            } else {
                Text(page.icon)
                    .font(.system(size: size))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// 导航栏右上角的「小字 + 小图标」按钮（发现页的「登录 / 分类」）。
///
/// 以前把 `Text` 直接塞进 `ToolbarItem` 里的 `HStack`：导航栏给右侧留的宽度
/// 不够时（书源名字很长时必然不够），`Text` 会被压成一列竖排字、溢出到
/// 玻璃胶囊外面，和标题糊在一起。
///
/// 这里用 `fixedSize` 让标签以「单行理想宽度」参与布局：右侧按钮拿到自己
/// 需要的宽度，标题让位并用省略号截断，不会互相重合。
struct NavTextButton: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    /// 自带玻璃胶囊底。iOS 26 工具栏默认把同一组按钮并进一个共享胶囊，
    /// 用 `.sharedBackgroundVisibility(.hidden)` 拆开后由按钮自己画底，
    /// 两个按钮才算「独立按键」。
    var pill: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .appFont(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, pill ? 11 : 0)
            .frame(height: pill ? 34 : 44)
            .background {
                if pill {
                    AppGlassSurface(shape: Capsule(), tint: Color(uiColor: .secondarySystemBackground))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

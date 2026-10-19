import SwiftUI

/// 竖版书源卡片（网格视图）：圆角渐变头像 + 名称 + 副标题。
/// 用于发现页分组里的书源（两列网格）。
struct SourceGridCard: View {
    @ThemePalette private var palette
    let source: BookSource
    /// 卡片副标题；nil 或空串时显示「分组名，没有分组显示域名」。
    var subtitle: String? = nil

    private var subtitleText: String {
        let custom = (subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? DiscoverCatalog.cardSubtitle(source) : custom
    }

    var body: some View {
        VStack(spacing: 11) {
            SourceAvatarView(name: source.bookSourceName, size: 62)
            VStack(spacing: 3) {
                Text(source.bookSourceName)
                    .appFont(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(subtitleText)
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background {
            ThemeSurface(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), isCard: true)
        }
    }
}

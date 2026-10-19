import SwiftUI

/// 竖版书源卡片（网格视图）：圆角渐变头像 + 名称 + 副标题。
/// 用于发现页分组里的书源，尺寸随「网格列数」设置自适应。
struct SourceGridCard: View {
    @ThemePalette private var palette
    @AppStorage(DiscoverSettings.gridColumnsKey) private var gridColumnsValue = 2
    let source: BookSource
    /// 卡片副标题；nil 或空串时显示「分组名，没有分组显示域名」。
    var subtitle: String? = nil

    private var columns: Int { DiscoverSettings.clampedColumns(gridColumnsValue) }
    private var avatarSize: CGFloat {
        switch columns {
        case 2: return 62
        case 3: return 48
        case 4: return 40
        default: return 34
        }
    }
    private var titleSize: CGFloat { columns >= 4 ? 12 : (columns == 3 ? 13.5 : 16) }
    private var captionSize: CGFloat { columns >= 4 ? 10 : (columns == 3 ? 11 : 12) }
    private var verticalPadding: CGFloat { columns >= 4 ? 12 : (columns == 3 ? 16 : 20) }

    private var subtitleText: String {
        let custom = (subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? DiscoverCatalog.cardSubtitle(source) : custom
    }

    var body: some View {
        VStack(spacing: columns >= 4 ? 7 : 11) {
            SourceAvatarView(name: source.bookSourceName, size: avatarSize)
            VStack(spacing: 3) {
                Text(source.bookSourceName)
                    .appFont(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(subtitleText)
                    .appFont(.system(size: captionSize))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, verticalPadding)
        .padding(.bottom, verticalPadding - 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background {
            ThemeSurface(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), isCard: true)
        }
    }
}

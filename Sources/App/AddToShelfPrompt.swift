import SwiftUI

/// 阅读 30 秒后、书还不在书架时的玻璃提示。
/// 复刻截图的三段式：标题 / 问句 / 两颗大胶囊按钮。
struct AddToShelfPrompt: View {
    @ThemePalette private var palette
    let bookName: String
    let onAdd: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                Text("加入书架")
                    .appFont(.title2.weight(.bold))
                Text("是否将《\(bookName)》加入书架？")
                    .appFont(.body)
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    button("不加入", tint: palette.surface, foreground: palette.primary,
                           identifier: "reader.shelfPrompt.decline", action: onDecline)
                    button("加入", tint: palette.accent, foreground: palette.accent,
                           identifier: "reader.shelfPrompt.add", action: onAdd)
                }
                .padding(.top, 2)
            }
            .padding(22)
            .frame(maxWidth: 340)
            .appGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous),
                      tint: palette.surface, tintOpacity: 0.55)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("reader.shelfPrompt")
        }
    }

    private func button(_ title: String, tint: Color, foreground: Color,
                        identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appFont(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 54)
                .appGlass(in: Capsule(), tint: tint, tintOpacity: title == "加入" ? 0.18 : 0.30)
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

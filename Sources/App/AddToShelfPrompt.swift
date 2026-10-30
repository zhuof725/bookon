import SwiftUI

/// 阅读 30 秒后、书还不在书架时的玻璃提示。
/// 复刻截图的三段式：标题 / 问句 / 两颗大胶囊按钮。
struct AddToShelfPrompt: View {
    let bookName: String
    /// 跟阅读纸面一致：玻璃染纸色，文字用纸面前景色。
    let paper: Color
    let foreground: Color
    let onAdd: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 13) {
                Text("加入书架")
                    .appFont(.system(size: 20, weight: .bold))
                    .foregroundStyle(foreground)
                Text("是否将《\(bookName)》加入书架？")
                    .appFont(.system(size: 15))
                    .foregroundStyle(foreground.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    button("不加入", tint: paper, tintOpacity: 0.42,
                           foreground: foreground, identifier: "reader.shelfPrompt.decline",
                           action: onDecline)
                    button("加入", tint: foreground, tintOpacity: 0.10,
                           foreground: foreground, identifier: "reader.shelfPrompt.add",
                           action: onAdd)
                }
                .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: 300)
            .appGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                      tint: paper, tintOpacity: 0.62)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 9)
            .padding(.horizontal, 28)
            .accessibilityIdentifier("reader.shelfPrompt")
        }
    }

    private func button(_ title: String, tint: Color, tintOpacity: Double,
                        foreground: Color, identifier: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appFont(.system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 48)
                .appGlass(in: Capsule(), tint: tint, tintOpacity: tintOpacity)
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

import SwiftUI

/// The appearance of the app-owned interface. Reader paper themes remain a
/// separate preference because they are part of reading layout and content.
enum AppAppearance: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    static let storageKey = "app.appearance.v1"

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var detail: String {
        switch self {
        case .system: return "根据系统外观自动切换"
        case .light: return "始终使用浅色界面"
        case .dark: return "始终使用深色界面"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppAppearanceSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var rawValue = AppAppearance.system.rawValue

    private var selection: AppAppearance {
        AppAppearance(rawValue: rawValue) ?? .system
    }

    var body: some View {
        List {
            Section {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        rawValue = appearance.rawValue
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: appearance.symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(AppPalette.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appearance.title)
                                    .appFont(.body)
                                    .foregroundStyle(.primary)
                                Text(appearance.detail)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if selection == appearance {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppPalette.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance.theme.\(appearance.rawValue)")
                    .accessibilityAddTraits(selection == appearance ? .isSelected : [])
                }
            } header: {
                Text("外观主题")
            } footer: {
                Text("只改变应用界面的明暗；阅读正文的纸张主题请在阅读设置中调整。")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: selection.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前主题")
                            .appFont(.subheadline)
                        Text(selection.title)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("appearance.current.value")
                    }
                    Spacer()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("appearance.current")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background.ignoresSafeArea())
        .navigationTitle("外观主题")
        .toolbar(.visible, for: .navigationBar)
        .modifier(MonochromeAppStyle())
        .modifier(AppTypographyRoot())
    }
}

import SwiftUI

/// Hosts the production appearance settings page with isolated launch flags.
/// The harness keeps the app-level appearance preference across relaunches so
/// the UI test can verify the actual UserDefaults behavior.
struct AppearanceHarnessView: View {
    @AppStorage(AppAppearance.storageKey) private var rawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: rawValue) ?? .system
    }

    var body: some View {
        NavigationStack {
            AppAppearanceSettingsView()
        }
        .preferredColorScheme(appearance.colorScheme)
        .modifier(MonochromeAppStyle())
        .modifier(AppTypographyRoot())
    }
}

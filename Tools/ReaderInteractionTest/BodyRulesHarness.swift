import SwiftUI

/// Per-test defaults persist across relaunches without touching production data.
enum BodyRulesFixture {
    nonisolated(unsafe) static let defaults: UserDefaults = {
        let token = ProcessInfo.processInfo.environment["BODY_RULES_TEST_SUITE"] ?? "manual"
        let suite = "io.legado.readerharness.body-rules." + token
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Cannot create isolated body rules defaults")
        }
        if !ProcessInfo.processInfo.arguments.contains("--body-rules-keep") {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }()
}

struct BodyRulesHarnessView: View {
    var body: some View {
        NavigationStack {
            BodyReplaceRulesView(defaults: BodyRulesFixture.defaults)
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--body-rules-dark") ? .dark : .light)
    }
}

import SwiftUI

/// A stable, test-owned suite survives relaunches, never touching user defaults.
enum TocRulesFixture {
    static let defaults: UserDefaults = {
        let token = ProcessInfo.processInfo.environment["TOC_RULES_TEST_SUITE"] ?? "manual"
        let suite = "io.legado.readerharness.toc-rules." + token
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Cannot create isolated TOC rules defaults")
        }
        if !ProcessInfo.processInfo.arguments.contains("--toc-rules-keep") {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }()
}

struct TocRulesHarnessView: View {
    var body: some View {
        NavigationStack {
            TxtTocRulesView(defaults: TocRulesFixture.defaults)
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--toc-rules-dark") ? .dark : .light)
    }
}

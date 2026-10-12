import SwiftUI

/// Production history model and views; only submission controls are fixtures.
struct SearchHistoryHarnessView: View {
    @StateObject private var history: BookSearchHistory
    @State private var draft = ""
    @State private var selected = "none"
    @State private var sheet = false
    @State private var report = "pending"
    private let defaults: UserDefaults

    init() {
        let id = ProcessInfo.processInfo.environment["SEARCH_HISTORY_SUITE"]!
        precondition(UUID(uuidString: id) != nil)
        let defaults = UserDefaults(suiteName: "search-history-test." + id)!
        self.defaults = defaults
        _history = StateObject(wrappedValue: BookSearchHistory(defaults: defaults))
    }
    private func submit(_ value: String) {
        let key = BookSearchHistory.normalized(value)
        guard !key.isEmpty else { return }
        history.record(key)
        draft = ""
    }
    private func select(_ value: String) {
        selected = value
        submit(value)
    }
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    TextField("书名或作者", text: $draft)
                        .accessibilityIdentifier("fixture.draft")
                    Button("提交") { submit(draft) }.accessibilityIdentifier("fixture.submit")
                }.padding()
                Text(history.entries.joined(separator: "|"))
                    .accessibilityIdentifier("fixture.entries")
                Text(selected).accessibilityIdentifier("fixture.selected")
                Text(report).accessibilityIdentifier("fixture.report")
                HStack {
                    Button("历史弹窗") { sheet = true }.accessibilityIdentifier("fixture.sheet")
                    Button("模型校验") { checkModel() }.accessibilityIdentifier("fixture.check")
                }
                List { BookSearchHistorySection(history: history, onSelect: select) }
            }
            .navigationTitle("搜索历史验证")
            .sheet(isPresented: $sheet) {
                BookSearchHistorySheet(history: history, onSelect: select)
            }
        }.modifier(AppTypographyRoot())
    }
    private func checkModel() {
        var failures: [String] = []
        func check(_ ok: Bool, _ name: String) { if !ok { failures.append(name) } }
        history.clear()
        history.record(" \n\t ")
        check(history.entries.isEmpty, "empty")
        history.record("  Dune\n")
        history.record("三体")
        history.record("dUNE")
        check(history.entries == ["dUNE", "三体"], "trim-case-recent")
        for i in 0..<25 { history.record("Book\(i)") }
        let expected = (5..<25).reversed().map { "Book\($0)" }
        check(history.entries == expected, "limit-order")
        let reopened = BookSearchHistory(defaults: defaults)
        check(reopened.entries == expected, "new-instance")
        reopened.remove(" book24 ")
        history.reload()
        check(history.entries == Array(expected.dropFirst()), "remove-reload")
        reopened.record("Other")
        history.record("Latest")
        check(Array(history.entries.prefix(2)) == ["Latest", "Other"], "latest-writer")
        history.clear()
        check(defaults.object(forKey: BookSearchHistory.storageKey) == nil, "clear-storage")
        defaults.set([" A ", "a", "", " B\n"], forKey: BookSearchHistory.storageKey)
        history.reload()
        check(history.entries == ["A", "B"], "sanitize-reload")
        history.clear()
        report = failures.isEmpty ? "PASS 8 model checks" : "FAIL " + failures.joined(separator: ",")
    }
}

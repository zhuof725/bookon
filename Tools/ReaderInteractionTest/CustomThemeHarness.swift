import Foundation
import SwiftUI
import UIKit

/// Preferences owned exclusively by the custom-theme harness route. The
/// production store still receives a real UserDefaults instance, but this suite
/// can never read or write the app's standard defaults.
enum CustomThemeHarnessSupport {
    static let suiteName = "io.legado.reader.interaction.custom-theme"
    static let defaults = UserDefaults(suiteName: suiteName)!
}

/// Native-only route for custom theme interaction tests. The store is injected
/// with a suite that is private to this harness, so no real app preference is
/// read, seeded, or cleared by the UI tests.
struct CustomThemeHarnessView: View {
    private enum PreviewDestination: String, Identifiable {
        case shelf, detail
        var id: String { rawValue }
    }

    @ObservedObject private var store: AppThemeStore
    @State private var rootInput = "root-state"
    @State private var rootCounter = 0
    @State private var destination: PreviewDestination?
    @State private var modelReport = "{}"
    @FocusState private var inputFocused: Bool
    private let dark: Bool
    private let narrow: Bool

    init(store: AppThemeStore) {
        _store = ObservedObject(wrappedValue: store)
        let arguments = ProcessInfo.processInfo.arguments
        dark = arguments.contains("--custom-theme-dark")
        narrow = arguments.contains("--custom-theme-width-320")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rootStateBar
                previewBar
                CustomThemeLiveProbe()
                AppAppearanceSettingsView(store: store)
                    .frame(maxHeight: .infinity)
            }
            .navigationDestination(isPresented: Binding(
                get: { destination != nil },
                set: { if !$0 { destination = nil } }
            )) {
                if let destination {
                    preview(destination)
                        .safeAreaInset(edge: .top) {
                            VStack(spacing: 0) {
                                Button("返回主题画廊") { self.destination = nil }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityIdentifier("theme.preview.back")
                                CustomThemeLiveProbe()
                            }.background(.regularMaterial)
                        }
                }
            }
        }
        .onAppear { if modelReport == "{}" { modelReport = CustomThemeModelProbe.run() } }
        .defaultAppStorage(CustomThemeHarnessSupport.defaults)
        .preferredColorScheme(dark ? .dark : .light)
        .modifier(AppThemeRoot(store: store))
        .frame(width: narrow ? 320 : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            // The probe is an accessibility-only leaf. Its value is JSON whose
            // values are booleans, allowing the UI test to assert every check
            // without coupling the test to a fixed check count.
            Text("模型验证").font(.system(size: 8))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Custom theme model probe")
                .accessibilityValue(modelReport)
                .accessibilityIdentifier("theme.model.probe")
                .allowsHitTesting(false)
        }
    }

    private var rootStateBar: some View {
        HStack(spacing: 8) {
            TextField("根状态", text: $rootInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($inputFocused)
                .onSubmit { inputFocused = false }
                .accessibilityIdentifier("theme.harness.input")
            Button("计数 \(rootCounter)") { rootCounter += 1 }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("theme.harness.counter")
            Text("\(rootCounter)")
                .accessibilityIdentifier("theme.harness.counter.value")
                .accessibilityHidden(true)
            Text("\(store.customThemes.count)")
                .font(.caption2)
                .accessibilityIdentifier("theme.harness.custom.count")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var previewBar: some View {
        HStack(spacing: 10) {
            Button("书架预览") { destination = .shelf }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("theme.preview.shelf")
            Button("详情预览") { destination = .detail }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("theme.preview.detail")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func preview(_ destination: PreviewDestination) -> some View {
        switch destination {
        case .shelf:
            BookshelfScreen(
                books: ShelfFixture.books,
                localOrigin: ShelfFixture.localOrigin,
                onOpen: { _ in }, onSearch: {}, onImport: {}, onRemove: { _ in }
            )
        case .detail:
            BookDetailScreen(
                book: DetailFixture.book(missingMetadata: false),
                onShelf: true,
                category: "随笔",
                chapters: DetailFixture.chapters,
                loading: false,
                message: nil,
                onBack: {}, onMore: {}, onRead: {}, onCategory: {}, onSource: {},
                onShelfAction: {}, onEditIntro: {}, onTOC: {}
            )
        }
    }
}

private struct CustomThemeLiveProbe: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @ThemePalette private var palette
    var body: some View {
        Text("测试配色")
            .font(.system(size: 8))
            .foregroundStyle(palette.primary)
            .accessibilityIdentifier("theme.live.palette")
            .accessibilityValue(theme.name + "|" + AppThemeColor.hex(palette.accent, scheme: scheme))
    }
}

/// Model-level checks run against the same production AppTheme/AppThemeStore
/// types used by the gallery and editor. Every reported value is a Bool.
enum CustomThemeModelProbe {
    private struct Snapshot: Codable {
        let version: Int
        let themes: [AppTheme]
        let selectedID: String
    }

    private static func suite(_ suffix: String) -> UserDefaults? {
        UserDefaults(suiteName: "io.legado.reader.interaction.custom-theme-probe.\(suffix)")
    }

    private static func succeeds(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch {
            return false
        }
    }

    private static func throwsError(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return false
        } catch {
            return true
        }
    }

    static func run() -> String {
        var checks: [String: Bool] = [:]
        guard let base = suite("base"),
              let invalidDefaults = suite("invalid"),
              let capacityDefaults = suite("capacity"),
              let multiDefaults = suite("multi"),
              let legacyDefaults = suite("legacy") else {
            return encoded(["probe": false])
        }

        for defaults in [base, invalidDefaults, capacityDefaults, multiDefaults, legacyDefaults] {
            defaults.removeObject(forKey: AppThemeStore.storageKey)
        }

        var invalidName = AppTheme.templates[1].draft()
        invalidName.name = "   "
        let invalidStore = AppThemeStore(defaults: invalidDefaults)
        checks["invalidName"] = invalidName.validationMessage != nil
            && throwsError { try invalidStore.save(invalidName) }

        var invalidHex = AppTheme.templates[1].draft()
        invalidHex.name = "无效颜色"
        invalidHex.light.background = "GGGGGG"
        checks["invalidHex"] = !AppThemeColor.isValid("GGGGGG")
            && invalidHex.validationMessage != nil
            && throwsError { try invalidStore.save(invalidHex) }

        var invalidMode = AppTheme.templates[1].draft()
        invalidMode.name = "浅色深底"
        invalidMode.light = .init(background: "111111", backgroundEnd: "111111",
                                  surface: "1F1F1F", accent: "FFFFFF")
        checks["lightModeContrast"] = invalidMode.validationMessage != nil
            && throwsError { try invalidStore.save(invalidMode) }

        var lowContrast = AppTheme.templates[1].draft()
        lowContrast.name = "低对比度"
        lowContrast.light = .init(background: "FFFFFF", backgroundEnd: "FFFFFF",
                                  surface: "FFFFFF", accent: "FFFFFF")
        checks["contrast"] = lowContrast.validationMessage != nil
            && throwsError { try invalidStore.save(lowContrast) }

        let capacityStore = AppThemeStore(defaults: capacityDefaults)
        var savedCapacity = true
        for index in 0..<AppThemeStore.maximumThemes {
            var theme = AppTheme.templates[1].draft()
            theme.name = "容量主题 \(index)"
            savedCapacity = savedCapacity && succeeds { try capacityStore.save(theme) }
        }
        var overCapacity = AppTheme.templates[1].draft()
        overCapacity.name = "超出容量"
        checks["maximum20"] = savedCapacity
            && capacityStore.customThemes.count == AppThemeStore.maximumThemes
            && throwsError { try capacityStore.save(overCapacity) }

        let fallbackSnapshot = Snapshot(version: 1, themes: [], selectedID: "missing-theme")
        base.set(try? JSONEncoder().encode(fallbackSnapshot), forKey: AppThemeStore.storageKey)
        let fallbackStore = AppThemeStore(defaults: base)
        checks["unknownSelectedFallback"] = fallbackStore.selectedID == AppTheme.defaultID
            && fallbackStore.selectedTheme.id == AppTheme.defaultID

        base.set(Data([0, 1, 2, 3]), forKey: AppThemeStore.storageKey)
        let corruptStore = AppThemeStore(defaults: base)
        checks["corruptPersistence"] = corruptStore.customThemes.isEmpty
            && corruptStore.selectedID == AppTheme.defaultID
            && corruptStore.notice != nil

        let first = AppThemeStore(defaults: multiDefaults)
        var multiTheme = AppTheme.templates[2].draft()
        multiTheme.name = "多实例主题"
        let firstSaved = succeeds { try first.save(multiTheme) }
        let second = AppThemeStore(defaults: multiDefaults)
        let loadedBySecond = second.customThemes.contains(where: { $0.id == multiTheme.id })
        let secondApplied = succeeds { try second.apply(id: multiTheme.id) }
        first.reload()
        checks["multiInstanceReload"] = firstSaved && loadedBySecond && secondApplied
            && first.selectedID == multiTheme.id

        let protectionStore = AppThemeStore(defaults: suite("protection") ?? multiDefaults)
        let saveBuiltIn = throwsError { try protectionStore.save(AppTheme.monochrome) }
        let deleteBuiltIn = throwsError { try protectionStore.delete(id: AppTheme.defaultID) }
        checks["builtInProtection"] = saveBuiltIn && deleteBuiltIn

        legacyDefaults.set(2, forKey: AppAppearance.storageKey)
        legacyDefaults.set(17, forKey: "fontSize")
        legacyDefaults.set(12, forKey: "readerLineHeightTenths")
        legacyDefaults.set(3, forKey: "theme")
        let legacyStore = AppThemeStore(defaults: legacyDefaults)
        var legacyTheme = AppTheme.templates[3].draft()
        legacyTheme.name = "旧设置隔离"
        let legacySave = succeeds { try legacyStore.save(legacyTheme, apply: true) }
        legacyStore.reload()
        checks["legacySettingsUntouched"] = legacySave
            && legacyDefaults.integer(forKey: AppAppearance.storageKey) == 2
            && legacyDefaults.integer(forKey: "fontSize") == 17
            && legacyDefaults.integer(forKey: "readerLineHeightTenths") == 12
            && legacyDefaults.integer(forKey: "theme") == 3

        return encoded(checks)
    }

    private static func encoded(_ checks: [String: Bool]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(checks),
              let value = String(data: data, encoding: .utf8) else { return "{\"probe\":false}" }
        return value
    }
}

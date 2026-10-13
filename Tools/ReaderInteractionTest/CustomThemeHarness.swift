import Foundation
import SwiftUI
import UIKit

/// Preferences owned exclusively by the custom-theme harness route. The
/// production store still receives a real UserDefaults instance, but this suite
/// can never read or write the app's standard defaults.
enum CustomThemeHarnessSupport {
    static let fixtureID = ProcessInfo.processInfo.environment["CUSTOM_THEME_FIXTURE_ID"]
        .flatMap(UUID.init(uuidString:))?.uuidString ?? "legacy-harness"
    static let suiteName = "io.legado.reader.interaction.custom-theme." + fixtureID
    static let defaults = UserDefaults(suiteName: suiteName)!
    static let assetDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(suiteName, isDirectory: true).appendingPathComponent("assets", isDirectory: true)
    static let assets = ThemeAssetStore(directory: assetDirectory)
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
    private let clean: Bool

    init(store: AppThemeStore) {
        _store = ObservedObject(wrappedValue: store)
        let arguments = ProcessInfo.processInfo.arguments
        dark = arguments.contains("--custom-theme-dark")
        narrow = arguments.contains("--custom-theme-width-320")
        clean = arguments.contains("--custom-theme-clean")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !clean {
                    rootStateBar
                    previewBar
                    CustomThemeLiveProbe()
                }
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
        .onAppear {
            // Run capacity/codec regressions once, not on every UI relaunch.
            if modelReport == "{}", ProcessInfo.processInfo.arguments.contains("--custom-theme-model-probe") {
                modelReport = CustomThemeModelProbe.run()
            }
        }
        .defaultAppStorage(CustomThemeHarnessSupport.defaults)
        .preferredColorScheme(dark ? .dark : .light)
        .modifier(AppThemeRoot(store: store))
        .frame(width: narrow ? 320 : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            // Read-only leaves remain accessible in the clean screenshot route
            // but draw no diagnostic text over the real production hub.
            VStack(alignment: .leading, spacing: 0) {
                Text("模型验证")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Custom theme model probe")
                    .accessibilityValue(modelReport)
                    .accessibilityIdentifier("theme.model.probe")
                Text("存储验证")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Custom theme store snapshot")
                    .accessibilityValue(CustomThemeModelProbe.storeReport(store))
                    .accessibilityIdentifier("theme.store.probe")
            }
            .font(.system(size: clean ? 1 : 8))
            .foregroundStyle(clean ? Color.clear : Color.primary)
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
            ThemeCustomizationRuntimeView(store: store)
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

    static func storeReport(_ store: AppThemeStore) -> String {
        let snapshot = Snapshot(version: 1, themes: store.customThemes, selectedID: store.selectedID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
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

    @MainActor
    static func run() -> String {
        var checks: [String: Bool] = [:]
        guard let base = suite("base"),
              let invalidDefaults = suite("invalid"),
              let capacityDefaults = suite("capacity"),
              let multiDefaults = suite("multi"),
              let legacyDefaults = suite("legacy"),
              let v1Defaults = suite("v1-four-field"),
              let extendedDefaults = suite("extended"),
              let protectionDefaults = suite("protection") else {
            return encoded(["probe": false])
        }

        for defaults in [base, invalidDefaults, capacityDefaults, multiDefaults, legacyDefaults,
                         v1Defaults, extendedDefaults, protectionDefaults] {
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

        let protectionStore = AppThemeStore(defaults: protectionDefaults)
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

        checks.merge(compatibilityChecks(defaults: v1Defaults)) { _, new in new }
        checks.merge(extendedChecks(defaults: extendedDefaults)) { _, new in new }
        checks.merge(ThemeCustomizationProbe.run()) { _, new in new }
        checks.merge(ThemeCustomizationRenderProbe.run()) { _, new in new }
        return encoded(checks)
    }

    private static func additionsAreNil(_ colors: AppThemeSwatches) -> Bool {
        colors.primaryText == nil && colors.secondaryText == nil && colors.border == nil
            && colors.selection == nil && colors.cardRadius == nil && colors.cardBorder == nil
    }

    private static func compatibilityChecks(defaults: UserDefaults) -> [String: Bool] {
        var checks = Dictionary(uniqueKeysWithValues: [
            "v1MissingFieldsDecode", "v1FourFieldInitializer", "v1RoundTrip", "v1StoreLoad",
            "v1StorePreserved", "v1PaletteDefaults", "bookDataUntouched"
        ].map { ($0, false) })
        // Literal v1 fixture: never encode the current model to fabricate an
        // allegedly old payload, which could silently include the new fields.
        let json = """
        {"version":1,"selectedID":"11111111-2222-3333-4444-555555555555","themes":[{
          "id":"11111111-2222-3333-4444-555555555555","name":"Legacy Four Colors","backgroundStyle":"gradient",
          "light":{"background":"E4EDF6","backgroundEnd":"F5F7FC","surface":"FFFFFF","accent":"36597C"},
          "dark":{"background":"121E2B","backgroundEnd":"1F3044","surface":"293E53","accent":"BCD9F6"}
        }]}
        """
        let data = Data(json.utf8)
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              let theme = snapshot.themes.first else { return checks }
        checks["v1MissingFieldsDecode"] = snapshot.version == 1 && theme.validationMessage == nil
            && additionsAreNil(theme.light) && additionsAreNil(theme.dark)
        checks["v1FourFieldInitializer"] = additionsAreNil(.init(
            background: "FFFFFF", backgroundEnd: "FFFFFF", surface: "FFFFFF", accent: "101010"))
        if let encoded = try? JSONEncoder().encode(snapshot),
           let restored = try? JSONDecoder().decode(Snapshot.self, from: encoded) {
            checks["v1RoundTrip"] = restored.themes == snapshot.themes
                && restored.selectedID == snapshot.selectedID && restored.version == 1
        }
        // A real Book value is only encoded into this isolated test suite.
        // No library repository or standard-defaults key is opened or written.
        let book = Book(bookUrl: "fixture://theme-unchanged", name: "Unchanged Book", origin: "fixture")
        let bookData = try? JSONEncoder().encode(book)
        defaults.set(bookData, forKey: "probe.book.data")
        defaults.set(data, forKey: AppThemeStore.storageKey)
        let store = AppThemeStore(defaults: defaults)
        checks["v1StoreLoad"] = store.customThemes == [theme] && store.selectedTheme == theme
            && store.notice == nil
        var added = AppTheme.templates[1].draft()
        added.name = "Added beside v1"
        let saved = succeeds { try store.save(added); try store.save(theme, apply: true) }
        let reloaded = AppThemeStore(defaults: defaults)
        checks["v1StorePreserved"] = saved && reloaded.customThemes.count == 2
            && reloaded.selectedTheme == theme && reloaded.customThemes.contains(theme)
            && reloaded.notice == nil
        checks["bookDataUntouched"] = bookData != nil && defaults.data(forKey: "probe.book.data") == bookData
            && (try? JSONDecoder().decode(Book.self, from: defaults.data(forKey: "probe.book.data") ?? Data())) == book
        checks["v1PaletteDefaults"] = [ColorScheme.light, .dark].allSatisfy { scheme in
            let colors = theme.swatches(for: scheme)
            let palette = ResolvedAppPalette(theme: theme, scheme: scheme)
            let backgrounds = [colors.surface] + (0...12).map {
                AppThemeColor.mix(colors.background, colors.backgroundEnd, fraction: Double($0) / 12)
            }
            let ink = AppThemeColor.foreground(over: backgrounds)
            let muted = AppThemeColor.mix(ink, colors.surface, fraction: 0.25)
            let secondary = backgrounds.allSatisfy { AppThemeColor.contrast(muted, $0) >= 4.5 } ? muted : ink
            let tint = AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.12)
            let selection = AppThemeColor.contrast(colors.accent, tint) >= 4.5
                && AppThemeColor.contrast(ink, tint) >= 4.5 ? tint : colors.surface
            return AppThemeColor.hex(palette.primary, scheme: scheme) == ink
                && AppThemeColor.hex(palette.secondary, scheme: scheme) == secondary
                && AppThemeColor.hex(palette.selection, scheme: scheme) == selection
                && AppThemeColor.hex(palette.border, scheme: scheme) == AppThemeColor.mix(colors.surface, ink, fraction: 0.20)
                && palette.cardRadius == CGFloat(AppTheme.defaultCardRadius) && palette.cardBorder
        }
        return checks
    }

    private static func extendedChecks(defaults: UserDefaults) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        var theme = AppTheme.monochrome.draft()
        theme.name = "Explicit tokens"
        theme.light.primaryText = "101010"; theme.light.secondaryText = "454545"
        theme.light.border = "A1B2C3"; theme.light.selection = "F4F5F6"
        theme.light.cardRadius = 10; theme.light.cardBorder = false
        theme.dark.primaryText = "F2F3F4"; theme.dark.secondaryText = "C4C5C6"
        theme.dark.border = "526374"; theme.dark.selection = "202020"
        theme.dark.cardRadius = 28; theme.dark.cardBorder = true
        let store = AppThemeStore(defaults: defaults)
        checks["explicitFieldsValid"] = theme.validationMessage == nil
        checks["explicitFieldsRoundTrip"] = (try? JSONEncoder().encode(theme))
            .flatMap { try? JSONDecoder().decode(AppTheme.self, from: $0) } == theme
        let saved = succeeds { try store.save(theme, apply: true) }
        let restored = AppThemeStore(defaults: defaults)
        checks["explicitFieldsPersistence"] = saved && restored.customThemes == [theme]
            && restored.selectedTheme == theme && restored.notice == nil
        checks["explicitPaletteHexes"] = [ColorScheme.light, .dark].allSatisfy { scheme in
            let colors = theme.swatches(for: scheme)
            let palette = ResolvedAppPalette(theme: theme, scheme: scheme)
            let pairs: [(Color, String)] = [
                (palette.accent, colors.accent), (palette.background, colors.background),
                (palette.backgroundEnd, colors.backgroundEnd), (palette.surface, colors.surface),
                (palette.primary, colors.primaryText ?? ""), (palette.secondary, colors.secondaryText ?? ""),
                (palette.border, colors.border ?? ""), (palette.selection, colors.selection ?? "")
            ]
            return pairs.allSatisfy { AppThemeColor.hex($0.0, scheme: scheme) == $0.1 }
                && Double(palette.cardRadius) == colors.cardRadius && palette.cardBorder == colors.cardBorder
        }
        let paths: [WritableKeyPath<AppThemeSwatches, String?>] = [
            \.primaryText, \.secondaryText, \.border, \.selection
        ]
        let before = defaults.data(forKey: AppThemeStore.storageKey)
        var hexRejected = true, contrastRejected = true, radiusRejected = true
        for dark in [false, true] {
            for path in paths {
                for hex in ["", "GGGGGG", "12345", "1234567", "#123456", "80FF0000"] {
                    var invalid = theme
                    if dark { invalid.dark[keyPath: path] = hex }
                    else { invalid.light[keyPath: path] = hex }
                    let rejected = invalid.validationMessage != nil && throwsError { try store.save(invalid) }
                    hexRejected = rejected && hexRejected
                }
            }
            for path in [\AppThemeSwatches.primaryText, \.secondaryText, \.selection] {
                var invalid = theme
                if dark {
                    invalid.dark[keyPath: path] = path == \AppThemeSwatches.selection ? invalid.dark.accent : invalid.dark.surface
                } else {
                    invalid.light[keyPath: path] = path == \AppThemeSwatches.selection ? invalid.light.accent : invalid.light.surface
                }
                let rejected = invalid.validationMessage != nil && throwsError { try store.save(invalid) }
                contrastRejected = rejected && contrastRejected
            }
            for radius in [7.99, 30.01, -1, Double.nan, Double.infinity, -Double.infinity] {
                var invalid = theme
                if dark { invalid.dark.cardRadius = radius } else { invalid.light.cardRadius = radius }
                let rejected = invalid.validationMessage != nil && throwsError { try store.save(invalid) }
                radiusRejected = rejected && radiusRejected
            }
        }
        checks["optionalHexInvalidRejected"] = hexRejected
        checks["explicitTextSelectionContrastRejected"] = contrastRejected
        checks["cardRadiusInvalidRejected"] = radiusRejected
        checks["invalidEditsDoNotPersist"] = defaults.data(forKey: AppThemeStore.storageKey) == before
            && AppThemeStore(defaults: defaults).selectedTheme == theme
        var limits = theme
        limits.light.cardRadius = 8; limits.dark.cardRadius = 30
        checks["cardRadiusEndpointsPersist"] = limits.validationMessage == nil
            && succeeds { try store.save(limits, apply: true) }
            && AppThemeStore(defaults: defaults).selectedTheme == limits
        return checks
    }

    private static func encoded(_ checks: [String: Bool]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(checks),
              let value = String(data: data, encoding: .utf8) else { return "{\"probe\":false}" }
        return value
    }
}

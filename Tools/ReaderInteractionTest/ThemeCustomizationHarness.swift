import Foundation
import SwiftUI
import UIKit

/// Executes production value/repository code, never a mirrored implementation.
/// Every run owns a UUID defaults suite and temporary asset directory.
@MainActor
enum ThemeCustomizationProbe {
    static func run() -> [String: Bool] {
        let token = UUID().uuidString
        let suite = "io.legado.reader.interaction.customization-probe." + token
        guard let defaults = UserDefaults(suiteName: suite) else { return ["customizationSetup": false] }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let directory = root.appendingPathComponent("assets", isDirectory: true)
            let assets = ThemeAssetStore(directory: directory)
            var checks = modelChecks(defaults: defaults, assets: assets)
            checks.merge(try assetChecks(root: root, directory: directory, assets: assets)) { _, new in new }
            checks.merge(try cleanupChecks(defaults: defaults, assets: assets, directory: directory)) { _, new in new }
            return checks
        } catch {
            // Absence of a required key is also a test failure; a thrown fixture
            // error can never turn a partially executed report into a pass.
            return ["customizationSetup": false]
        }
    }

    private static func rejects(_ action: () throws -> Void) -> Bool {
        do { try action(); return false } catch { return true }
    }

    private static func roundTrip<T: Codable & Equatable>(_ value: T) -> Bool {
        guard let data = try? JSONEncoder().encode(value),
              let restored = try? JSONDecoder().decode(T.self, from: data) else { return false }
        return value == restored
    }

    private static func modelChecks(defaults: UserDefaults, assets: ThemeAssetStore) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        // This literal predates customization; do not manufacture it with the
        // current encoder or accidentally default legacy themes into new UI.
        let legacy = Data("""
        {"id":"11111111-2222-3333-4444-555555555555","name":"Legacy","backgroundStyle":"solid",
         "light":{"background":"F9F9F9","backgroundEnd":"F9F9F9","surface":"FFFFFF","accent":"1A1A1A"},
         "dark":{"background":"111111","backgroundEnd":"111111","surface":"1F1F1F","accent":"EBEBEB"}}
        """.utf8)
        let old = try? JSONDecoder().decode(AppTheme.self, from: legacy)
        checks["customizationLegacyNil"] = old != nil && old?.customization == nil
            && old?.assetIDs.isEmpty == true && old.map(roundTrip) == true
        checks["customizationBuiltInsUnchanged"] = AppTheme.templates.allSatisfy {
            $0.customization == nil && $0.assetIDs.isEmpty
        }
        var theme = AppTheme.custom()
        let neutral = ThemeCustomization()
        checks["customizationNeutralNew"] = theme.customization == neutral
            && theme.light == AppTheme.monochrome.light && theme.dark == AppTheme.monochrome.dark
            && theme.backgroundStyle == .solid && theme.validationMessage == nil
            && !theme.isBuiltIn && UUID(uuidString: theme.id) != nil && theme.id != AppTheme.custom().id
        checks["customizationDefaults"] = neutral.tabStyle == .iconsAndText && neutral.shelfColumns == 3
            && neutral.coverWidth == 112 && neutral.defaultCoverImage == nil && neutral.launchImage == nil
            && neutral.pageBackgroundImage == nil && neutral.fontPostScriptName == nil
            && neutral.effect == .transparent && neutral.cardBackground
        checks["customizationPartialDecodeDefaults"] = (try? JSONDecoder().decode(
            ThemeCustomization.self, from: Data("{}".utf8))) == neutral
        let store = AppThemeStore(defaults: defaults, assets: assets)
        var config = neutral
        config.tabStyle = .text; config.shelfColumns = 2; config.coverWidth = 96
        config.fontPostScriptName = "Helvetica"; config.effect = .opaque; config.cardBackground = false
        theme.name = "Persisted full settings"; theme.customization = config
        checks["customizationRoundTrip"] = roundTrip(theme)
        do {
            try store.save(theme)
            checks["customizationSaveWithoutApply"] = store.selectedID == AppTheme.defaultID
            try store.apply(id: theme.id)
            let fresh = AppThemeStore(defaults: defaults, assets: assets)
            checks["customizationPersistReload"] = fresh.selectedTheme == theme && fresh.customThemes == [theme]
        } catch { checks["customizationPersistReload"] = false }
        checks["customizationMalformedDecodeRejected"] = [
            "{\"shelfColumns\":2.5}", "{\"coverWidth\":\"NaN\"}", "{\"tabStyle\":\"unknown\"}",
            "{\"effect\":\"unknown\"}", "{\"cardBackground\":\"false\"}"
        ].allSatisfy { raw in rejects { _ = try JSONDecoder().decode(ThemeCustomization.self, from: Data(raw.utf8)) } }
        let before = defaults.data(forKey: AppThemeStore.storageKey)
        var invalidRejected = true
        for value in [-1, 0, 1, 6, Int.max] {
            var draft = theme; draft.customization?.shelfColumns = value
            let validCheck = draft.validationMessage != nil && rejects { try store.save(draft, apply: true) }
            invalidRejected = validCheck && invalidRejected
        }
        checks["customizationColumnRangeRejected"] = invalidRejected
        invalidRejected = true
        for value in [-1.0, 0, 59.99, 180.01, 10_000, Double.nan, Double.infinity, -Double.infinity] {
            var draft = theme; draft.customization?.coverWidth = value
            let validCheck = draft.validationMessage != nil && rejects { try store.save(draft, apply: true) }
            invalidRejected = validCheck && invalidRejected
        }
        checks["customizationWidthNonfiniteRejected"] = invalidRejected
        var fontsRejected = true
        for name in [String(repeating: "a", count: 129), "Helvetica\n", "\u{0000}Helvetica", "A\tB"] {
            var draft = theme; draft.customization?.fontPostScriptName = name
            let rejected = draft.validationMessage != nil && rejects { try store.save(draft) }
            fontsRejected = rejected && fontsRejected
        }
        checks["customizationInvalidFontsRejected"] = fontsRejected
        checks["customizationInvalidSaveAtomic"] = defaults.data(forKey: AppThemeStore.storageKey) == before
            && AppThemeStore(defaults: defaults, assets: assets).selectedTheme == theme
        var endpointsPersist = true
        for columns in [2, 5] {
            for width in [60.0, 180.0] {
                for style in ThemeTabStyle.allCases {
                    for effect in ThemeInterfaceEffect.allCases {
                        var draft = theme
                        draft.customization?.shelfColumns = columns; draft.customization?.coverWidth = width
                        draft.customization?.tabStyle = style; draft.customization?.effect = effect
                        do {
                            try store.save(draft, apply: true)
                            endpointsPersist = endpointsPersist && roundTrip(draft)
                                && AppThemeStore(defaults: defaults, assets: assets).selectedTheme == draft
                        } catch { endpointsPersist = false }
                    }
                }
            }
        }
        checks["customizationEndpointsAndEnumsPersist"] = endpointsPersist
        let fontDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fontDirectory) }
        let manager = ReadingFontManager(directory: fontDirectory, defaults: defaults)
        let readingName = manager.selectedPostScriptName
        let sentinels: [String: Any] = ["fontSize": 19, "readerLineHeightTenths": 14,
            "theme": 2, AppAppearance.storageKey: 2, "probe.book.data": Data("unchanged".utf8)]
        for (key, value) in sentinels { defaults.set(value, forKey: key) }
        var fontRoundTrips = true
        for name in [nil, "", "Helvetica", "Missing-Fixture-Font"] as [String?] {
            var draft = theme; draft.customization?.fontPostScriptName = name
            do {
                try store.save(draft, apply: true)
                fontRoundTrips = fontRoundTrips && AppThemeStore(defaults: defaults, assets: assets).selectedTheme == draft
            } catch { fontRoundTrips = false }
        }
        checks["customizationFontTriStatePersists"] = fontRoundTrips
        checks["customizationReaderSettingsIsolated"] = manager.selectedPostScriptName == readingName
            && sentinels.allSatisfy { key, value in
                guard let actual = defaults.object(forKey: key) else { return false }
                return (actual as? NSObject)?.isEqual(value) == true
            }
        checks.merge(tabIconAndSliderChecks(defaults: defaults, assets: assets, store: store, theme: theme)) { _, new in new }
        return checks
    }

    /// Tab icon and glow/opacity slider contract: decode defaults for themes
    /// saved before these fields existed, key/value validation, range and
    /// finite guards, asset-ID bookkeeping and save atomicity.
    private static func tabIconAndSliderChecks(defaults: UserDefaults, assets: ThemeAssetStore,
                                               store: AppThemeStore, theme: AppTheme) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let neutral = ThemeCustomization()
        checks["customizationTabIconDefaults"] = neutral.tabIcons == nil && neutral.glowIntensity == 0.5
            && neutral.surfaceOpacity == 0.85 && roundTrip(neutral)
        func decode(_ raw: String) -> ThemeCustomization? {
            try? JSONDecoder().decode(ThemeCustomization.self, from: Data(raw.utf8))
        }
        // Snapshots written before tabIcons/glow/surfaceOpacity existed must
        // decode with the documented defaults, including explicit JSON nulls.
        let legacySettings = decode("{\"tabStyle\":\"text\"}")
        let partialIcons = decode("{\"tabIcons\":{\"shelf\":\"star.fill\"}}")
        let nullFields = decode("{\"tabIcons\":null,\"glowIntensity\":null,\"surfaceOpacity\":null}")
        checks["customizationTabIconsNilEmptyPartialDecode"] = legacySettings?.tabStyle == .text
            && legacySettings?.tabIcons == nil && legacySettings?.glowIntensity == 0.5
            && legacySettings?.surfaceOpacity == 0.85
            && partialIcons?.tabIcons == ["shelf": "star.fill"] && partialIcons?.shelfColumns == 3
            && partialIcons?.glowIntensity == 0.5 && partialIcons?.surfaceOpacity == 0.85
            && nullFields?.tabIcons == nil && nullFields?.glowIntensity == 0.5
            && nullFields?.surfaceOpacity == 0.85
        let emptyIcons = decode("{\"tabIcons\":{}}")
        checks["customizationTabIconsEmptyRejected"] = emptyIcons?.tabIcons == [:]
            && emptyIcons?.validationMessage != nil
        checks["customizationTabIconsMalformedDecodeRejected"] = [
            "{\"tabIcons\":[]}", "{\"tabIcons\":{\"shelf\":3}}", "{\"tabIcons\":\"star.fill\"}",
            "{\"glowIntensity\":\"high\"}", "{\"glowIntensity\":\"NaN\"}", "{\"surfaceOpacity\":true}"
        ].allSatisfy { raw in rejects { _ = try JSONDecoder().decode(ThemeCustomization.self, from: Data(raw.utf8)) } }
        let iconsBefore = defaults.data(forKey: AppThemeStore.storageKey)
        var iconsRejected = true
        for icons in [["unknown": "star.fill"], ["shelf": "star.fill", "extra": "book.fill"],
                      ["shelf": "../icon"], ["shelf": "bad icon"], ["shelf": ""],
                      ["shelf": "a:b"], ["shelf": String(repeating: "s", count: 129)]] {
            var draft = theme; draft.customization?.tabIcons = icons
            let check = draft.validationMessage != nil && rejects { try store.save(draft, apply: true) }
            iconsRejected = check && iconsRejected
        }
        checks["customizationTabIconKeysAndValuesRejected"] = iconsRejected
        checks["customizationTabIconInvalidSaveAtomic"] = defaults.data(forKey: AppThemeStore.storageKey) == iconsBefore
        // Validation is format-based: a valid asset ID is accepted even before
        // the file exists, exactly like the other image settings.
        let validIconID = UUID().uuidString.lowercased() + ".jpg"
        var iconsAccepted = true
        for icons in [["shelf": "star.fill"], ["statistics": validIconID],
                      ["shelf": "star.fill", "statistics": "chart.bar", "profile": validIconID]] {
            var draft = theme; draft.customization?.tabIcons = icons
            let check = draft.validationMessage == nil && roundTrip(draft)
            do { try store.save(draft, apply: true) } catch { iconsAccepted = false }
            iconsAccepted = check && iconsAccepted
        }
        checks["customizationTabIconValuesAccepted"] = iconsAccepted
        var assetTheme = theme
        assetTheme.customization?.tabIcons = ["shelf": "star.fill", "profile": validIconID]
        checks["customizationAssetIDsIncludeTabIcons"] = assetTheme.assetIDs.contains(validIconID)
            && !assetTheme.assetIDs.contains("star.fill")
        let slidersBefore = defaults.data(forKey: AppThemeStore.storageKey)
        var slidersRejected = true
        for value in [-0.01, 1.01, -1.0, 2.0, Double.nan, Double.infinity, -Double.infinity] {
            var glowDraft = theme; glowDraft.customization?.glowIntensity = value
            let glowCheck = glowDraft.validationMessage != nil && rejects { try store.save(glowDraft, apply: true) }
            var opacityDraft = theme; opacityDraft.customization?.surfaceOpacity = value
            let opacityCheck = opacityDraft.validationMessage != nil && rejects { try store.save(opacityDraft, apply: true) }
            slidersRejected = glowCheck && opacityCheck && slidersRejected
        }
        checks["customizationGlowOpacityRangeRejected"] = slidersRejected
            && defaults.data(forKey: AppThemeStore.storageKey) == slidersBefore
        var slidersPersist = true
        for value in [0.0, 0.25, 0.5, 1.0] {
            var draft = theme
            draft.customization?.glowIntensity = value
            draft.customization?.surfaceOpacity = 1 - value
            do {
                try store.save(draft, apply: true)
                slidersPersist = slidersPersist && roundTrip(draft)
                    && AppThemeStore(defaults: defaults, assets: assets).selectedTheme == draft
            } catch { slidersPersist = false }
        }
        checks["customizationGlowOpacityEndpointsPersist"] = slidersPersist
        try? store.save(theme, apply: true)
        return checks
    }

    static func png(_ color: UIColor = .magenta) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48), format: format).pngData { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        }
    }

    private static func assetChecks(root: URL, directory: URL, assets: ThemeAssetStore) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let bytes = png()
        let source = root.appendingPathComponent("source.png")
        try bytes.write(to: source, options: .atomic)
        let id = try assets.importFile(source)
        let dataID = try assets.importData(png(.cyan))
        checks["assetImportImageAndID"] = ThemeAssetStore.isValidID(id) && ThemeAssetStore.isValidID(dataID)
            && assets.image(for: id) != nil && assets.image(for: dataID) != nil
        checks["assetSourceUnchanged"] = try Data(contentsOf: source) == bytes
        try FileManager.default.removeItem(at: source)
        let fresh = ThemeAssetStore(directory: directory)
        checks["assetDurableIndependentCopy"] = fresh.image(for: id) != nil && fresh.image(for: dataID) != nil
        var theme = AppTheme.custom()
        theme.customization?.defaultCoverImage = id
        theme.customization?.launchImage = id
        theme.customization?.pageBackgroundImage = dataID
        checks["assetIDsDeduplicateAllSlots"] = theme.assetIDs == Set([id, dataID]) && roundTrip(theme)
        let survivor = root.appendingPathComponent("outside.png")
        try bytes.write(to: survivor, options: .atomic)
        let invalidIDs = ["", "../outside.png", "../../outside.png", "/tmp/outside.png", survivor.path,
                          "file://" + survivor.path, "https://example.invalid/image.png", "%2e%2e/outside.png",
                          "..\\outside.png", "not-an-asset", "a/b", "a\u{0000}b"]
        var pathsRejected = true, modelRejected = true
        for invalid in invalidIDs {
            let check = !ThemeAssetStore.isValidID(invalid) && fresh.image(for: invalid) == nil
            pathsRejected = check && pathsRejected
            fresh.remove(invalid)
            for path in [\ThemeCustomization.defaultCoverImage, \.launchImage, \.pageBackgroundImage] {
                var draft = theme; draft.customization?[keyPath: path] = invalid
                modelRejected = (draft.validationMessage != nil) && modelRejected
            }
        }
        checks["assetMalformedTraversalRejected"] = pathsRejected && fresh.image(for: nil) == nil
        checks["assetInvalidReferencesRejected"] = modelRejected
        checks["assetTraversalRemoveConfined"] = try Data(contentsOf: survivor) == bytes
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        checks["assetNonImageRejected"] = rejects { _ = try assets.importData(Data("not an image".utf8)) }
            && rejects { _ = try assets.importData(Data()) }
            && rejects { _ = try assets.importFile(root.appendingPathComponent("missing.png")) }
        // Valid PNG prefix with trailing bytes: the size guard must run even
        // when UIImage/ImageIO could otherwise decode the image successfully.
        var oversize = bytes
        oversize.append(Data(repeating: 0, count: 32 * 1024 * 1024))
        checks["assetOversizeDataRejected"] = rejects { _ = try assets.importData(oversize) }
        let huge = root.appendingPathComponent("oversize.png")
        try oversize.write(to: huge)
        checks["assetOversizeFileRejected"] = rejects { _ = try assets.importFile(huge) }
            && (try? Data(contentsOf: huge)) == oversize
        checks["assetFailedImportsLeaveNoFiles"] = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == before
        fresh.remove(id); fresh.remove(id)
        checks["assetRemoveIdempotentAndDurable"] = ThemeAssetStore(directory: directory).image(for: id) == nil
            && ThemeAssetStore(directory: directory).image(for: dataID) != nil
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let large = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format).pngData { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }
        let largeID = try assets.importData(large)
        let bitmap = ThemeAssetStore(directory: directory).image(for: largeID)?.cgImage
        checks["assetImportedDimensionsBounded"] = bitmap != nil && (bitmap?.width ?? 0) == 2000
            && (bitmap?.height ?? 0) == 1000
        let symlinkID = UUID().uuidString.lowercased() + ".jpg"
        let link = directory.appendingPathComponent(symlinkID)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: survivor)
        checks["assetSymlinkFileRejected"] = fresh.image(for: symlinkID) == nil
        fresh.remove(symlinkID)
        checks["assetSymlinkRemovalConfined"] = (try Data(contentsOf: survivor)) == bytes
            && (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil
        let linkedRoot = root.appendingPathComponent("linked-assets")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: directory)
        let linkedStore = ThemeAssetStore(directory: linkedRoot)
        let beforeLinks = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let linkedImportRejected = rejects { _ = try linkedStore.importData(bytes) }
        let linkedReadRejected = linkedStore.image(for: dataID) == nil
        linkedStore.remove(dataID)
        let afterLinks = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        checks["assetSymlinkRootRejected"] = linkedImportRejected && linkedReadRejected
            && ThemeAssetStore(directory: directory).image(for: dataID) != nil && afterLinks == beforeLinks
        checks["assetSymbolImageValidation"] = assets.symbolImage(for: "star.fill") != nil
            && assets.symbolImage(for: "book.fill") != nil
            && assets.symbolImage(for: "") == nil && assets.symbolImage(for: "bad icon") == nil
            && assets.symbolImage(for: "../icon") == nil && assets.symbolImage(for: "a:b") == nil
            && assets.symbolImage(for: "a\u{0000}b") == nil
            && assets.symbolImage(for: String(repeating: "s", count: 129)) == nil
            && assets.symbolImage(for: "not.a.symbol.name.here") == nil
            && ThemeAssetStore.isValidSymbolName("star.fill") && !ThemeAssetStore.isValidSymbolName("bad icon")
        let tabIconID = try assets.importData(png(.purple))
        var iconTheme = AppTheme.custom()
        iconTheme.customization?.tabIcons = ["shelf": "star.fill", "profile": tabIconID]
        checks["assetTabIconImportSharedPipeline"] = ThemeAssetStore.isValidID(tabIconID)
            && ThemeAssetStore(directory: directory).image(for: tabIconID) != nil
            && iconTheme.assetIDs.contains(tabIconID) && !iconTheme.assetIDs.contains("star.fill")
        try assets.remove(tabIconID)
        checks["assetTabIconCleanupSharedPipeline"] = ThemeAssetStore(directory: directory).image(for: tabIconID) == nil
        return checks
    }

    private static func cleanupChecks(defaults: UserDefaults, assets: ThemeAssetStore,
                                      directory: URL) throws -> [String: Bool] {
        defaults.removeObject(forKey: AppThemeStore.storageKey)
        var checks: [String: Bool] = [:]
        // Distinct pixels also avoid relying on whether the importer deduplicates.
        let shared = try assets.importData(png(.red))
        let old = try assets.importData(png(.green))
        let replacement = try assets.importData(png(.blue))
        let unreferenced = try assets.importData(png(.yellow))
        func exists(_ id: String) -> Bool { ThemeAssetStore(directory: directory).image(for: id) != nil }
        var a = AppTheme.custom(); a.name = "A"
        a.customization?.defaultCoverImage = shared
        a.customization?.launchImage = old
        var b = AppTheme.custom(); b.name = "B"
        b.customization?.pageBackgroundImage = shared
        let first = AppThemeStore(defaults: defaults, assets: assets)
        try first.save(a, apply: true)
        // Save B through another instance; A's stale editor must reload B before
        // computing retained IDs or it could delete B's shared reference.
        let second = AppThemeStore(defaults: defaults, assets: assets)
        try second.save(b)
        var changed = a
        changed.customization?.defaultCoverImage = replacement
        changed.customization?.launchImage = nil
        try first.save(changed)
        checks["assetReplacementCleansOnlyUnreferenced"] = !exists(old) && exists(replacement)
            && exists(shared) && exists(unreferenced) && first.customThemes.count == 2
        let before = defaults.data(forKey: AppThemeStore.storageKey)
        var invalid = changed; invalid.name = " "
        invalid.customization?.defaultCoverImage = shared
        checks["assetFailedSaveDoesNotClean"] = rejects { try first.save(invalid) }
            && defaults.data(forKey: AppThemeStore.storageKey) == before
            && exists(shared) && exists(replacement) && exists(unreferenced)
        try first.apply(id: b.id)
        checks["assetApplyDoesNotClean"] = exists(shared) && exists(replacement)
        try first.delete(id: changed.id)
        checks["assetDeletePreservesOtherTheme"] = !exists(replacement) && exists(shared)
            && first.selectedID == b.id && exists(unreferenced)
        try first.delete(id: b.id)
        checks["assetLastReferenceDeleteCleans"] = !exists(shared) && exists(unreferenced)
            && AppThemeStore(defaults: defaults, assets: assets).customThemes.isEmpty
            && AppThemeStore(defaults: defaults, assets: assets).selectedID == AppTheme.defaultID
        return checks
    }
}

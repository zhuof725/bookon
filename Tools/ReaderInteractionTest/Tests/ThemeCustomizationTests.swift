import XCTest

final class ThemeCustomizationTests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureID = ""
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(); fixtureID = UUID().uuidString
    }
    override func tearDownWithError() throws { app?.terminate() }

    private func launch(seed: Bool = true, probe: Bool = false, dark: Bool = false) {
        app.launchEnvironment["CUSTOM_THEME_FIXTURE_ID"] = fixtureID
        app.launchArguments = ["--custom-theme-mode", "--custom-theme-width-320",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if seed { app.launchArguments.append("--custom-theme-seed") }
        if probe { app.launchArguments.append("--custom-theme-model-probe") }
        if dark { app.launchArguments.append("--custom-theme-dark") }
        app.launch()
        XCTAssertTrue(app.buttons["theme.add"].waitForExistence(timeout: 10))
    }
    private func visible(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let up = element.exists && element.frame.minY < 100
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.78 : 0.35))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        visible(button); button.tap()
    }
    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.exists && button.isHittable)
        button.tap()
        XCTAssertTrue(app.textFields["theme.editor.name"].waitForExistence(timeout: 5))
    }
    private func page(_ id: String) { tap("theme.editor.row." + id) }
    private func backFromIconPicker() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.exists && button.isHittable)
        button.tap()
        XCTAssertTrue(app.buttons["theme.editor.tab.icon.shelf"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func report(_ id: String) throws -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let raw = try XCTUnwrap(probe.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }
    private func stored() throws -> [String: Any] {
        let themes = try XCTUnwrap(try report("theme.store.probe")["themes"] as? [[String: Any]])
        XCTAssertEqual(themes.count, 1)
        return try XCTUnwrap(themes.first)
    }
    private func name(_ value: String) {
        let field = app.textFields["theme.editor.name"]
        visible(field)
        let old = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Theme name must be editable across its whole row")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
        for character in value { field.typeText(String(character)) }
        XCTAssertEqual(field.value as? String, value)
        field.typeText("\n")
    }

    func testProductionModelAssetsCleanupAndRenderedEffects() throws {
        launch(probe: true)
        let result = try report("theme.model.probe")
        let required: Set<String> = [
            "customizationLegacyNil", "customizationBuiltInsUnchanged", "customizationNeutralNew",
            "customizationDefaults", "customizationPartialDecodeDefaults", "customizationMalformedDecodeRejected",
            "customizationRoundTrip", "customizationSaveWithoutApply", "customizationPersistReload",
            "customizationColumnRangeRejected", "customizationWidthNonfiniteRejected",
            "customizationInvalidFontsRejected", "customizationInvalidSaveAtomic",
            "customizationEndpointsAndEnumsPersist", "customizationFontTriStatePersists", "customizationReaderSettingsIsolated",
            "customizationTabIconDefaults", "customizationTabIconsNilEmptyPartialDecode",
            "customizationTabIconsEmptyRejected", "customizationTabIconsMalformedDecodeRejected",
            "customizationTabIconKeysAndValuesRejected", "customizationTabIconInvalidSaveAtomic",
            "customizationTabIconValuesAccepted", "customizationAssetIDsIncludeTabIcons",
            "customizationGlowOpacityRangeRejected", "customizationGlowOpacityEndpointsPersist",
            "assetImportImageAndID", "assetSourceUnchanged", "assetDurableIndependentCopy", "assetIDsDeduplicateAllSlots",
            "assetMalformedTraversalRejected", "assetInvalidReferencesRejected", "assetTraversalRemoveConfined",
            "assetNonImageRejected", "assetOversizeDataRejected", "assetOversizeFileRejected",
            "assetFailedImportsLeaveNoFiles", "assetRemoveIdempotentAndDurable", "assetImportedDimensionsBounded",
            "assetSymlinkFileRejected", "assetSymlinkRemovalConfined", "assetSymlinkRootRejected",
            "assetSymbolImageValidation", "assetTabIconImportSharedPipeline", "assetTabIconCleanupSharedPipeline",
            "assetReplacementCleansOnlyUnreferenced", "assetFailedSaveDoesNotClean", "assetApplyDoesNotClean",
            "assetDeletePreservesOtherTheme", "assetLastReferenceDeleteCleans",
            "renderTransparentSurface", "renderOpaqueSurface", "renderCardBackgroundOff",
            "renderControlsRemainOpaqueWhenCardsOff", "renderMissingFontFallback", "runtimeShelfMetricsClamp"
        ]
        XCTAssertTrue(required.isSubset(of: Set(result.keys)), "Missing checks: \(required.subtracting(result.keys))")
        for key in required { XCTAssertEqual(result[key] as? Bool, true, "Production regression: \(key)") }
        let evidence = XCTAttachment(string: String(describing: result))
        evidence.name = "customization-model-assets-render-evidence"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testSettingsSaveApplyRuntimeDockShelfCancelAndRelaunch() throws {
        launch(dark: true)
        tap("theme.add")
        XCTAssertTrue(app.textFields["theme.editor.name"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'theme.template.'")).count, 0)
        name("Full Settings")
        for row in ["tab", "shelf", "cover", "launch", "colors", "background", "effect", "cards"] {
            let element = app.buttons["theme.editor.row." + row]
            visible(element)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        }
        capture("customization-summary-eight-rows-bottom")
        page("tab"); tap("theme.editor.tab.text")
        XCTAssertTrue(app.buttons["theme.editor.tab.text"].isSelected)
        // Three per-tab icon rows: 书架/统计/我的.
        for key in ["shelf", "statistics", "profile"] {
            let row = app.buttons["theme.editor.tab.icon.\(key)"]
            visible(row)
            XCTAssertEqual(row.value as? String, "默认")
        }
        // Grid selection updates the draft and the row summary immediately.
        tap("theme.editor.tab.icon.shelf")
        let gridIcon = app.buttons["theme.editor.tab.icon.grid.star.fill"]
        XCTAssertTrue(gridIcon.waitForExistence(timeout: 5)); gridIcon.tap()
        XCTAssertTrue(gridIcon.isSelected)
        XCTAssertTrue(app.buttons["theme.editor.tab.icon.import"].exists)
        backFromIconPicker()
        XCTAssertEqual(app.buttons["theme.editor.tab.icon.shelf"].value as? String, "自定义")
        // Re-selecting the same grid icon toggles back to the default.
        tap("theme.editor.tab.icon.shelf")
        gridIcon.tap(); XCTAssertFalse(gridIcon.isSelected); backFromIconPicker()
        XCTAssertEqual(app.buttons["theme.editor.tab.icon.shelf"].value as? String, "默认")
        tap("theme.editor.tab.icon.profile")
        gridIcon.tap(); XCTAssertTrue(gridIcon.isSelected)
        // Reset restores the default icon for this tab.
        tap("theme.editor.tab.icon.reset")
        XCTAssertFalse(gridIcon.isSelected); backFromIconPicker()
        XCTAssertEqual(app.buttons["theme.editor.tab.icon.profile"].value as? String, "默认")
        // Persist one custom SF Symbol icon for the saved theme.
        tap("theme.editor.tab.icon.shelf")
        gridIcon.tap(); XCTAssertTrue(gridIcon.isSelected); backFromIconPicker()
        back()
        page("shelf")
        let stepper = app.steppers["theme.editor.shelf.columns"]
        visible(stepper)
        // Native stepper order is decrement then increment, independent of locale.
        XCTAssertEqual(stepper.buttons.count, 2)
        stepper.buttons.element(boundBy: 0).tap()
        let width = app.sliders["theme.editor.shelf.width"]
        visible(width); width.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(width.value as? String, "60 点"); back()
        page("effect"); tap("theme.editor.effect.opaque")
        XCTAssertTrue(app.buttons["theme.editor.effect.opaque"].isSelected)
        let glow = app.sliders["theme.editor.effect.glow"]
        let opacity = app.sliders["theme.editor.effect.opacity"]
        visible(glow)
        XCTAssertEqual(glow.value as? String, "50%")
        glow.adjust(toNormalizedSliderPosition: 0.75)
        XCTAssertEqual(glow.value as? String, "75%")
        opacity.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertEqual(opacity.value as? String, "60%")
        back()
        page("cards")
        let toggle = app.switches["theme.editor.cards.enabled"]
        visible(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0"); back()
        page("colors"); tap("theme.editor.font.system")
        XCTAssertTrue(app.buttons["theme.editor.font.system"].isSelected)
        tap("theme.editor.mode.dark"); back()
        capture("customization-summary-dark-native-presentation") // NOT claimed to be 320pt.
        tap("theme.editor.save")
        XCTAssertTrue(app.buttons["theme.use"].waitForExistence(timeout: 6))
        let saved = try stored()
        let config = try XCTUnwrap(saved["customization"] as? [String: Any])
        XCTAssertEqual(config["tabStyle"] as? String, "text")
        XCTAssertEqual(config["tabIcons"] as? [String: String], ["shelf": "star.fill"])
        XCTAssertEqual(config["glowIntensity"] as? Double, 0.75, accuracy: 0.01)
        XCTAssertEqual(config["surfaceOpacity"] as? Double, 0.6, accuracy: 0.01)
        XCTAssertEqual(config["shelfColumns"] as? Int, 2)
        XCTAssertEqual(config["coverWidth"] as? Double, 60)
        XCTAssertEqual(config["effect"] as? String, "opaque")
        XCTAssertEqual(config["cardBackground"] as? Bool, false)
        XCTAssertEqual(config["fontPostScriptName"] as? String, "")
        XCTAssertEqual(try report("theme.store.probe")["selectedID"] as? String, "builtin.monochrome")
        tap("theme.use")
        try assertRuntime()
        tap("theme.customize"); page("tab"); tap("theme.editor.tab.icons"); back()
        page("shelf"); visible(width); width.adjust(toNormalizedSliderPosition: 1); back()
        tap("theme.editor.cancel"); tap("theme.editor.discard")
        XCTAssertTrue(NSDictionary(dictionary: try stored()).isEqual(to: saved))
        app.terminate(); launch(seed: false, dark: true)
        XCTAssertTrue(NSDictionary(dictionary: try stored()).isEqual(to: saved))
        XCTAssertEqual(try report("theme.store.probe")["selectedID"] as? String, saved["id"] as? String)
        try assertRuntime()
    }

    func testNativeImagePickerCancelPreservesDraftAndSavedStore() throws {
        launch()
        let before = try report("theme.store.probe")
        tap("theme.add")
        name("Picker Draft")
        page("cover")
        tap("theme.editor.image.cover.import")
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "Native image document picker must present Cancel")
        capture("customization-native-image-picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["theme.editor.image.cover.import"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["theme.editor.image.cover.remove"].exists)
        back()
        XCTAssertEqual(app.textFields["theme.editor.name"].value as? String, "Picker Draft")
        tap("theme.editor.cancel"); tap("theme.editor.discard")
        XCTAssertTrue(NSDictionary(dictionary: try report("theme.store.probe")).isEqual(to: before))
    }

    private func assertRuntime() throws {
        tap("theme.preview.shelf")
        let books = (0..<3).map { app.buttons["shelf.book.customization-\($0)"] }
        XCTAssertTrue(books[0].waitForExistence(timeout: 6))
        XCTAssertEqual(app.scrollViews.firstMatch.frame.width, 320, accuracy: 2)
        XCTAssertEqual(books[0].frame.minY, books[1].frame.minY, accuracy: 2)
        XCTAssertGreaterThan(books[2].frame.minY, books[0].frame.maxY)
        XCTAssertGreaterThan(books[1].frame.minX, books[0].frame.maxX)
        for index in [1, 2, 0] {
            let id = "library.tab.\(index)"
            tap(id)
            XCTAssertTrue(app.buttons[id].isSelected)
            XCTAssertTrue(app.staticTexts["theme.runtime.callbacks"].label.contains("tab=\(index)"))
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
        }
        books[0].tap()
        XCTAssertTrue(app.staticTexts["theme.runtime.callbacks"].label.contains("opened=customization-0"))
        capture("customization-applied-dark-runtime-320")
        tap("theme.preview.back")
    }
}

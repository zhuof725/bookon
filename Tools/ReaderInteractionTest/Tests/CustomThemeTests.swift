import XCTest

final class CustomThemeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func launch(seed: Bool = true, dark: Bool = false, narrow: Bool = false,
                        clean: Bool = false, modelProbe: Bool = false) {
        app.launchArguments = [
            "--custom-theme-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        if seed { app.launchArguments.append("--custom-theme-seed") }
        if dark { app.launchArguments.append("--custom-theme-dark") }
        if narrow { app.launchArguments.append("--custom-theme-width-320") }
        if clean { app.launchArguments.append("--custom-theme-clean") }
        if modelProbe { app.launchArguments.append("--custom-theme-model-probe") }
        app.launch()
        XCTAssertTrue(app.buttons["theme.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["theme.gallery.name"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "theme.store.probe").firstMatch.waitForExistence(timeout: 6))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func visible(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            let down = element.exists && element.frame.minY < 100
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.38 : 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.78 : 0.38))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 6) {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), identifier)
        visible(element)
        element.tap()
    }

    private func replace(_ field: XCUIElement, with value: String, submit: Bool = true) {
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        visible(field)
        let old = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + value)
        if !value.isEmpty { XCTAssertEqual(field.value as? String, value) }
        // Hex onSubmit SAVES. Modal tests always pass submit:false and use
        // the explicit save/cancel buttons, including the invalid-input case.
        if submit { field.typeText("\n") }
    }

    private func section(_ name: String) {
        tap("theme.editor.section.\(name)")
        XCTAssertTrue(app.buttons["theme.editor.section.\(name)"].isSelected)
    }

    private func setHex(_ field: String, to input: String, expected: String) {
        tap("theme.editor.hex.\(field)")
        replace(app.textFields["theme.hex.input"], with: input, submit: false)
        XCTAssertTrue(app.buttons["theme.hex.save"].isEnabled)
        tap("theme.hex.save")
        let row = app.buttons["theme.editor.hex.\(field)"]
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        XCTAssertEqual(row.value as? String, expected)
    }

    private func assertRootState() {
        XCTAssertEqual(app.textFields["theme.harness.input"].value as? String, "kept")
        XCTAssertEqual(app.buttons["theme.harness.counter"].label, "计数 1")
    }

    private func editorField() -> XCUIElement {
        let field = app.textFields["theme.editor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), field.debugDescription)
        return field
    }

    private func openTemplate(_ template: String = "builtin.mist") {
        tap("theme.add")
        let templateButton = app.buttons["theme.template.\(template)"]
        XCTAssertTrue(templateButton.waitForExistence(timeout: 8), templateButton.debugDescription)
        capture("custom-theme-template-gallery")
        visible(templateButton)
        templateButton.tap()
        XCTAssertTrue(app.buttons["theme.editor.save"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["theme.editor.name"].exists)
    }

    private func createTheme(named name: String = "Forest Theme", apply: Bool = true) {
        openTemplate()
        replace(editorField(), with: name)
        section("background")
        tap("theme.editor.style.solid")
        section("colors")
        tap("theme.editor.mode.light")
        tap("theme.editor.swatch.0")
        tap("theme.editor.mode.dark")
        tap("theme.editor.swatch.5")
        capture("custom-theme-editor-dark")
        XCTAssertTrue(app.buttons["theme.editor.save"].isEnabled)
        tap("theme.editor.save")
        let nameLabel = app.staticTexts["theme.gallery.name"]
        XCTAssertTrue(nameLabel.waitForExistence(timeout: 8))
        visible(nameLabel)
        XCTAssertEqual(nameLabel.label, name)
        if apply {
            tap("theme.use")
            let selected = app.staticTexts["theme.gallery.selected"]
            visible(selected)
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", name), object: selected)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 6), .completed)
        }
    }

    private func modelReport() throws -> [String: Bool] {
        let element = app.descendants(matching: .any)
            .matching(identifier: "theme.model.probe").firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 4))
        let raw = try XCTUnwrap(element.value as? String)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        return try XCTUnwrap(JSONDecoder().decode([String: Bool].self, from: data))
    }

    private func storeReport() throws -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "theme.store.probe").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        let raw = try XCTUnwrap(probe.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }

    private func storedTheme() throws -> [String: Any] {
        let themes = try XCTUnwrap(try storeReport()["themes"] as? [[String: Any]])
        XCTAssertEqual(themes.count, 1)
        return try XCTUnwrap(themes.first)
    }

    private func assertModelProbe(file: StaticString = #filePath, line: UInt = #line) throws {
        let report = try modelReport()
        let required: Set<String> = [
            "v1MissingFieldsDecode", "v1FourFieldInitializer", "v1RoundTrip", "v1StoreLoad",
            "v1StorePreserved", "v1PaletteDefaults", "bookDataUntouched", "explicitFieldsValid",
            "explicitFieldsRoundTrip", "explicitFieldsPersistence", "explicitPaletteHexes",
            "optionalHexInvalidRejected", "explicitTextSelectionContrastRejected",
            "cardRadiusInvalidRejected", "cardRadiusEndpointsPersist", "invalidEditsDoNotPersist"
        ]
        XCTAssertTrue(required.isSubset(of: Set(report.keys)), "missing regression checks: \(required.subtracting(report.keys))")
        for (name, result) in report {
            XCTAssertTrue(result, "model check failed: \(name); report=\(report)", file: file, line: line)
        }
    }

    func testModelProbeUsesProductionStoreAndIsolatedDefaults() throws {
        launch(modelProbe: true)
        try assertModelProbe()
    }

    func testCreateApplyPersistEditCancelAndDeleteFallback() throws {
        launch()
        replace(app.textFields["theme.harness.input"], with: "kept")
        tap("theme.harness.counter")
        createTheme()
        assertRootState()
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "1")
        XCTAssertTrue(app.staticTexts["theme.live.palette"].value as? String == "Forest Theme|1F4E79")

        tap("theme.customize")
        replace(editorField(), with: "Forest Edited")
        section("background")
        tap("theme.editor.style.gradient")
        section("colors")
        tap("theme.editor.swatch.1")
        tap("theme.editor.save")
        let name = app.staticTexts["theme.gallery.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        visible(name)
        XCTAssertEqual(name.label, "Forest Edited")
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "1")
        assertRootState()
        let saved = try storedTheme()

        tap("theme.customize")
        replace(editorField(), with: "Discarded")
        section("colors")
        tap("theme.editor.swatch.2")
        tap("theme.editor.cancel")
        tap("theme.editor.discard")
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        visible(name)
        XCTAssertEqual(name.label, "Forest Edited")
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "Forest Edited")
        XCTAssertTrue(NSDictionary(dictionary: try storedTheme()).isEqual(to: saved))
        assertRootState()

        app.terminate()
        launch(seed: false)
        XCTAssertEqual(app.staticTexts["theme.gallery.name"].label, "Forest Edited")
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "1")
        XCTAssertTrue(NSDictionary(dictionary: try storedTheme()).isEqual(to: saved))
        tap("theme.delete")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "Forest Edited")
        tap("theme.delete")
        tap("theme.delete.confirm")
        let selected = app.staticTexts["theme.gallery.selected"]
        let fallback = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "经典黑白"), object: selected)
        XCTAssertEqual(XCTWaiter.wait(for: [fallback], timeout: 8), .completed)
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "0")
        XCTAssertFalse(app.buttons["theme.delete"].exists)
    }

    func testEditorLightDarkPreviewIsDraftOnly() throws {
        launch()
        openTemplate("builtin.sage")
        let preview = app.descendants(matching: .any).matching(identifier: "theme.editor.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 4))
        let modeY = app.buttons["theme.editor.mode.light"].frame.minY
        for tab in ["background", "cards", "components", "colors"] {
            section(tab)
            XCTAssertTrue(editorField().isHittable, "Name must remain near the top of \(tab)")
            XCTAssertTrue(preview.isHittable, "Preview must be visible on entering \(tab)")
            XCTAssertGreaterThanOrEqual(preview.frame.height, 120)
            XCTAssertLessThanOrEqual(preview.frame.height, 180)
            XCTAssertEqual(app.buttons["theme.editor.mode.light"].frame.minY, modeY, accuracy: 2)
            XCTAssertTrue(app.buttons["theme.editor.mode.dark"].isHittable)
            if tab == "components" { capture("custom-theme-components-preview") }
        }
        for field in ["accent", "background", "backgroundEnd", "surface", "primaryText", "secondaryText", "border", "selection"] {
            XCTAssertTrue(app.buttons["theme.editor.hex.\(field)"].exists, field)
        }
        capture("custom-theme-editor-light")
        tap("theme.editor.mode.dark")
        XCTAssertTrue(app.buttons["theme.editor.mode.dark"].isSelected)
        XCTAssertTrue((preview.value as? String)?.contains("深色") == true)
        capture("custom-theme-editor-dark-preview")
        tap("theme.editor.cancel")
        let selected = app.staticTexts["theme.gallery.selected"]
        visible(selected)
        XCTAssertEqual(selected.label, "经典黑白")
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "0")
    }

    func testHubSearchFilterAndBrowseDoesNotApply() throws {
        launch(clean: true)
        XCTAssertFalse(app.textFields["theme.harness.input"].exists)
        XCTAssertTrue(app.buttons["appearance.theme.0"].isHittable)
        capture("custom-theme-hub-clean")
        openTemplate("builtin.monochrome")
        replace(editorField(), with: "Search Custom")
        tap("theme.editor.save")
        XCTAssertTrue(app.staticTexts["theme.gallery.name"].waitForExistence(timeout: 6))
        let customID = try XCTUnwrap(try storedTheme()["id"] as? String)
        let search = app.textFields["theme.search"]
        replace(search, with: "Search Custom")
        tap("theme.filter.custom")
        XCTAssertTrue(app.buttons["theme.filter.custom"].isSelected)
        XCTAssertTrue(app.buttons["theme.browse.\(customID)"].exists)
        XCTAssertFalse(app.buttons["theme.browse.builtin.monochrome"].exists)
        tap("theme.filter.builtin")
        XCTAssertFalse(app.buttons["theme.browse.\(customID)"].exists)
        replace(search, with: "晨雾")
        tap("theme.browse.builtin.mist")
        XCTAssertEqual(app.staticTexts["theme.gallery.name"].label, "晨雾")
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "经典黑白")
        XCTAssertEqual(try storeReport()["selectedID"] as? String, "builtin.monochrome")
        XCTAssertFalse(app.buttons["theme.delete"].exists)
        replace(search, with: "")
        tap("theme.filter.all")
        XCTAssertTrue(app.buttons["theme.filter.all"].isSelected)
        visible(app.buttons["theme.browse.\(customID)"])
        XCTAssertTrue(app.buttons["theme.browse.\(customID)"].exists)
        tap("theme.browse.\(customID)")
        XCTAssertEqual(app.staticTexts["theme.gallery.name"].label, "Search Custom")
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "经典黑白")
        XCTAssertEqual(try storeReport()["selectedID"] as? String, "builtin.monochrome")
    }

    func testHexValidationCancelCardsAndIndependentDarkPersistence() throws {
        launch(clean: true)
        openTemplate("builtin.monochrome")
        replace(editorField(), with: "Exact Theme")
        tap("theme.editor.hex.accent")
        let input = app.textFields["theme.hex.input"]
        for invalid in ["GGGGGG", "80123456"] {
            replace(input, with: invalid, submit: false)
            XCTAssertFalse(app.buttons["theme.hex.save"].isEnabled)
            XCTAssertTrue(input.exists)
        }
        replace(input, with: "#6B3D57", submit: false)
        XCTAssertTrue(app.buttons["theme.hex.save"].isEnabled)
        tap("theme.hex.cancel")
        XCTAssertEqual(app.buttons["theme.editor.hex.accent"].value as? String, "1A1A1A")
        setHex("accent", to: "#1F4E79", expected: "1F4E79")
        capture("custom-theme-colors-edited-light")
        section("cards")
        let radius = app.sliders["theme.editor.cardRadius"]
        let border = app.switches["theme.editor.cardBorder"]
        visible(radius)
        radius.adjust(toNormalizedSliderPosition: 0)
        visible(border)
        border.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(border.value as? String, "0")
        setHex("surface", to: "FDFDFC", expected: "FDFDFC")
        // Re-enter the section to reset its scroll position for the screenshot.
        section("colors"); section("cards")
        capture("custom-theme-cards-edited-light")
        tap("theme.editor.mode.dark")
        XCTAssertEqual(border.value as? String, "1")
        XCTAssertEqual(app.buttons["theme.editor.hex.surface"].value as? String, "1F1F1F")
        visible(radius)
        radius.adjust(toNormalizedSliderPosition: 1)
        section("colors")
        setHex("accent", to: "#FFB9D9F2", expected: "B9D9F2")
        capture("custom-theme-colors-edited-dark")
        tap("theme.editor.mode.light")
        XCTAssertEqual(app.buttons["theme.editor.hex.accent"].value as? String, "1F4E79")
        section("cards")
        XCTAssertEqual(border.value as? String, "0")
        XCTAssertEqual(app.buttons["theme.editor.hex.surface"].value as? String, "FDFDFC")
        tap("theme.editor.save")
        XCTAssertTrue(app.staticTexts["theme.gallery.name"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "经典黑白")
        let saved = try storedTheme()
        let light = try XCTUnwrap(saved["light"] as? [String: Any])
        let dark = try XCTUnwrap(saved["dark"] as? [String: Any])
        XCTAssertEqual(light["accent"] as? String, "1F4E79")
        XCTAssertEqual(dark["accent"] as? String, "B9D9F2")
        XCTAssertEqual(light["surface"] as? String, "FDFDFC")
        XCTAssertEqual(dark["surface"] as? String, "1F1F1F")
        XCTAssertEqual((light["cardRadius"] as? NSNumber)?.doubleValue, 8)
        XCTAssertEqual((dark["cardRadius"] as? NSNumber)?.doubleValue, 30)
        XCTAssertEqual(light["cardBorder"] as? Bool, false)
        XCTAssertNil(dark["cardBorder"], "Editing light border must not write the dark override")
        tap("theme.use")
        app.terminate()
        launch(seed: false, clean: true)
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "Exact Theme")
        XCTAssertTrue(NSDictionary(dictionary: try storedTheme()).isEqual(to: saved))
        tap("theme.customize")
        section("cards")
        XCTAssertEqual(border.value as? String, "0")
        tap("theme.editor.mode.dark")
        XCTAssertEqual(border.value as? String, "1")
        capture("custom-theme-cards-persisted-dark")
        tap("theme.editor.cancel")
        XCTAssertTrue(app.staticTexts["theme.gallery.name"].waitForExistence(timeout: 6))
        XCTAssertTrue(NSDictionary(dictionary: try storedTheme()).isEqual(to: saved))
    }

    func testDark320ProductionShelfAndDetailScreens() throws {
        launch(dark: true, narrow: true)
        createTheme(named: "Narrow Theme")
        XCTAssertEqual(app.staticTexts["theme.live.palette"].value as? String, "Narrow Theme|F0C1AC")
        tap("theme.preview.shelf")
        XCTAssertTrue(app.buttons["shelf.more"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["shelf.more"].frame.width, 44, accuracy: 2)
        XCTAssertLessThan(app.buttons["shelf.more"].frame.maxX, app.frame.maxX)
        XCTAssertEqual(app.staticTexts["theme.live.palette"].value as? String, "Narrow Theme|F0C1AC")
        capture("custom-theme-dark-320-shelf")
        tap("theme.preview.back")
        tap("theme.preview.detail")
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.scrollViews.firstMatch.frame.width, 320, accuracy: 2)
        XCTAssertEqual(app.staticTexts["theme.live.palette"].value as? String, "Narrow Theme|F0C1AC")
        capture("custom-theme-dark-320-detail")
        tap("theme.preview.back")
    }
}

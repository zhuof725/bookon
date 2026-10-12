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

    private func launch(seed: Bool = true, dark: Bool = false, narrow: Bool = false) {
        app.launchArguments = [
            "--custom-theme-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        if seed { app.launchArguments.append("--custom-theme-seed") }
        if dark { app.launchArguments.append("--custom-theme-dark") }
        if narrow { app.launchArguments.append("--custom-theme-width-320") }
        app.launch()
        XCTAssertTrue(app.buttons["theme.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["theme.gallery.name"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "theme.model.probe").firstMatch.waitForExistence(timeout: 6))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func visible(_ element: XCUIElement) {
        for _ in 0..<10 {
            let frame = element.frame
            if element.exists && element.isHittable && frame.minY > 45 && frame.maxY < app.frame.maxY - 35 { return }
            let down = element.exists && frame.minY < 100
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.38 : 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.78 : 0.38))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 6) {
        let element = app.buttons[identifier]
        _ = element.waitForExistence(timeout: timeout)
        visible(element)
        element.tap()
    }

    private func replace(_ field: XCUIElement, with value: String) {
        _ = field.waitForExistence(timeout: 6)
        visible(field)
        let old = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
        for character in value { field.typeText(String(character)) }
        XCTAssertEqual(field.value as? String, value)
        field.typeText("\n")
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
        tap("theme.editor.style.solid")
        tap("theme.editor.mode.light")
        tap("theme.editor.swatch.0")
        tap("theme.editor.mode.dark")
        tap("theme.editor.swatch.5")
        tap("theme.editor.mode.dark")
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

    private func assertModelProbe(file: StaticString = #filePath, line: UInt = #line) throws {
        let report = try modelReport()
        XCTAssertFalse(report.isEmpty, "model probe returned no checks", file: file, line: line)
        for (name, result) in report {
            XCTAssertTrue(result, "model check failed: \(name); report=\(report)", file: file, line: line)
        }
    }

    func testModelProbeUsesProductionStoreAndIsolatedDefaults() throws {
        launch()
        try assertModelProbe()
    }

    func testCreateApplyPersistEditCancelAndDeleteFallback() throws {
        launch()
        replace(app.textFields["theme.harness.input"], with: "kept")
        tap("theme.harness.counter")
        createTheme()
        XCTAssertEqual(app.textFields["theme.harness.input"].value as? String, "kept")
        XCTAssertEqual(app.buttons["theme.harness.counter"].label, "计数 1")
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "1")
        XCTAssertTrue(app.staticTexts["theme.live.palette"].value as? String == "Forest Theme|1F4E79")

        tap("theme.customize")
        replace(editorField(), with: "Forest Edited")
        tap("theme.editor.style.gradient")
        tap("theme.editor.swatch.1")
        tap("theme.editor.save")
        let name = app.staticTexts["theme.gallery.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        visible(name)
        XCTAssertEqual(name.label, "Forest Edited")
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "1")

        tap("theme.customize")
        replace(editorField(), with: "Discarded")
        tap("theme.editor.swatch.2")
        tap("theme.editor.cancel")
        tap("theme.editor.discard")
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        visible(name)
        XCTAssertEqual(name.label, "Forest Edited")
        XCTAssertEqual(app.staticTexts["theme.gallery.selected"].label, "Forest Edited")

        app.terminate()
        launch(seed: false)
        XCTAssertEqual(app.staticTexts["theme.gallery.name"].label, "Forest Edited")
        XCTAssertEqual(app.staticTexts["theme.harness.custom.count"].label, "1")
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

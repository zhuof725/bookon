import XCTest

final class TocRulesTests: XCTestCase {
    private var app: XCUIApplication!
    private var suite = ""
    private let pattern = "^TEST [0-9]+$"
    private let builtIns = ["chapter", "episode", "volume-chapter", "preface", "chapter-en",
        "chapter-upper", "roman", "number", "chinese-number", "bracket-chapter",
        "bracket-title", "volume", "number-space", "equals", "dashes"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        suite = UUID().uuidString
    }
    override func tearDownWithError() throws { app?.terminate() }

    private func launch(_ options: [String] = []) {
        app.launchEnvironment["TOC_RULES_TEST_SUITE"] = suite
        app.launchArguments = ["--toc-rules-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + options
        app.launch()
        XCTAssertTrue(app.buttons["tocRules.back"].waitForExistence(timeout: 8))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            let form = app.collectionViews.firstMatch
            if form.exists { form.swipeUp(velocity: .slow) }
            else { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }
    private func replace(_ field: XCUIElement, with text: String) {
        reveal(field)
        field.tap()
        let old = field.value as? String ?? ""
        // Single-line fixtures: tap the trailing edge to place the caret at end.
        if !old.isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func openRule(_ id: String) {
        let row = app.buttons[id]
        reveal(row)
        row.tap()
        XCTAssertTrue(app.buttons["tocRules.close"].waitForExistence(timeout: 4))
    }
    private func assertGone(_ element: XCUIElement) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 4), .completed)
    }
    private func save() {
        let button = app.buttons["tocRules.save"]
        XCTAssertTrue(button.isEnabled)
        button.tap()
        assertGone(button)
    }

    private func builtin(_ suffix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "tocRules.rule.builtin." + suffix).firstMatch
    }

    func testBuiltInListCannotOpen() {
        launch()
        XCTAssertLessThan(builtin("chapter").frame.height, 100)
        capture("toc-rules-static-list")
        for suffix in builtIns {
            let row = builtin(suffix)
            reveal(row)
            XCTAssertFalse(app.buttons["tocRules.rule.builtin." + suffix].exists)
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertFalse(app.buttons["tocRules.close"].exists)
            XCTAssertFalse(app.textFields["tocRules.name"].exists)
        }
        reveal(app.buttons["tocRules.add"])
        capture("toc-rules-static-list-bottom")
        XCTAssertTrue(app.buttons["tocRules.add"].isEnabled)
    }

    func testCustomValidationPersistenceEditAndConfirmedDelete() {
        launch()
        openRule("tocRules.add")
        XCTAssertFalse(app.buttons["tocRules.save"].isEnabled)
        replace(app.textFields["tocRules.name"], with: "TEST custom")
        replace(app.textViews["tocRules.pattern"], with: "(")
        XCTAssertFalse(app.buttons["tocRules.save"].isEnabled)
        replace(app.textViews["tocRules.pattern"], with: pattern)
        replace(app.textFields["tocRules.sample"], with: "TEST 42")
        let test = app.buttons["tocRules.test"]
        reveal(test)
        test.tap()
        XCTAssertTrue(app.staticTexts["tocRules.result"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["tocRules.result"].label, "匹配成功")
        save()
        let custom = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND NOT (identifier BEGINSWITH %@)",
            "tocRules.rule.", "tocRules.rule.builtin.")).firstMatch
        reveal(custom)
        let id = custom.identifier
        XCTAssertTrue(custom.label.contains("TEST custom"))
        app.terminate()
        launch(["--toc-rules-keep"])
        openRule(id)
        XCTAssertEqual(app.textFields["tocRules.name"].value as? String, "TEST custom")
        XCTAssertEqual(app.textViews["tocRules.pattern"].value as? String, pattern)
        replace(app.textFields["tocRules.name"], with: "TEST edited")
        save()
        app.terminate()
        launch(["--toc-rules-keep"])
        openRule(id)
        XCTAssertEqual(app.textFields["tocRules.name"].value as? String, "TEST edited")
        XCTAssertEqual(app.textViews["tocRules.pattern"].value as? String, pattern)
        reveal(app.buttons["tocRules.delete"])
        app.buttons["tocRules.delete"].tap()
        let confirmation = app.alerts["删除自定义规则？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 4))
        confirmation.buttons["取消"].tap()
        XCTAssertTrue(app.buttons[id].exists, "Cancel must preserve the rule")
        openRule(id)
        reveal(app.buttons["tocRules.delete"])
        app.buttons["tocRules.delete"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 4))
        confirmation.buttons["删除"].tap()
        assertGone(app.buttons[id])
        app.terminate()
        launch(["--toc-rules-keep"])
        reveal(app.buttons["tocRules.add"])
        XCTAssertFalse(app.buttons[id].exists, "Deletion must survive screen recreation")
        XCTAssertTrue(builtin("dashes").exists)
    }

    func testDarkListScreenshot() {
        launch(["--toc-rules-dark"])
        XCTAssertTrue(builtin("chapter").exists)
        capture("toc-rules-04-dark-list")
        reveal(app.buttons["tocRules.add"])
        XCTAssertTrue(builtin("dashes").exists)
        capture("toc-rules-05-dark-list-bottom")
    }
}

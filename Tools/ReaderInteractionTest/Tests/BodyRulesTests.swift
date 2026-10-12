import XCTest

final class BodyRulesTests: XCTestCase {
    private var app: XCUIApplication!
    private var suite = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        suite = UUID().uuidString
    }
    override func tearDownWithError() throws { app?.terminate() }

    private func launch(_ options: [String] = []) {
        app.launchEnvironment["BODY_RULES_TEST_SUITE"] = suite
        app.launchArguments = ["--body-rules-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + options
        app.launch()
        XCTAssertTrue(app.buttons["bodyRules.back"].waitForExistence(timeout: 8))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            // Drag along the outer form gutter, not inside a nested TextEditor.
            let down = element.exists && element.frame.maxY < app.frame.height * 0.25
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: down ? 0.35 : 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: down ? 0.75 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }
    private func replace(_ id: String, with text: String) {
        let field = app.textViews[id]
        reveal(field)
        field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty {
            // Fixtures stay on one line; tap the trailing edge before deleting.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        var typed = ""
        for character in text {
            field.typeText(String(character))
            typed.append(character)
            let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", typed), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 3), .completed)
        }
        XCTAssertEqual(field.value as? String, text)
        let hide = app.buttons["bodyRules.hideKeyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 4))
        hide.tap()
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
    private func assertGone(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    private func open(_ id: String) {
        let row = app.buttons[id]
        reveal(row)
        row.tap()
        XCTAssertTrue(app.buttons["bodyRules.close"].waitForExistence(timeout: 4))
    }
    private func save() {
        let button = app.buttons["bodyRules.save"]
        XCTAssertTrue(button.isEnabled)
        button.tap()
        assertGone(button)
    }
    private func preview(_ expected: String) {
        let button = app.buttons["bodyRules.test"]
        reveal(button)
        XCTAssertTrue(button.isEnabled)
        button.tap()
        let result = app.staticTexts["bodyRules.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        reveal(result)
        XCTAssertEqual(result.label, expected)
    }
    private var firstRule: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bodyRules.rule.")).firstMatch
    }

    func testLiteralPreviewSaveToggleAndRelaunchInDarkMode() {
        launch()
        XCTAssertTrue(app.staticTexts["bodyRules.empty"].exists)
        open("bodyRules.add")
        XCTAssertFalse(app.buttons["bodyRules.save"].isEnabled)
        replace("bodyRules.name", with: "Literal test")
        replace("bodyRules.pattern", with: "a.b")
        replace("bodyRules.replacement", with: "$1")
        replace("bodyRules.sample", with: "a.b aXb a.b")
        preview("$1 aXb $1")
        capture("body-rules-01-light-literal-preview")
        save()
        reveal(firstRule)
        let id = firstRule.identifier
        XCTAssertTrue(firstRule.label.contains("Literal test"))
        let toggleID = id.replacingOccurrences(of: "bodyRules.rule.", with: "bodyRules.enabled.")
        let toggle = app.switches[toggleID]
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        capture("body-rules-02-light-disabled-list")
        app.terminate()
        launch(["--body-rules-keep", "--body-rules-dark"])
        XCTAssertTrue(app.buttons[id].exists)
        XCTAssertEqual(app.switches[toggleID].value as? String, "0")
        capture("body-rules-03-dark-persisted-list")
        open(id)
        XCTAssertEqual(app.textViews["bodyRules.name"].value as? String, "Literal test")
        XCTAssertEqual(app.switches["bodyRules.enabled"].value as? String, "0")
        XCTAssertEqual(app.switches["bodyRules.regex"].value as? String, "0")
        let pattern = app.textViews["bodyRules.pattern"]
        reveal(pattern)
        XCTAssertEqual(pattern.value as? String, "a.b")
        let replacement = app.textViews["bodyRules.replacement"]
        reveal(replacement)
        XCTAssertEqual(replacement.value as? String, "$1")
        app.buttons["bodyRules.close"].tap()
        assertGone(app.buttons["bodyRules.close"])
        app.switches[toggleID].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.terminate()
        launch(["--body-rules-keep"])
        XCTAssertEqual(app.switches[toggleID].value as? String, "1", "Re-enabling must persist")
    }

    func testInvalidRegexCapturePreviewAndConfirmedDeletion() {
        launch()
        open("bodyRules.add")
        replace("bodyRules.name", with: "Regex test")
        let regex = app.switches["bodyRules.regex"]
        reveal(regex)
        regex.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        replace("bodyRules.pattern", with: "(")
        XCTAssertFalse(app.buttons["bodyRules.save"].isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "正则表达式无效")).firstMatch.exists)
        capture("body-rules-04-invalid-regex")
        replace("bodyRules.pattern", with: "(cat)")
        XCTAssertTrue(app.buttons["bodyRules.save"].isEnabled)
        replace("bodyRules.replacement", with: "$1!")
        replace("bodyRules.sample", with: "cat dog")
        preview("cat! dog")
        save()
        reveal(firstRule)
        let id = firstRule.identifier
        app.terminate()
        launch(["--body-rules-keep"])
        open(id)
        XCTAssertEqual(app.switches["bodyRules.regex"].value as? String, "1")
        reveal(app.buttons["bodyRules.delete"])
        app.buttons["bodyRules.delete"].tap()
        let alert = app.alerts["删除正文替换规则？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 4))
        alert.buttons["取消"].tap()
        XCTAssertTrue(app.buttons[id].exists)
        open(id)
        reveal(app.buttons["bodyRules.delete"])
        app.buttons["bodyRules.delete"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 4))
        alert.buttons["删除"].tap()
        assertGone(app.buttons[id])
        app.terminate()
        launch(["--body-rules-keep"])
        XCTAssertTrue(app.staticTexts["bodyRules.empty"].exists)
        XCTAssertFalse(app.buttons[id].exists)
    }
}

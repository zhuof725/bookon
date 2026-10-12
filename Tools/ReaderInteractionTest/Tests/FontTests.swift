import XCTest

final class FontTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app?.terminate() }

    private func launch(_ scenario: String) {
        app.launchArguments = ["--font-mode", "--font-scenario", scenario,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["font.fixture.run"].waitForExistence(timeout: 10))
    }

    private func runAndAssert(_ scenario: String, file: StaticString = #filePath, line: UInt = #line) {
        launch(scenario)
        app.buttons["font.fixture.run"].tap()
        let report = app.staticTexts["font.fixture.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 12), file: file, line: line)
        let predicate = NSPredicate(format: "label CONTAINS %@", "\"ok\":true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed,
                       report.label, file: file, line: line)
        XCTAssertFalse(report.label.contains("\"failed\":0") == false,
                       report.label, file: file, line: line)
    }

    /// Real TTF import, byte duplicate, persistence, invalid/corrupt rollback,
    /// missing-file recovery, selected removal and source immutability.
    func testFontRepositoryImportPersistenceAndRollback() { runAndAssert("repository") }

    /// OTF and TTC are intentionally separate simulator processes: CoreText
    /// process registration names otherwise make cross-scenario collision tests
    /// ambiguous. TTC asserts both embedded faces create usable UIFonts.
    func testOpenTypeContainerFaces() { runAndAssert("otf") }
    func testTrueTypeCollectionFaces() { runAndAssert("ttc") }

    /// Uses the actual shared resolver, TextKit CommentTextView, ChapterTitleLayout
    /// and ReaderPaginator. This is a compact four-state report (system/Sans/Wide/
    /// system), with source UTF-16 reconstruction and comment attachment checks.
    func testReadingPipelineFontIdentityAndPagination() { runAndAssert("engine") }

    private func reveal(_ element: XCUIElement, upward: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if upward { scroll.swipeUp(velocity: .slow) }
            else { scroll.swipeDown(velocity: .slow) }
        }
        XCTAssertTrue(element.isHittable, element.debugDescription)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testProductionFontManagerViewSelectionAndDeletion() {
        launch("ui")
        let current = app.staticTexts["fonts.current"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let sans = app.buttons["fonts.choice.LegadoFixtureSans-Regular"]
        XCTAssertTrue(sans.waitForExistence(timeout: 10))
        XCTAssertTrue(current.label.contains("系统默认"))

        capture("font-management-light")
        reveal(sans)
        sans.tap()
        XCTAssertEqual(waitLabel(current, contains: "LegadoFixtureSans-Regular"), true)
        XCTAssertEqual(app.buttons["fonts.choice.LegadoFixtureSans-Regular"].value as? String, "已选择")

        reveal(app.buttons["fonts.system"], upward: false)
        app.buttons["fonts.system"].tap()
        XCTAssertEqual(waitLabel(current, contains: "系统默认"), true)
        XCTAssertEqual(app.buttons["fonts.system"].value as? String, "已选择")

        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fonts.delete.")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 6))
        reveal(delete)
        delete.tap()
        let alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["取消"].tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Cancel must preserve imported file")
        XCTAssertTrue(sans.exists)

        reveal(delete)
        delete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["移除字体文件"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fonts.empty").firstMatch.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["fonts.system"].exists)
        XCTAssertFalse(delete.exists)

        // One dark screenshot is sufficient to catch production contrast/layout
        // regressions without automating the platform fileImporter itself.
        let appearance = app.buttons["font.fixture.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 4))
        appearance.tap()
        let dark = XCTAttachment(screenshot: app.screenshot())
        dark.name = "font-management-dark"
        dark.lifetime = .keepAlways
        add(dark)
        reveal(app.staticTexts["fonts.current"], upward: false)
        XCTAssertTrue(app.staticTexts["fonts.current"].exists)
    }

    @discardableResult
    private func waitLabel(_ element: XCUIElement, contains text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}

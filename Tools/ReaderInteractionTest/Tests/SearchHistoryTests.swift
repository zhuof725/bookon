import XCTest

final class SearchHistoryTests: XCTestCase {
    private var app: XCUIApplication!
    private var suite = ""
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        suite = UUID().uuidString
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws { app.terminate() }
    private func launch() {
        app.launchEnvironment["SEARCH_HISTORY_SUITE"] = suite
        app.launchArguments = ["--search-history-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["fixture.submit"].waitForExistence(timeout: 8))
    }
    private func expect(_ id: String, _ value: String) {
        let element = app.staticTexts[id]
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed)
    }
    private func submit(_ text: String) {
        let field = app.textFields["fixture.draft"]
        field.tap()
        field.typeText(text)
        app.buttons["fixture.submit"].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testSubmittedOnlyRestartDedupAndRealSheetCallback() {
        launch()
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].exists)
        let field = app.textFields["fixture.draft"]
        field.tap(); field.typeText("Unsubmitted")
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].exists)
        app.terminate(); launch()
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].exists)
        submit("   ")
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].exists)
        submit("  Dune  ")
        submit("Foundation")
        submit("dUNE")
        expect("fixture.entries", "dUNE|Foundation")
        app.terminate(); launch()
        expect("fixture.entries", "dUNE|Foundation")
        capture("history-restarted")
        app.buttons["fixture.sheet"].tap()
        let query = app.buttons["searchHistory.query.Foundation"]
        XCTAssertTrue(query.waitForExistence(timeout: 4))
        capture("history-production-sheet")
        query.tap()
        expect("fixture.selected", "Foundation")
        expect("fixture.entries", "Foundation|dUNE")
        app.terminate(); launch()
        expect("fixture.entries", "Foundation|dUNE")
    }
    func testDeleteClearCancelConfirmAndRestart() {
        launch()
        submit("Dune"); submit("Foundation")
        app.terminate(); launch()
        app.buttons["searchHistory.delete.Dune"].tap()
        expect("fixture.entries", "Foundation")
        app.terminate(); launch()
        expect("fixture.entries", "Foundation")
        app.buttons["searchHistory.clear"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3))
        capture("history-clear-confirmation")
        app.buttons["取消"].tap()
        expect("fixture.entries", "Foundation")
        app.buttons["searchHistory.clear"].tap()
        app.buttons["清空全部记录"].tap()
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].waitForExistence(timeout: 3))
        app.terminate(); launch()
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].exists)
        capture("history-cleared-restarted")
    }
    func testProductionModelLimitNormalizationAndReload() {
        launch()
        app.buttons["fixture.check"].tap()
        expect("fixture.report", "PASS 8 model checks")
        XCTAssertTrue(app.staticTexts["searchHistory.empty"].exists)
        capture("history-model-checks")
    }
}

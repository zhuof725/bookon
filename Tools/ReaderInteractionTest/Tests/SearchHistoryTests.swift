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
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 4))
        let matches = app.buttons.matching(identifier: "searchHistory.query.Foundation")
        let visible = matches.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(visible.count, 1, "Only the sheet row should be tappable")
        capture("history-production-sheet")
        visible.first!.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["完成"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
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
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 6))
        capture("history-clear-confirmation")
        app.buttons["取消"].tap()
        expect("fixture.entries", "Foundation")
        app.buttons["searchHistory.clear"].tap()
        // 系统 alert 里的按钮在无障碍树里会出现一层嵌套的重复元素，取第一个。
        app.buttons["清空全部记录"].firstMatch.tap()
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

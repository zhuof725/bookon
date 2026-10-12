import XCTest

final class AppFontTests: XCTestCase {
    func testLiveProductionScreensAndRootFields() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--app-font-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["appfont.next"].waitForExistence(timeout: 15))
        let report = app.staticTexts["appfont.report"]
        for stage in 0..<3 {
            let expected = NSPredicate(format: "label CONTAINS %@", "PASS stage=\(stage)")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: report)], timeout: 8), .completed, report.label)
            XCTAssertEqual(app.textFields["appfont.field"].value as? String, "Root field ABC 123")
            capture(app, "app-font-shelf-stage-\(stage)")
            app.buttons["appfont.page"].tap()
            XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
            capture(app, "app-font-detail-stage-\(stage)")
            app.buttons["appfont.page"].tap()
            if stage < 2 { app.buttons["appfont.next"].tap() }
        }
        app.buttons["appfont.next"].tap()
        app.buttons["appfont.size"].tap()
        capture(app, "app-font-accessibility-size")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

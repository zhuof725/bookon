import XCTest

final class LiveAppearanceTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { app.terminate() }
    private func start(_ route: String) {
        app.launchArguments = [route, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testEverySettingHasCorrespondingLivePreviewAndDraftUpdates() {
        start("--live-appearance-mode")
        let summary = app.staticTexts["theme.preview.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("3列"))
        app.buttons["fixture.change"].tap()
        XCTAssertTrue(summary.label.contains("2列")); XCTAssertTrue(summary.label.contains("60pt"))
        for page in ["tab", "shelf", "cover", "launch", "colors", "background", "effect", "cards"] {
            app.buttons["fixture.pages"].tap()
            app.buttons["fixture.page." + page].tap()
            let preview = app.descendants(matching: .any).matching(identifier: "theme.preview.live." + page).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 5), page)
            XCTAssertGreaterThan(preview.frame.height, 100)
            XCTAssertLessThan(preview.frame.maxY, app.frame.height - 60)
            if page == "effect" {
                XCTAssertTrue(summary.label.contains("20%")); XCTAssertTrue(summary.label.contains("60%"))
                shot("live-effect-preview")
            }
            if page == "cards" { XCTAssertTrue(summary.label.contains("30pt")); shot("live-card-preview") }
        }
    }
    func testLaunchHasNoSkipAndAutomaticallyReturnsTwice() {
        start("--live-appearance-mode")
        XCTAssertTrue(app.buttons["fixture.splash"].waitForExistence(timeout: 10))
        for i in 1...2 {
            app.buttons["fixture.splash"].tap()
            XCTAssertFalse(app.buttons["theme.launch.skip"].exists)
            XCTAssertFalse(app.buttons["跳过"].exists)
            let closed = app.staticTexts["fixture.closed"]
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(i)"), object: closed)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 6), .completed)
            XCTAssertTrue(app.buttons["fixture.splash"].isHittable)
        }
    }
    func testNativeListRowsRemainIndependentAndTappable() {
        start("--independent-rows-mode")
        let a = app.buttons["independent.row.0"], b = app.buttons["independent.row.1"]
        XCTAssertTrue(a.waitForExistence(timeout: 10)); XCTAssertTrue(b.exists)
        XCTAssertGreaterThanOrEqual(b.frame.minY, a.frame.maxY)
        a.tap(); b.tap(); XCTAssertEqual(app.staticTexts["independent.count"].label, "2")
        shot("independent-native-list-cards")
    }
}

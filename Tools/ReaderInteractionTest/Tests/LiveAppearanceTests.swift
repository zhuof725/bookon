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
    private func open(_ page: String) {
        app.buttons["fixture.pages"].tap()
        app.buttons["fixture.page." + page].tap()
    }
    /// Rolled back: no pinned per-setting preview surface remains on any page.
    func testAppearanceSubpagesHaveNoLivePreviewSurface() {
        start("--live-appearance-mode")
        XCTAssertTrue(app.buttons["fixture.pages"].waitForExistence(timeout: 10))
        for page in ["tab", "shelf", "cover", "launch", "colors", "background", "effect", "cards"] {
            open(page)
            XCTAssertTrue(app.descendants(matching: .any)
                .matching(identifier: "theme.editor.page." + page).firstMatch.waitForExistence(timeout: 6), page)
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'theme.preview.live.'")).firstMatch.exists,
                "Live preview surface must be gone on \(page)")
            XCTAssertFalse(app.staticTexts["theme.preview.summary"].exists)
        }
        shot("appearance-subpage-without-pinned-preview")
    }
    /// Controls on the pages that lost the preview must still edit the draft.
    func testAppearanceControlsStillEditWithoutPreview() {
        start("--live-appearance-mode")
        open("shelf")
        let stepper = app.steppers["theme.editor.shelf.columns"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 8))
        XCTAssertEqual(stepper.value as? String, "3")
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(stepper.value as? String, "4")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'theme.preview.live.'")).firstMatch.exists)
        open("effect")
        XCTAssertTrue(app.buttons["theme.editor.effect.transparent"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.sliders["theme.editor.effect.glow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'theme.preview.live.'")).firstMatch.exists)
        // The pre-existing bottom summary preview stays available on this page.
        let legacy = app.descendants(matching: .any).matching(identifier: "theme.editor.tab.preview").firstMatch
        open("tab")
        XCTAssertTrue(legacy.waitForExistence(timeout: 6))
        shot("appearance-tab-legacy-preview")
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
            let interactive = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["fixture.splash"])
            XCTAssertEqual(XCTWaiter.wait(for: [interactive], timeout: 6), .completed)
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

import XCTest

final class SettingsGlassTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { app.terminate() }
    private func launch(_ extras: [String] = []) {
        app.launchArguments = ["--settings-glass-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extras
        app.launch()
    }
    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name
        item.lifetime = .keepAlways; add(item)
    }
    func testReferenceRowsKeepExistingLabelsAndCallbacks() {
        launch()
        let first = app.buttons["settings.row.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(first.frame.height, 56)
        let next = app.buttons["settings.row.1"]
        XCTAssertGreaterThanOrEqual(next.frame.minY - first.frame.maxY, 7)
        XCTAssertLessThanOrEqual(next.frame.minY - first.frame.maxY, 10)
        XCTAssertEqual(first.frame.minX, next.frame.minX, accuracy: 1)
        shot("reference-glass-settings-light")
        first.tap()
        XCTAssertEqual(app.staticTexts["settings.callback"].label, "书源管理")
        next.tap()
        XCTAssertEqual(app.staticTexts["settings.callback"].label, "目录规则")
        for title in ["历史记录", "我的收藏", "稍后再看", "我的订阅", "感谢你们的赞助！", "关于 MiniBili"] {
            XCTAssertFalse(app.staticTexts[title].exists, "Reference content must not become fake app features")
        }
    }
    func testDarkNarrowAccessibilityRowsRemainUsable() {
        launch(["--settings-dark", "--settings-large"])
        let first = app.buttons["settings.row.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(first.frame.width, 273)
        XCTAssertGreaterThan(first.frame.height, 56)
        XCTAssertGreaterThanOrEqual(first.frame.minX, 0)
        XCTAssertLessThanOrEqual(first.frame.maxX, app.frame.maxX)
        first.tap()
        XCTAssertEqual(app.staticTexts["settings.callback"].label, "书源管理")
        shot("reference-glass-settings-dark-large320")
    }
}

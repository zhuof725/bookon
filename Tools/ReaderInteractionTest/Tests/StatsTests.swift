import XCTest

/// 统计页（阅读目标）视觉回归：截图供与参考设计逐项比对。
final class StatsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--stats-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["stats.date"].waitForExistence(timeout: 10), "统计页没有出现")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadingGoalsPageScreenshots() {
        XCTAssertTrue(app.staticTexts["stats.todayClock"].exists)
        XCTAssertTrue(app.buttons["stats.dailyGoal"].exists)
        capture("stats-01-top")

        app.swipeUp()
        capture("stats-02-streak-yearly")

        app.swipeUp()
        capture("stats-03-plans")

        app.swipeUp()
        capture("stats-04-chart")

        // 分段控件在最后一张卡片顶部；滚到底后再切换 30 天。
        let month = element("stats.range.month")
        if month.waitForExistence(timeout: 3) {
            month.tap()
            capture("stats-05-month")
        }
    }

    func testChartComponentsWithData() {
        app.terminate()
        app.launchArguments = ["--stats-data-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["有数据：近 7 天"].waitForExistence(timeout: 8))
        capture("stats-data-01-week")
        app.swipeUp()
        capture("stats-data-02-month")
        app.swipeUp()
        capture("stats-data-03-year-plan")
    }

    func testMonthRangeScreenshot() {
        app.terminate()
        app.launchArguments = ["--stats-mode", "--stats-month", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["stats.date"].waitForExistence(timeout: 8))
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        capture("stats-06-month")
    }
}

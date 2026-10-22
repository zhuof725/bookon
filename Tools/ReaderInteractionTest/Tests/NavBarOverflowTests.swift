import XCTest

/// 导航栏右上角「登录 / 分类」不能和长标题重合：
/// 之前标签被压成竖排、溢出玻璃胶囊盖在标题上。
final class NavBarOverflowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws { app.terminate() }

    private func launch(_ mode: String) {
        app.launchArguments = ["--nav-bar-mode=\(mode)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["harness.nav.category"].waitForExistence(timeout: 8))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongTitleKeepsButtonsHorizontalAndClear() {
        launch("long")
        let login = app.buttons["harness.nav.login"]
        let category = app.buttons["harness.nav.category"]
        XCTAssertTrue(login.exists)
        XCTAssertTrue(category.exists)

        // 竖排时标签宽度只剩一个字（~20pt）；单行「登录 + 图标」应 >= 48pt。
        XCTAssertGreaterThanOrEqual(login.frame.width, 48, "登录按钮被压窄（文字可能竖排）")
        XCTAssertGreaterThanOrEqual(category.frame.width, 48, "分类按钮被压窄（文字可能竖排）")
        XCTAssertLessThanOrEqual(login.frame.height, 60)
        XCTAssertLessThanOrEqual(category.frame.height, 60)

        // 两个按钮互不重叠，且都在屏幕内。
        XCTAssertLessThanOrEqual(login.frame.maxX, category.frame.minX + 0.5, "两个按钮重叠")
        XCTAssertGreaterThanOrEqual(login.frame.minX, 0)
        XCTAssertLessThanOrEqual(category.frame.maxX, app.windows.firstMatch.frame.width + 0.5)

        // 导航栏里的标题不能盖到按钮上。
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.exists)
        let titles = navBar.staticTexts.allElementsBoundByIndex
        XCTAssertFalse(titles.isEmpty, "导航栏里没有标题")
        for text in titles where text.exists {
            let frame = text.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            XCTAssertFalse(frame.intersects(login.frame), "标题「\(text.label)」压住了登录按钮")
            XCTAssertFalse(frame.intersects(category.frame), "标题「\(text.label)」压住了分类按钮")
        }
        capture("navbar-long-title")
    }

    func testShortTitleLayoutStillFine() {
        launch("short")
        let login = app.buttons["harness.nav.login"]
        let category = app.buttons["harness.nav.category"]
        XCTAssertGreaterThanOrEqual(login.frame.width, 48)
        XCTAssertGreaterThanOrEqual(category.frame.width, 48)
        XCTAssertLessThanOrEqual(login.frame.maxX, category.frame.minX + 0.5)
        capture("navbar-short-title")
    }
}

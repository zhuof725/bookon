import XCTest

final class AppearanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func launch(reset: Bool = false) {
        app.launchArguments = ["--appearance-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if reset { app.launchArguments.append("--appearance-reset") }
        app.launch()
        let value = app.staticTexts["appearance.current.value"]
        for _ in 0..<6 where !value.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["appearance.theme.0"].waitForExistence(timeout: 8))
    }

    private func select(rawValue: Int, title: String) {
        let button = app.buttons["appearance.theme.\(rawValue)"]
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
        let value = app.staticTexts["appearance.current.value"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", title), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed)
        XCTAssertTrue(button.isSelected)
    }

    func testThemeSelectionAndPersistenceAcrossRelaunch() throws {
        launch(reset: true)
        XCTAssertEqual(app.staticTexts["appearance.current.value"].label, "跟随系统")

        select(rawValue: 2, title: "深色")
        XCTAssertEqual(app.staticTexts["appearance.current.value"].label, "深色")

        app.terminate()
        launch()
        XCTAssertEqual(app.staticTexts["appearance.current.value"].label, "深色")
        XCTAssertTrue(app.buttons["appearance.theme.2"].isSelected)

        select(rawValue: 1, title: "浅色")
        select(rawValue: 0, title: "跟随系统")
    }
}

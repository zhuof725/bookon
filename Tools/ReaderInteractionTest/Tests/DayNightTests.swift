import XCTest

/// 阅读设置：日间 / 夜间各自保存背景、字号与边距，切换整套生效并跨启动保留。
final class DayNightTests: XCTestCase {
    func testDayAndNightKeepSeparateLayouts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--day-night-mode", "--reset-day-night"]
        app.launch()

        let state = app.staticTexts["day-night-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertEqual(state.label, "mode=0 theme=0 font=20 left=20")

        let day = app.buttons["日间"]
        let night = app.buttons["夜间"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertTrue(night.exists)

        // 夜间默认：夜间背景（3）、排版沿用日间。
        night.tap()
        XCTAssertTrue(stateIs(state, "mode=1 theme=3 font=20 left=20"), state.label)
        XCTAssertTrue(app.buttons["reader.theme.3"].exists)
        XCTAssertTrue(app.buttons["reader.theme.4"].exists)
        XCTAssertFalse(app.buttons["reader.theme.0"].exists, "夜间只应显示深色背景")

        // 夜间改成自己的字号、边距与纯黑背景。
        app.buttons["day-night-font-plus"].tap()
        app.buttons["day-night-font-plus"].tap()
        app.buttons["day-night-left-plus"].tap()
        app.buttons["reader.theme.4"].tap()
        XCTAssertTrue(stateIs(state, "mode=1 theme=4 font=22 left=21"), state.label)

        // 切回日间：还是原来那一套，不受夜间改动影响。
        day.tap()
        XCTAssertTrue(stateIs(state, "mode=0 theme=0 font=20 left=20"), state.label)
        XCTAssertTrue(app.buttons["reader.theme.0"].exists)
        XCTAssertFalse(app.buttons["reader.theme.3"].exists, "日间只应显示浅色背景")

        // 再切回夜间：刚才的 22pt / 21pt / 纯黑仍在。
        night.tap()
        XCTAssertTrue(stateIs(state, "mode=1 theme=4 font=22 left=21"), state.label)
        XCTAssertTrue(app.buttons["reader.theme.4"].exists)

        // 重启后仍是夜间那套。
        app.terminate()
        app.launchArguments = ["--day-night-mode"]
        app.launch()
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertEqual(state.label, "mode=1 theme=4 font=22 left=21")
        let restoredNight = app.buttons["夜间"]
        XCTAssertTrue(restoredNight.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredNight.isSelected)
    }

    private func stateIs(_ element: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
}

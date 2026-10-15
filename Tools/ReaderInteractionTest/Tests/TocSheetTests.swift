import XCTest

/// 目录页：书源时间显示、已缓存标识、预缓存进度条（完成/失败重试/停止）。
/// 全部离线运行：合成章节与合成预缓存服务，不访问网络与真实缓存。
final class TocSheetTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reader-toc-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["reader.toc.precache"].waitForExistence(timeout: 10))
        return app
    }

    private func row(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.buttons["reader.toc.row.\(index)"]
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 8) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "等待 \(element.identifier) 变为「\(value)」超时")
    }

    private func waitForLabel(_ element: XCUIElement, contains fragment: String, timeout: TimeInterval = 25) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "等待 \(element.identifier) 包含「\(fragment)」超时")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// ① 时间显示 + ④ 已缓存标识。
    func testRowsShowSourceTimeAndCacheMarks() {
        let app = launch()
        let first = row(app, 1)
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(first.label.contains("语言课1"), first.label)
        XCTAssertTrue(first.label.contains("2026-10-01"), "目录行应显示书源更新时间：\(first.label)")
        waitForValue(row(app, 5), "已缓存")
        XCTAssertTrue(row(app, 5).label.contains("3分钟前"), row(app, 5).label)
        XCTAssertTrue(row(app, 9).label.contains("2026-09-30 12:00"), row(app, 9).label)
        XCTAssertEqual(row(app, 9).value as? String, "已缓存")
        XCTAssertEqual(row(app, 12).value as? String, "已缓存", "VIP 章节同样显示缓存标识")
        XCTAssertEqual(row(app, 3).value as? String, "未缓存")
        XCTAssertFalse(row(app, 2).label.contains("2026"), "没有时间的章节不显示时间：\(row(app, 2).label)")
        XCTAssertFalse(row(app, 2).label.contains("分钟"), row(app, 2).label)
        capture(app, "reader-toc-rows")
        row(app, 7).tap()
        XCTAssertEqual(app.staticTexts["reader.toc.harness.selection"].label, "selected=7")
    }

    /// ③ 预缓存完成窗口并跳过已缓存章节。
    func testPrecacheProgressCompletesWindowAndSkipsCached() {
        let app = launch()
        waitForValue(row(app, 5), "已缓存")
        app.buttons["reader.toc.precache"].tap()
        let status = app.staticTexts["reader.toc.precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("正在预缓存"), status.label)
        XCTAssertTrue(app.progressIndicators["reader.toc.precache.bar"].exists, "预缓存应显示进度条")
        capture(app, "reader-toc-precache-running")
        waitForLabel(status, contains: "预缓存完成")
        // 可见行已获得缓存标识（List 懒加载，不可见的行 22 无法断言）。
        XCTAssertEqual(row(app, 12).value as? String, "已缓存")
        // 20 章窗口里有 3 章打开前已缓存：不应重复请求书源。
        XCTAssertEqual(app.staticTexts["reader.toc.harness.loads"].label, "loads=17")
        capture(app, "reader-toc-precache-finished")
    }

    /// ③ 预缓存失败即停并保留进度，重试从失败处续跑。
    func testPrecacheFailureStopsAndRetryResumes() {
        let app = launch(["--reader-toc-fail=15"])
        waitForValue(row(app, 5), "已缓存")
        app.buttons["reader.toc.precache"].tap()
        let status = app.staticTexts["reader.toc.precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "进度状态应出现")
        waitForLabel(status, contains: "预缓存中断")
        XCTAssertTrue(status.label.contains("书源暂时拒绝访问"), status.label)
        XCTAssertTrue(app.buttons["reader.toc.precache.retry"].exists, "中断后应提供重试")
        capture(app, "reader-toc-precache-failed")
        app.buttons["reader.toc.precache.retry"].tap()
        waitForLabel(status, contains: "预缓存完成")
        // 首次 9 次成功 + 失败一次后重试补 8 章；重试不重复请求已缓存章节。
        XCTAssertEqual(app.staticTexts["reader.toc.harness.loads"].label, "loads=17")
    }

    /// ③ 预缓存可停止并关闭进度提示。
    func testPrecacheCanBeStoppedAndDismissed() {
        let app = launch()
        app.buttons["reader.toc.precache"].tap()
        let status = app.staticTexts["reader.toc.precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        // 停止按钮在运行时出现；若预缓存极快完成则 dismiss 直接出现。
        let stop = app.buttons["reader.toc.precache.stop"]
        let dismiss = app.buttons["reader.toc.precache.dismiss"]
        if stop.waitForExistence(timeout: 3) {
            stop.tap()
            waitForLabel(status, contains: "已停止", timeout: 8)
            XCTAssertFalse(stop.exists, "停止后不再显示停止按钮")
        }
        capture(app, "reader-toc-precache-stopped")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 20), "运行结束后应出现关闭按钮")
        dismiss.tap()
        XCTAssertFalse(status.waitForExistence(timeout: 2), "关闭后进度条应消失")
        XCTAssertTrue(app.buttons["reader.toc.precache"].isEnabled, "停止后可再次预缓存")
    }
}

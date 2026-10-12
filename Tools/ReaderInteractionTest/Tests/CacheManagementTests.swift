import XCTest

final class CacheManagementTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }
    override func tearDownWithError() throws { app?.terminate() }

    private func launch(dark: Bool = false) {
        app.launchEnvironment["CACHE_MANAGEMENT_FIXTURE_ID"] = UUID().uuidString
        app.launchArguments = ["--cache-management-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if dark { app.launchArguments.append("--cache-management-dark") }
        app.launch()
        XCTAssertTrue(app.buttons["cache.clear.content"].waitForExistence(timeout: 12))
        status("fixture=ready")
        status("content=6144;contentFiles=2;memory=1;catalog=1024;catalogFiles=1")
        verifyProtected()
    }
    private func status(_ fragment: String) {
        let report = app.staticTexts["cache.fixture.report"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", fragment), object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 6), .completed, report.value as? String ?? "missing")
    }
    private func probe() { app.buttons["cache.fixture.check"].tap() }
    private func verifyProtected() { status("protected=1665;protectedFiles=3;unmanaged=257") }
    private func reveal(_ id: String) -> XCUIElement {
        let item = app.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<8 {
            if item.exists && item.isHittable, item.frame.minY >= 115, item.frame.maxY < app.frame.maxY - 115 { return item }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(item.exists && item.isHittable, id)
        return item
    }
    private func tap(_ id: String) { reveal(id).tap() }
    private func confirm() {
        let confirm = app.buttons["确认清理"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 5), .completed)
        let busy = app.descendants(matching: .any).matching(identifier: "cache.busy").firstMatch
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 8), .completed)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "cache.result").firstMatch.waitForExistence(timeout: 8))
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testCancelThenContentOnlyClearKeepsCatalogAndPersonalFiles() {
        launch()
        capture("cache-management-light-summary")
        tap("cache.clear.content")
        XCTAssertTrue(app.buttons["确认清理"].waitForExistence(timeout: 5))
        capture("cache-management-content-confirmation")
        app.buttons["取消"].tap()
        probe()
        status("content=6144;contentFiles=2;memory=1;catalog=1024;catalogFiles=1")
        tap("cache.clear.content")
        confirm()
        probe()
        status("content=0;contentFiles=0;memory=0;catalog=1024;catalogFiles=1")
        verifyProtected()
        app.buttons["cache.refresh"].tap()
        probe()
        status("content=0;contentFiles=0;memory=0;catalog=1024;catalogFiles=1")
        capture("cache-management-content-cleared")
    }
    func testDarkClearAllAndEmptyReclearKeepProtectedBytes() {
        launch(dark: true)
        capture("cache-management-dark-summary")
        tap("cache.clear.all")
        confirm()
        probe()
        status("content=0;contentFiles=0;memory=0;catalog=0;catalogFiles=0;networkDisk=0;networkMemory=0")
        verifyProtected()
        capture("cache-management-all-cleared")
        tap("cache.clear.all")
        confirm()
        probe()
        status("content=0;contentFiles=0;memory=0;catalog=0;catalogFiles=0")
        verifyProtected()
        let result = reveal("cache.result")
        XCTAssertFalse(result.label.contains("部分缓存未能清理"))
        capture("cache-management-empty-reclear")
    }
}

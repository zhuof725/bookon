import XCTest

final class ShelfTests: XCTestCase {
    private var app: XCUIApplication!
    private var a: XCUIElement { app.buttons["shelf.book.fixture-a"] }
    private var b: XCUIElement { app.buttons["shelf.book.fixture-b"] }
    private var report: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "shelf.fixture.report").firstMatch
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--shelf-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(a.waitForExistence(timeout: 8))
        XCTAssertTrue(b.exists)
    }

    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 3), id)
        button.tap()
    }

    private func status(_ fragment: String) {
        let predicate = NSPredicate(format: "value CONTAINS %@", fragment)
        expectation(for: predicate, evaluatedWith: report)
        waitForExpectations(timeout: 4)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShelfAndMoreMenuScreenshots() {
        // Visual composition references, inspected by the author (not bundled covers):
        // /var/minis/attachments/uploads/photo_91AB4728.png
        // /var/minis/attachments/uploads/photo_2C4A2EB4.png
        status("counts=2,1,1,1") // actual ShelfBooks.visible for all/reading/unread/local
        status("orders=fixture-b,fixture-a|fixture-a,fixture-b|fixture-a,fixture-b")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shelf.book.'")).count, 2)
        XCTAssertEqual(a.frame.minY, b.frame.minY, accuracy: 2)
        XCTAssertLessThan(b.frame.minX, a.frame.minX)
        // 页面左右边距 16（AppLayout.pageInset），列间距 18：可用宽度 = 宽 - 32 - 36。
        let expectedWidth = (app.frame.width - 32 - 36) / 3
        XCTAssertEqual(a.frame.width, expectedWidth, accuracy: 4, "Three columns; only two occupied")
        XCTAssertLessThan(app.buttons["shelf.filter"].frame.maxY, a.frame.minY)
        XCTAssertEqual(app.buttons["shelf.filter"].frame.midX, app.frame.midX, accuracy: 2,
                       "分类「全部」胶囊应在书架头部水平居中")
        XCTAssertLessThan(a.frame.maxY, app.buttons["library.tab.0"].frame.minY)
        capture("shelf-01-grid")
        tap("shelf.more")
        for id in ["shelf.select", "shelf.import", "shelf.view", "shelf.sort"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 3))
        }
        XCTAssertLessThan(app.buttons["shelf.more"].frame.maxY, app.buttons["shelf.select"].frame.minY)
        capture("shelf-02-more-menu")
    }

    func testLayoutSortFilterAndCancelRemoval() {
        tap("shelf.more"); tap("shelf.view"); tap("shelf.layout.list")
        status("layout=列表")
        XCTAssertLessThan(b.frame.minY, a.frame.minY)
        tap("shelf.more"); tap("shelf.sort"); tap("shelf.sort.title")
        status("sort=书名")
        XCTAssertLessThan(a.frame.minY, b.frame.minY)
        tap("shelf.filter"); tap("shelf.filter.reading")
        XCTAssertTrue(b.exists); XCTAssertFalse(a.exists)
        tap("shelf.filter"); tap("shelf.filter.unread")
        XCTAssertTrue(a.exists); XCTAssertFalse(b.exists)
        tap("shelf.filter"); tap("shelf.filter.local")
        XCTAssertTrue(a.exists); XCTAssertFalse(b.exists)
        tap("shelf.filter"); tap("shelf.filter.all")
        tap("shelf.more"); tap("shelf.select")
        XCTAssertFalse(app.buttons["shelf.removeSelected"].isEnabled)
        a.tap()
        XCTAssertEqual(a.value as? String, "已选择")
        tap("shelf.removeSelected")
        XCTAssertTrue(app.buttons["移除书籍"].waitForExistence(timeout: 3))
        tap("取消") // Never confirm removal or touch the user's files.
        status("books=2"); status("removed=0")
        tap("shelf.finishSelection")
        XCTAssertEqual(a.value as? String, "打开阅读")
        XCTAssertFalse(app.buttons["shelf.removeSelected"].exists)
        XCTAssertTrue(a.exists && b.exists)
    }

    func testReferenceListMetadataAndSelection() {
        status("summaryChecks=true")
        tap("shelf.more"); tap("shelf.view"); tap("shelf.layout.list")
        status("layout=列表")
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '167章未读'"), object: b)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 6), .completed)
        XCTAssertTrue(b.label.contains("2026-10-13 · 第169章 测试章节"))
        XCTAssertTrue(a.label.contains("未读过"))
        XCTAssertFalse(a.label.contains("共0章"))
        XCTAssertTrue(a.label.contains("暂无章节信息"))
        XCTAssertFalse(b.staticTexts["99+"].exists)
        XCTAssertEqual(a.frame.minX, 0, accuracy: 2)
        XCTAssertEqual(a.frame.width, app.frame.width, accuracy: 2)
        XCTAssertEqual(a.frame.height, 104, accuracy: 2)
        XCTAssertEqual(b.frame.maxY, a.frame.minY, accuracy: 2)
        capture("shelf-reference-list-light")
        tap("shelf.more"); tap("shelf.select"); b.tap()
        XCTAssertEqual(b.value as? String, "已选择")
        b.tap(); XCTAssertEqual(b.value as? String, "未选择")
        tap("shelf.finishSelection"); status("removed=0")
        b.tap(); XCTAssertTrue(app.staticTexts["shelf.reader"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["shelf.reader.title"].label, "B 山海手记")
    }

    func testReferenceListDarkLarge320() {
        app.terminate()
        app.launchArguments += ["--shelf-dark", "--shelf-large"]
        app.launch()
        XCTAssertTrue(a.waitForExistence(timeout: 10))
        tap("shelf.more"); tap("shelf.view"); tap("shelf.layout.list")
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(b.frame.width, 320)
        XCTAssertGreaterThan(b.frame.height, 104)
        XCTAssertGreaterThanOrEqual(b.frame.minX, 0)
        XCTAssertLessThanOrEqual(b.frame.maxX, app.frame.maxX)
        capture("shelf-reference-list-dark-large320")
        b.tap(); XCTAssertTrue(app.staticTexts["shelf.reader"].waitForExistence(timeout: 5))
    }

    func testImportAndSearchCallbacks() {
        // 搜索入口已移到最右边的底栏页签，书架上不再有搜索按钮。
        XCTAssertFalse(app.buttons["shelf.search"].exists, "书架头部不再有搜索按钮")
        tap("library.tab.3")
        XCTAssertTrue(app.staticTexts["shelf.searchPage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["library.tab.3"].isSelected)
        XCTAssertGreaterThan(app.buttons["library.tab.3"].frame.minX, app.buttons["library.tab.2"].frame.minX,
                             "搜索在底栏最右边")
        status("tab=3")
        tap("library.tab.0")
        XCTAssertTrue(a.waitForExistence(timeout: 3))
        tap("shelf.more"); tap("shelf.import")
        status("import=1")
        XCTAssertFalse(app.buttons["shelf.import"].exists)
        status("books=2"); status("removed=0")
        XCTAssertTrue(a.exists && b.exists)
    }

    func testDockAndReaderPushHidesRootDock() {
        tap("library.tab.5")
        XCTAssertTrue(app.staticTexts["shelf.explore"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["library.tab.5"].isSelected)
        tap("library.tab.2")
        XCTAssertTrue(app.staticTexts["shelf.profile"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["library.tab.2"].isSelected)
        tap("library.tab.0")
        XCTAssertTrue(a.waitForExistence(timeout: 3))
        status("tab=0")
        a.tap()
        XCTAssertTrue(app.staticTexts["shelf.reader"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["shelf.reader.title"].label, "A 林间札记")
        for id in ["library.tab.0", "library.tab.5", "library.tab.2", "library.tab.3", "shelf.more"] {
            XCTAssertFalse(app.buttons[id].exists, "Root chrome must not follow the pushed reader")
        }
        XCTAssertEqual(app.navigationBars.count, 0)
        capture("shelf-03-reader-no-dock")
        tap("shelf.reader.back")
        XCTAssertTrue(a.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["library.tab.0"].exists)
        status("books=2")
    }

    /// 下划更新：在书架上向下拖动应触发刷新回调，并显示结果文案。
    /// 下拉手势在慢速模拟器上偶发不达标，最多重试三次；断言只要求最终触发一次。
    func testPullToRefreshRunsOnce() {
        status("refreshes=0")
        let start = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let finish = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 9))
        for _ in 0..<3 {
            start.press(forDuration: 0.2, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.6)
            if let value = report.value as? String, value.contains("refreshes=1") { break }
            Thread.sleep(forTimeInterval: 1.5)
        }
        status("refreshes=1")
        status("refresh=已更新 2 本")
        // 刷新结果胶囊是视觉附加项：截图留证（shelf-04-pull-refresh），
        // 断言只覆盖「下拉触发一次刷新并拿到结果文案」这一功能事实。
        capture("shelf-04-pull-refresh")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shelf.book.'")).count, 2,
                       "下拉刷新不应误触书籍")
    }
}

import XCTest

final class ChromeTests: XCTestCase {
    private let chromeIDs = ["reader.back", "reader.details", "reader.title", "reader.source",
                             "reader.chapter", "reader.position", "reader.progress", "reader.previous",
                             "reader.next", "reader.toc", "reader.speech", "reader.search", "reader.settings"]

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-chrome-mode"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reader-footer-page"].waitForExistence(timeout: 10))
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func counters(_ app: XCUIApplication, file: StaticString = #filePath,
                          line: UInt = #line) -> [String: Int] {
        let page = app.staticTexts["reader-footer-page"]
        let raw = page.value as? String ?? ""
        XCTAssertTrue(raw.contains("back="), "Missing callback instrumentation: \(raw)", file: file, line: line)
        var result: [String: Int] = [:]
        for item in raw.split(separator: ";") {
            let pair = item.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { result[String(pair[0])] = Int(pair[1]) }
        }
        return result
    }

    private func centerTap(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func assertNoOverlap(_ left: XCUIElement, _ right: XCUIElement,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(left.exists && right.exists, "Missing \(left.identifier) or \(right.identifier)", file: file, line: line)
        guard left.exists && right.exists else { return }
        XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX + 1,
                                 "Overlapping controls: \(left.identifier) and \(right.identifier)", file: file, line: line)
    }

    private func assertUniqueChrome(_ app: XCUIApplication, file: StaticString = #filePath,
                                    line: UInt = #line) {
        for id in chromeIDs {
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: id).count, 1,
                           "Duplicate or missing accessible chrome control: \(id)", file: file, line: line)
        }
    }

    func testReferenceChromeOverlayScreenshotAndStableBodyOnCloseReopen() {
        let app = launch()
        assertUniqueChrome(app)
        XCTAssertEqual(app.staticTexts["reader.title"].label, "巫师：从合成宝石开始")
        XCTAssertEqual(app.staticTexts["reader.source"].label, "起点小说 (qimo)")
        XCTAssertEqual(app.staticTexts["reader.chapter"].label, "第 3 章 语言课")
        XCTAssertEqual(app.staticTexts["reader.position"].label, "7 / 14")
        XCTAssertEqual(app.staticTexts["reader-footer-page"].label, "7/14")
        let paragraph = element(app, "chrome.body.paragraph.1")
        XCTAssertTrue(paragraph.exists, "Real InlineCommentParagraph should remain in accessibility tree")
        let before = paragraph.frame
        XCTAssertGreaterThan(before.width, 200)
        snapshot(app, "reader-chrome-light-reference-open")

        centerTap(app)
        XCTAssertFalse(app.buttons["reader.back"].waitForExistence(timeout: 1))
        XCTAssertEqual(paragraph.frame.origin.x, before.origin.x, accuracy: 1)
        XCTAssertEqual(paragraph.frame.origin.y, before.origin.y, accuracy: 1)
        XCTAssertEqual(paragraph.frame.size.height, before.size.height, accuracy: 1)
        snapshot(app, "reader-chrome-light-reference-closed")

        centerTap(app)
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 5))
        assertUniqueChrome(app)
        XCTAssertEqual(paragraph.frame.origin.x, before.origin.x, accuracy: 1)
        XCTAssertEqual(paragraph.frame.origin.y, before.origin.y, accuracy: 1)
        XCTAssertEqual(paragraph.frame.size.height, before.size.height, accuracy: 1)
        XCTAssertEqual(app.staticTexts["reader-footer-page"].label, "7/14")
        snapshot(app, "reader-chrome-light-reference-reopened")
    }

    func testNightThemeAnd320ptChromeHaveNoOverlappingControls() {
        for (name, flags) in [("night", ["--chrome-dark"]),
                              ("320pt", ["--chrome-narrow"])] {
            let app = launch(flags)
            assertUniqueChrome(app)
            let back = app.buttons["reader.back"]
            let title = app.staticTexts["reader.title"]
            let source = app.staticTexts["reader.source"]
            let details = app.buttons["reader.details"]
            let previous = app.buttons["reader.previous"]
            let slider = app.sliders["reader.progress"]
            let next = app.buttons["reader.next"]
            assertNoOverlap(back, title)
            assertNoOverlap(title, details)
            assertNoOverlap(back, source)
            assertNoOverlap(source, details)
            assertNoOverlap(previous, slider)
            assertNoOverlap(slider, next)
            let chapter = app.staticTexts["reader.chapter"]
            let position = app.staticTexts["reader.position"]
            XCTAssertFalse(chapter.frame.intersects(position.frame), "Chapter and position overlap")
            XCTAssertLessThan(chapter.frame.maxY, slider.frame.minY)
            XCTAssertLessThan(position.frame.maxY, slider.frame.minY)
            XCTAssertLessThan(title.frame.maxY, slider.frame.minY)
            for pair in [("reader.toc", "reader.speech"), ("reader.speech", "reader.search"),
                         ("reader.search", "reader.settings")] {
                assertNoOverlap(app.buttons[pair.0], app.buttons[pair.1])
            }
            XCTAssertGreaterThan(app.buttons["reader.settings"].frame.minY, slider.frame.maxY - 2)
            if name == "320pt" {
                XCTAssertLessThanOrEqual(details.frame.maxX - back.frame.minX, 320)
                XCTAssertEqual(app.staticTexts["reader.position"].label, "7 / 14")
            }
            snapshot(app, "reader-chrome-\(name)-open")
            app.terminate()
        }
    }

    func testButtonCallbacksAndSheetsDoNotDuplicateChromeIdentifiers() {
        let app = launch()
        app.buttons["reader.back"].tap()
        XCTAssertEqual(counters(app)["back"], 1)
        app.buttons["reader.next"].tap()
        XCTAssertEqual(app.staticTexts["reader.position"].label, "8 / 14")
        app.buttons["reader.previous"].tap()
        XCTAssertEqual(app.staticTexts["reader.position"].label, "7 / 14")
        app.buttons["reader.speech"].tap()
        XCTAssertEqual(app.buttons["reader.speech"].value as? String, "正在朗读")
        app.buttons["reader.speech"].tap()
        XCTAssertEqual(app.buttons["reader.speech"].value as? String, "未朗读")
        // No AVSpeechSynthesizer is invoked by this offline callback fixture.
        for (id, title) in [("reader.details", "书籍信息"), ("reader.toc", "目录"),
                            ("reader.settings", "阅读设置")] {
            app.buttons[id].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), title)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: id).count, 0,
                           "Chrome must not coexist with sheet \(title)")
            app.buttons["完成"].tap()
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
            assertUniqueChrome(app)
        }
        let values = counters(app)
        for (key, expected) in ["back": 1, "details": 1, "previous": 1, "next": 1,
                                "toc": 1, "speech": 2, "settings": 1] {
            XCTAssertEqual(values[key], expected, key)
        }
    }

    func testSliderCommitsOnceWhenEditingEndsAndDisabledEdgesStayDisabled() {
        let app = launch()
        let slider = app.sliders["reader.progress"]
        XCTAssertTrue(slider.isEnabled)
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.46, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        let values = counters(app)
        XCTAssertGreaterThanOrEqual(values["began"] ?? 0, 1)
        XCTAssertEqual(values["began"], values["ended"])
        XCTAssertGreaterThan(values["updatesWhileEditing"] ?? 0, 0)
        XCTAssertEqual(values["commits"], 1)
        XCTAssertEqual(values["committedBeforeEnd"], 0)
        let currentPage = Int(app.staticTexts["reader.position"].label.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(currentPage, 7)
        snapshot(app, "reader-chrome-scrub-committed")
        app.terminate()

        for (edge, disabled, enabled, page) in [("first", "reader.previous", "reader.next", "1 / 14"),
                                               ("last", "reader.next", "reader.previous", "14 / 14")] {
            let boundary = launch(["--chrome-edge=\(edge)"])
            XCTAssertEqual(boundary.staticTexts["reader.position"].label, page)
            XCTAssertFalse(boundary.buttons[disabled].isEnabled)
            XCTAssertTrue(boundary.buttons[enabled].isEnabled)
            let disabledButton = boundary.buttons[disabled]
            disabledButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertEqual(counters(boundary)[edge == "first" ? "previous" : "next"], 0)
            XCTAssertEqual(boundary.staticTexts["reader.position"].label, page)
            boundary.buttons[enabled].tap()
            XCTAssertEqual(counters(boundary)[edge == "first" ? "next" : "previous"], 1)
            boundary.terminate()
        }
        let unsrubbable = launch(["--chrome-no-scrub"])
        XCTAssertFalse(unsrubbable.sliders["reader.progress"].isEnabled)
        XCTAssertEqual(counters(unsrubbable)["commits"], 0)
    }

    func testChapterSearchFindsParagraphAndEmojiThenNavigatesExactPage() {
        for (query, name) in [("宝石", "han"), ("👩🏽‍🔬", "emoji")] {
            let app = launch()
            app.buttons["reader.search"].tap()
            XCTAssertTrue(app.navigationBars["本章搜索"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "reader.search").count, 0)
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(query)
            let hit = app.buttons["reader.search.result.12"]
            XCTAssertTrue(hit.waitForExistence(timeout: 5), "Missing \(query) paragraph")
            XCTAssertTrue(hit.label.contains("7"), "Search should map true character offset to page 7")
            XCTAssertEqual(app.buttons.matching(identifier: "reader.search.result.12").count, 1)
            snapshot(app, "reader-chrome-search-\(name)-result")
            hit.tap()
            XCTAssertTrue(app.buttons["reader.search"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["reader.position"].label, "7 / 14")
            XCTAssertEqual(counters(app)["search"], 1)
            XCTAssertEqual(counters(app)["select"], 1)
            app.terminate()
        }
    }

    func testScrollSearchShowsMatchingParagraphWithoutApproximateJump() {
        let app = launch(["--chrome-scroll-search"])
        app.buttons["reader.search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("👩🏽‍🔬")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "小巫师")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader.search.result.")).count, 0,
                       "Scroll search is read-only; do not invent approximate jump targets")
        snapshot(app, "reader-chrome-scroll-search-read-only-emoji")
        // Native searchable replaces navigation items with Cancel while active.
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "取消")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertEqual(counters(app)["select"], 0)
        XCTAssertEqual(app.staticTexts["reader.position"].label, "7 / 14")
    }
}

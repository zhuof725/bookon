import XCTest

final class DetailTests: XCTestCase {
    private var app: XCUIApplication!
    private let intro = "山风吹过旧书屋，旅人翻开林间笔记。\n灯下记录远行见闻，也记录归途。\n下一段故事，从清晨开始。"
    private let actions = ["back", "more", "read", "category", "source", "remove", "editor", "toc"]
    private var report: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "detail.fixture.report").firstMatch
    }
    private var scroll: XCUIElement { app.scrollViews.firstMatch }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func launch(_ options: [String] = []) {
        app.launchArguments = ["--detail-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + options
        app.launch()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["detail.title"].exists)
        XCTAssertTrue(report.exists)
    }

    private func status(_ value: String) {
        let predicate = NSPredicate(format: "value CONTAINS %@", value)
        let pending = XCTNSPredicateExpectation(predicate: predicate, object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 4), .completed, value)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }

    private func capture(_ name: String) {
        // Native simulator rendering, not an HTML mock or reference-image crop.
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func assertSeparate(_ elements: [XCUIElement], file: StaticString = #filePath, line: UInt = #line) {
        for (index, element) in elements.enumerated() {
            XCTAssertTrue(element.exists, file: file, line: line)
            XCTAssertGreaterThan(element.frame.width, 0, file: file, line: line)
            XCTAssertGreaterThan(element.frame.height, 0, file: file, line: line)
            for other in elements.dropFirst(index + 1) {
                XCTAssertFalse(element.frame.intersects(other.frame),
                    "Overlapping \(element.identifier) / \(other.identifier)", file: file, line: line)
            }
        }
    }

    /// 版式对齐参考图：封面卡 → 阅读/书架 → 分组·类型·更新 → 简介 → 目录 → 来源。
    func testReferenceLayoutSections() {
        launch()
        let read = app.buttons["detail.read"]
        let shelf = app.buttons["detail.shelfAction"]
        // 两个 56pt 胶囊按钮：阅读占满剩余宽度，书架按内容宽度收窄，互不重叠。
        XCTAssertEqual(read.frame.height, 56, accuracy: 2)
        XCTAssertEqual(shelf.frame.height, 56, accuracy: 2)
        XCTAssertGreaterThan(read.frame.width, shelf.frame.width)
        XCTAssertLessThanOrEqual(read.frame.maxX, shelf.frame.minX + 0.5)
        // 分组 / 类型 / 更新 三栏（分组可点，值就是当前分类）。
        XCTAssertTrue(app.buttons["detail.changeCategory"].label.contains("随笔"),
                      app.buttons["detail.changeCategory"].label)
        XCTAssertEqual(app.staticTexts["detail.type.value"].label, "本地")
        XCTAssertEqual(app.staticTexts["detail.update.value"].label, "未知")
        // 来源卡显示书源名 + 换源。
        let source = app.buttons["detail.changeSource"]
        reveal(source)
        XCTAssertTrue(source.label.contains("本地书籍"), source.label)
        XCTAssertTrue(source.label.contains("换源"), source.label)
        capture("detail-08-reference-layout")
    }

    func testSourceBooksNeverOfferIntroEditing() {
        for flags in [["--detail-source-book", "--detail-off-shelf"], ["--detail-source-book"]] {
            launch(flags)
            let description = app.staticTexts["detail.intro"]
            reveal(description)
            XCTAssertEqual(description.label, intro)
            XCTAssertFalse(app.buttons["detail.editIntro"].exists)
            XCTAssertFalse(app.buttons["编辑简介"].exists)
            reveal(app.buttons["detail.toc"])
            XCTAssertFalse(app.buttons["detail.editIntro"].exists)
            capture(flags.contains("--detail-off-shelf") ? "detail-source-search-no-editor" : "detail-source-shelf-no-editor")
            app.terminate()
        }
        launch()
        let editor = app.buttons["detail.editIntro"]
        reveal(editor)
        editor.tap()
        status("editor=1")
    }

    func testFullDetailMetadataAndNativeScreenshots() {
        // Composition reference: photo_BAB718AA.png. Its book, cover, counts and
        // timestamps are NOT test data. All displayed metadata comes from fixtures.
        launch()
        XCTAssertEqual(app.staticTexts["detail.title"].label, "林间札记")
        XCTAssertTrue(app.staticTexts["detail.author"].label.contains("离线作者"))
        XCTAssertEqual(app.staticTexts["detail.wordCount"].label, "65 字")
        XCTAssertEqual(app.staticTexts["detail.category"].label, "随笔")
        XCTAssertEqual(app.staticTexts["detail.status"].label, "在读")
        for tag in ["幻想", "旅行", "成长", "见闻", "自然", "短篇"] {
            XCTAssertTrue(app.staticTexts[tag].exists, tag)
        }
        XCTAssertTrue(app.buttons["detail.read"].label.contains("继续阅读"))
        XCTAssertEqual(app.buttons["detail.shelfAction"].label, "移除书架")
        status("chapters=3")
        capture("detail-01-full-light-top")
        let text = app.staticTexts["detail.intro"]
        reveal(text)
        XCTAssertEqual(text.label, intro)
        XCTAssertGreaterThan(text.frame.height, 60, "Three explicit intro lines must remain multiline")
        let toc = app.buttons["detail.toc"]
        reveal(toc)
        // A Button may combine its children. Inspect its label instead of relying
        // on detail.count/detail.latest surviving parent identifier propagation.
        XCTAssertTrue(toc.label.contains("共 3 章"), toc.label)
        XCTAssertTrue(toc.label.contains("第三章 清晨出发"), toc.label)
        XCTAssertFalse(toc.label.contains("更新于"), "No fixture chapter has an updateTime")
        capture("detail-02-full-light-intro-toc")
    }

    func testAllCallbacksAreIsolatedAndNonDestructive() {
        launch()
        for id in ["detail.back", "detail.more"] {
            let button = app.buttons[id]
            XCTAssertEqual(button.frame.width, 46, accuracy: 1)
            XCTAssertEqual(button.frame.height, 46, accuracy: 1)
        }
        let controls = ["detail.back", "detail.more", "detail.read", "detail.changeCategory",
                        "detail.changeSource", "detail.shelfAction", "detail.editIntro", "detail.toc"]
        for (index, id) in controls.enumerated() {
            XCTAssertEqual(app.buttons.matching(identifier: id).count, 1, "Unique leaf identifier: \(id)")
            let button = app.buttons[id]
            reveal(button)
            button.tap()
            // Verify the entire vector after each tap: adjacent hit regions must
            // not fire a different callback or accidentally invoke two actions.
            let expected = actions.enumerated().map { "\($0.element)=\($0.offset <= index ? 1 : 0)" }
                .joined(separator: ";")
            status(expected)
            status("onShelf=true;chapters=3;fixtureUnchanged=true")
        }
        XCTAssertEqual(app.alerts.count, 0, "Fixture removal must not open destructive dialogs")
        XCTAssertTrue(app.staticTexts["detail.title"].exists, "Back callback is recorded, not real navigation")
    }

    func testMissingMetadataDoesNotInventCountsOrDates() {
        launch(["--detail-missing", "--detail-dark"])
        status("scheme=dark")
        status("chapters=0")
        XCTAssertFalse(app.staticTexts["detail.wordCount"].exists)
        XCTAssertTrue(app.staticTexts["detail.author"].label.contains("作者未知"))
        XCTAssertEqual(app.staticTexts["detail.category"].label, "未分类")
        XCTAssertEqual(app.staticTexts["detail.status"].label, "未读")
        XCTAssertTrue(app.buttons["detail.read"].label.contains("开始阅读"))
        XCTAssertEqual(app.staticTexts["detail.intro"].label, "暂无简介")
        capture("detail-03-missing-dark-top")
        let toc = app.buttons["detail.toc"]
        reveal(toc)
        XCTAssertFalse(toc.label.contains("章"), "An unloaded empty catalog must not claim a chapter count")
        XCTAssertFalse(toc.label.contains("最新"))
        XCTAssertFalse(toc.label.contains("更新于"))
        let visibleText = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ") + toc.label
        for fabricated in ["229.7", "836", "11009", "1970", "2026/10/12", "共 0 章", "0 字", "更新于"] {
            XCTAssertFalse(visibleText.contains(fabricated), fabricated)
        }
        capture("detail-04-missing-dark-intro-toc")
    }

    func test320PointDarkLayoutHasNoOverlapAndMultilineIntro() {
        launch(["--detail-width-320", "--detail-dark"])
        status("scheme=dark")
        XCTAssertEqual(scroll.frame.width, 320, accuracy: 1, "Real native layout constrained to 320pt")
        let left = scroll.frame.minX
        let right = scroll.frame.maxX
        let ids = ["detail.back", "detail.more", "detail.read", "detail.changeCategory", "detail.changeSource", "detail.shelfAction"]
        let buttons = ids.map { app.buttons[$0] }
        assertSeparate(buttons)
        let title = app.staticTexts["detail.title"]
        let cover = app.descendants(matching: .any).matching(identifier: "detail.cover").firstMatch
        let metadata = [title, app.staticTexts["detail.author"], app.staticTexts["detail.wordCount"],
                        app.staticTexts["detail.category"], app.staticTexts["detail.status"]]
            + ["幻想", "旅行", "成长", "见闻", "自然", "短篇"].map { app.staticTexts[$0] }
        assertSeparate([cover] + metadata)
        assertSeparate(metadata + Array(buttons.dropFirst(2)))
        for element in buttons + [cover] + metadata {
            XCTAssertGreaterThanOrEqual(element.frame.minX, left - 1, element.identifier)
            XCTAssertLessThanOrEqual(element.frame.maxX, right + 1, element.identifier)
        }
        capture("detail-05-320-dark-top")
        let text = app.staticTexts["detail.intro"]
        reveal(text)
        XCTAssertEqual(text.label, intro)
        XCTAssertGreaterThan(text.frame.height, 75, "Narrow intro wraps rather than truncates")
        XCTAssertGreaterThanOrEqual(text.frame.minX, left)
        XCTAssertLessThanOrEqual(text.frame.maxX, right)
        capture("detail-06-320-dark-multiline-intro")
        let editor = app.buttons["detail.editIntro"]
        reveal(editor)
        XCTAssertLessThanOrEqual(text.frame.maxY, editor.frame.minY)
        let toc = app.buttons["detail.toc"]
        reveal(toc)
        XCTAssertLessThanOrEqual(editor.frame.maxY, toc.frame.minY)
        XCTAssertGreaterThanOrEqual(toc.frame.minX, left)
        XCTAssertLessThanOrEqual(toc.frame.maxX, right)
        XCTAssertTrue(toc.label.contains("共 3 章"))
        capture("detail-07-320-dark-toc")
    }
}

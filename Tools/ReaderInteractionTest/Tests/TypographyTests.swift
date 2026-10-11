import XCTest

final class TypographyTests: XCTestCase {
    func testNativeGlyphsFixedBaselinesAndActualLinePagination() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--typography-mode"]
        app.launch()
        let inspect = app.buttons["inspect-typography"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 8))
        inspect.tap()
        let metrics = app.staticTexts["typography-metrics"]
        let ready = NSPredicate { _, _ in metrics.exists && metrics.label.hasPrefix("{") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: metrics)], timeout: 12), .completed)
        let raw = metrics.label
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func number(_ key: String) throws -> Double {
            try XCTUnwrap(report[key] as? NSNumber, "Missing \(key): \(raw)").doubleValue
        }
        let detail = XCTAttachment(string: raw)
        detail.name = "native-glyph-baseline-and-source-metrics.json"
        detail.lifetime = .keepAlways
        add(detail)
        // Six representative settings × first/continuation. The same 19pt font is
        // measured at two widths, which catches width/floor(width/fontSize) tracking.
        XCTAssertEqual(try number("naturalCases"), 12, raw)
        for key in ["nativeAdvanceError", "nativeSizeError", "nativeGlyphError", "indentError", "widthError", "shapingError"] {
            XCTAssertLessThanOrEqual(try number(key), 0.25, "\(key): \(raw)")
        }
        XCTAssertLessThanOrEqual(try number("largestHanStepRatio"), 1.02, raw)
        XCTAssertGreaterThan(try number("hanPairs"), 100, raw)
        XCTAssertGreaterThan(try number("punctuationGlyphs"), 100, raw)
        XCTAssertGreaterThan(try number("naturalRows"), 30, raw)
        XCTAssertGreaterThan(try number("baselinePairs"), 20, raw)
        for key in ["baselineError", "heightError", "bubbleBaselineError", "bubbleHeightError", "bubbleWidthError"] {
            XCTAssertLessThanOrEqual(try number(key), 0.5, "\(key): \(raw)")
        }
        for key in ["naturalSourceOK", "naturalAttributesOK", "nativeGlyphsOK", "lineBreaksOK", "nativeRunsOK",
                    "bubbleHitOK", "bubbleSourceOK", "bubbleTailOK", "mixedNativeRunsOK"] {
            XCTAssertEqual(report[key] as? Bool, true, "\(key): \(raw)")
        }
        let quotes = try XCTUnwrap(report["quoteGlyphs"] as? [String: Int])
        XCTAssertEqual(Set(quotes.keys), Set(["‘", "’", "“", "”"]))
        XCTAssertEqual(Set(quotes.values).count, 4, raw)
        XCTAssertEqual(try number("bubbleChecks"), 4, raw)
        // Android distributes spare height only on near-full pure-text pages.
        // Sparse terminal pages intentionally retain natural top whitespace.
        XCTAssertGreaterThan(try number("anchoredPages"), 0, raw)
        XCTAssertLessThanOrEqual(try number("anchoredPages"), try number("pages"), raw)
        XCTAssertLessThanOrEqual(try number("terminalAnchors"), 3, raw)
        XCTAssertEqual(try number("titleChecks"), 3, raw)
        for key in ["pageWithinError", "pageAcrossError", "pageHeightError", "pageWidthError", "pageOverflow", "pageTopError", "pageBottomBaselineError", "terminalBottomError", "titleTopError"] {
            XCTAssertLessThanOrEqual(try number(key), 0.75, "\(key): \(raw)")
        }
        for key in ["pageSourceOK", "offsetsOK", "actualLineSplitsOK", "continuationsOK", "pageCommentsOK", "pageBubblesOK", "naturalPagesOK"] {
            XCTAssertEqual(report[key] as? Bool, true, "\(key): \(raw)")
        }
        XCTAssertGreaterThan(try number("nonterminalPages"), 2, raw)
        XCTAssertGreaterThan(try number("splitChecks"), 2, raw)
        XCTAssertGreaterThan(try number("pagePairs"), 10, raw)
        XCTAssertGreaterThan(try number("pageBoundaries"), 2, raw)
        XCTAssertEqual(try number("pageComments"), 9, raw)
        for key in ["scrollWidthError", "scrollHeightError", "scrollBaselineError"] {
            XCTAssertLessThanOrEqual(try number(key), 0.75, "\(key): \(raw)")
        }
        XCTAssertEqual(try number("scrollParagraphs"), 6, raw)
        XCTAssertEqual(try number("scrollBoundaries"), 4, raw)
        XCTAssertGreaterThan(try number("scrollPairs"), 10, raw)
        XCTAssertEqual(report["scrollSourceOK"] as? Bool, true, raw)
        XCTAssertEqual(report["scrollBubbleOK"] as? Bool, true, raw)
        // Avoid restoring the old hundreds-of-bitmaps / many-host Cartesian matrix.
        XCTAssertLessThan(try number("elapsedSeconds"), 12, raw)
        app.terminate()
        app.launchArguments = ["--typography-mode", "--reference-page"]
        app.launch()
        XCTAssertTrue(app.staticTexts["chapter-title"].waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "reference-chinese-dialogue-native-production-page"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLongChapterTitleIsVisibleAndLayoutControlsPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--typography-mode"]
        app.launch()
        XCTAssertTrue(app.staticTexts["typography-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["typography-title"].label.contains("这是一个很长的章节标题"))
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.staticTexts["layout-value-font"].waitForExistence(timeout: 5))
        let old = app.staticTexts["layout-value-font"].label
        app.buttons["layout-plus-font"].tap()
        app.buttons["layout-plus-left"].tap()
        XCTAssertNotEqual(app.staticTexts["layout-value-font"].label, old)
        app.buttons["close-settings"].tap()
        app.buttons["open-settings"].tap()
        XCTAssertEqual(app.staticTexts["layout-value-left"].label, "21 pt")
        XCTAssertTrue(app.staticTexts["layout-value-font"].exists)
    }
}

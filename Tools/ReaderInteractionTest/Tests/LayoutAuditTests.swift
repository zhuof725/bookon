import XCTest

final class LayoutAuditTests: XCTestCase {
    func testReportedQuotesBreaksBubbleAndParagraphRhythm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--layout-audit-mode"]
        app.launch()
        let button = app.buttons["inspect-layout-audit"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        let label = app.staticTexts["layout-audit-report"]
        let ready = NSPredicate { _, _ in label.exists && label.label.hasPrefix("{") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: label)],
                                    timeout: 45), .completed, label.label)
        let raw = label.label
        let attachment = XCTAttachment(string: raw)
        attachment.name = "reported-page-glyph-break-spacing-audit.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(raw.data(using: .utf8)))
            as? [String: Any], raw)
        func number(_ key: String) throws -> Double {
            try XCTUnwrap(report[key] as? NSNumber, "Missing \(key): \(raw)").doubleValue
        }
        for key in ["sourceOK", "attachmentsOK", "mixedSourceOK", "pageSourceOK", "pageBubble36", "lineBreakRulesOK", "spanningQuoteOK", "nonDialogueOK"] {
            XCTAssertEqual(report[key] as? Bool, true, "\(key): \(raw)")
        }
        XCTAssertEqual(report["quoteSource"] as? String,
            "“报告，守望者赵空城，在老住宅区发现鬼面王……”他打开耳麦，声音十分平静。 \u{FFFC}", raw)
        XCTAssertEqual(try number("cases"), 7, raw)
        XCTAssertGreaterThan(try number("rowsChecked"), 45, raw)
        XCTAssertGreaterThan(try number("bubbles"), 50, raw)
        XCTAssertGreaterThan(try number("eligibleSuffixes"), 5, raw)
        XCTAssertEqual(try number("orphanBubbles"), 0, "No detached comment icon, even if the preceding row was full; \(raw)")
        XCTAssertEqual(try number("eligibleOrphans"), 0, "A bubble must not be alone when its composed final character + closing punctuation + separator + attachment fit; \(raw)")
        XCTAssertGreaterThan(try number("pageEligibleSuffixes"), 0, raw)
        XCTAssertEqual(try number("pageOrphans"), 0, raw)
        XCTAssertEqual(try number("pageEligibleOrphans"), 0, raw)
        XCTAssertGreaterThan(try number("pageParagraphs"), 7, raw)
        XCTAssertGreaterThan(try number("renderedPages"), 0, raw)
        XCTAssertGreaterThan(try number("withinPairs"), 5, raw)
        XCTAssertGreaterThan(try number("acrossPairs"), 3, raw)
        XCTAssertLessThanOrEqual(try number("maxWithinError"), 0.75, raw)
        XCTAssertLessThanOrEqual(try number("maxAcrossError"), 0.75, raw)
        let breaks = try XCTUnwrap(report["isolatedNativeBreaks"] as? [String: [String]], raw)
        XCTAssertFalse(try XCTUnwrap(breaks["word-production"]).isEmpty, raw)
        XCTAssertFalse(try XCTUnwrap(breaks["word-no-strategy"]).isEmpty, raw)
        XCTAssertFalse(try XCTUnwrap(breaks["character-no-strategy"]).isEmpty, raw)
        let variants = try XCTUnwrap(report["quoteVariants"] as? [String: [[String: Any]]], raw)
        for name in ["ascii-ellipsis", "ascii-six-dots", "curly-ellipsis-diagnostic",
                     "curly-six-dots-diagnostic"] {
            XCTAssertGreaterThan(try XCTUnwrap(variants[name], raw).count, 1, "\(name): \(raw)")
        }
        let quotes = try XCTUnwrap(report["quoteRows"] as? [[String: Any]], raw)
        XCTAssertGreaterThan(quotes.count, 1, raw)
        XCTAssertTrue(quotes.contains { ($0["text"] as? String)?.contains("在老住宅区发现鬼面王……”") == true }, raw)
        XCTAssertGreaterThan(try number("spanningPages"), 2, raw)
        let bubble = try XCTUnwrap(report["bubble36Rows"] as? [[String: Any]], raw)
        XCTAssertGreaterThan(bubble.count, 1, raw)
        XCTAssertFalse(bubble.last?["text"] as? String == " \u{FFFC}", "Reported bubble 36 must not occupy an otherwise empty line: \(raw)")
        // No global "all internal lines are 100% filled" assertion. Only the actual
        // premature 鬼面 | 王…… break is a regression when another Han could fit.
        XCTAssertEqual((report["failingRows"] as? [[String: Any]])?.count, 0, raw)
    }

    func testReferencePageIsActuallyRenderedByProductionView() {
        let app = XCUIApplication()
        app.launchArguments = ["--layout-audit-mode", "--layout-audit-reference-page"]
        app.launch()
        let footer = app.staticTexts["reader-footer-page"]
        XCTAssertTrue(footer.waitForExistence(timeout: 12))
        XCTAssertTrue(footer.label.contains("/"), footer.label)
        XCTAssertFalse(footer.label == "10/15", "Do not fabricate reported chapter pagination")
        XCTAssertTrue(app.staticTexts["reader-footer-title"].label.contains("第23章 鬼面王"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "reported-layout-production-26pt-natural-page"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments.append("--layout-audit-first-page")
        app.launch()
        XCTAssertTrue(app.staticTexts["reader-footer-page"].waitForExistence(timeout: 12))
        let first = XCTAttachment(screenshot: app.screenshot())
        first.name = "reported-dialogue-production-26pt-first-page"
        first.lifetime = .keepAlways
        add(first)
    }
}

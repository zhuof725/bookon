import XCTest

final class BottomBubbleTests: XCTestCase {
    private func attachJSON(_ object: Any, name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAllTextPagesBottomBaselinesAndOriginalParagraphBubbles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--bottom-bubble-mode"]
        app.launch()
        let inspect = app.buttons["inspect-bottom-bubble"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 10))
        inspect.tap()
        let output = app.staticTexts["bottom-bubble-report"]
        let ready = NSPredicate { _, _ in output.exists && output.label.hasPrefix("{") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: output)],
                                     timeout: 60), .completed)
        let data = try XCTUnwrap(output.label.data(using: .utf8))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try attachJSON(report, name: "bottom-bubble-production-textkit-report.json")
        let failures = try XCTUnwrap(report["failures"] as? [[String: Any]])
        try attachJSON(failures, name: "bottom-bubble-failure-samples.json")
        let counts = try XCTUnwrap(report["counters"] as? [String: NSNumber])
        let errors = try XCTUnwrap(report["maximumErrors"] as? [String: NSNumber])
        func count(_ key: String) throws -> Int {
            try XCTUnwrap(counts[key], "Missing coverage counter: \(key)").intValue
        }
        XCTAssertEqual(report["schemaVersion"] as? Int, 1)
        XCTAssertEqual(report["fontSizes"] as? [Double], [19, 24, 28, 32])
        XCTAssertEqual(try count("cases"), 34) // Core matrix + 20/23pt screenshot geometry.
        XCTAssertEqual(try count("onFirstPages"), 18)
        XCTAssertEqual(try count("offFirstPages"), 16)
        XCTAssertEqual(try count("bottomTerminalPages"), 18)
        XCTAssertEqual(try count("longTitlePages"), 8)
        XCTAssertEqual(try count("sparseBottomPages"), 8)
        XCTAssertEqual(try count("singleLineBottomPages"), 4)
        XCTAssertEqual(try count("topBaselinePages"), try count("pages"))
        XCTAssertEqual(try count("bottomBaselinePages") + count("naturalTopPages"), try count("pages"))
        XCTAssertGreaterThan(try count("bottomBaselinePages"), 0)
        XCTAssertEqual(try count("boundedGapExpansionChecks"), try count("pages"))
        XCTAssertEqual(try count("offTopBaselinePages"), try count("bottomDisabledPages"))
        XCTAssertEqual(try count("alignmentFlagChecks"), try count("pages"))
        XCTAssertEqual(try count("bottomEnabledPages") + count("bottomDisabledPages"), try count("pages"))
        XCTAssertEqual(try count("sourceReassemblyChecks"), 34)
        XCTAssertEqual(try count("equalSizeBubbleComparisons"), 12)
        XCTAssertEqual(report["pixelReferenceLoaded"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(report["bubbleOutlineMinIoU"] as? Double), 0.90)
        XCTAssertLessThanOrEqual(try XCTUnwrap(report["bubbleInkBoxErrorPixels"] as? Double), 2)
        XCTAssertLessThanOrEqual(try XCTUnwrap(report["bubbleCanvasSizeError"] as? Double), 0.02)
        XCTAssertLessThanOrEqual(try XCTUnwrap(report["bubbleDigitInkBoxErrorPixels"] as? Double), 2)
        for key in ["referenceAttachmentGeometryError", "referenceCanvasBaselineError",
                    "referenceInkBaselineError", "referenceInkTailAdvanceError"] {
            XCTAssertLessThanOrEqual(try XCTUnwrap(errors[key]).doubleValue, 0.5, key)
        }
        for key in ["onMiddlePages", "offMiddlePages", "onLastPages", "offLastPages",
                    "distributedGapPages", "naturalHeightBottomPages", "continuationParagraphs",
                    "splitFragments", "paragraphBoundaryPairs", "withinParagraphPairs",
                    "zeroCommentHasNoBubbleChecks", "bubbleParagraphs", "actualRows"] {
            XCTAssertGreaterThan(try count(key), 0, "Missing coverage: \(key)")
        }
        for key in ["topBaselineError", "naturalLastBaselineError", "gapPolicyError",
                    "bottomBaselineError", "offTopBaselineError", "bodyHeightError", "bodyWidthError",
                    "renderedWidthError", "actualLineHeightError", "localBaselineError",
                    "withinParagraphGapError", "paragraphBaselineGapError", "firstLineIndentError",
                    "lineOverflowError", "bodyTopOverflowError", "capacityOverflowError",
                    "titleTopError", "titleHeightError", "bubbleGlyphRectError",
                    "bubbleImageWidthError", "bubbleImageHeightError", "bubbleHorizontalOverflowError",
                    "bubbleVerticalOverflowError", "bubbleTextOverlapError"] {
            let value = try XCTUnwrap(errors[key], "Missing measured error: \(key)").doubleValue
            XCTAssertLessThanOrEqual(value, 0.75, "\(key)=\(value); see failure-samples.json")
        }
        for key in ["equalBubbleImagewidthError", "equalBubbleImageheightError", "equalBubbleRectSizeError"] {
            let value = try XCTUnwrap(errors[key], "Missing bubble comparison: \(key)").doubleValue
            XCTAssertLessThanOrEqual(value, 0.01, key)
        }
        let pages = try XCTUnwrap(report["pageSamples"] as? [[String: Any]])
        XCTAssertEqual(pages.count, try count("pages"))
        for page in pages {
            let bottom = try XCTUnwrap(page["bottomJustify"] as? Bool)
            let shouldFill = try XCTUnwrap(page["shouldFill"] as? Bool)
            XCTAssertEqual(page["alignsBodyBottom"] as? Bool, shouldFill)
            let font = try XCTUnwrap(page["fontSize"] as? Double)
            let number = try XCTUnwrap(page["pageNumber"] as? Int)
            let total = try XCTUnwrap(page["pageCount"] as? Int)
            if bottom && number < total {
                XCTAssertTrue(shouldFill, "Every ordinary text page must fill both ends")
            }
            let fixture = try XCTUnwrap(page["fixture"] as? String)
            let detail = "\(fixture), \(font)pt, page \(number), bottom=\(bottom)"
            // Top alignment is mandatory for EVERY page (including short
            // and single-row pages). Last-row expectations are independently
            // computed from capacity/natural height, never just the output flag.
            let first = try XCTUnwrap(page["firstBaseline"] as? Double)
            let targetFirst = try XCTUnwrap(page["targetFirstBaseline"] as? Double)
            XCTAssertEqual(first, targetFirst, accuracy: 0.75, detail)
            let last = try XCTUnwrap(page["lastBaseline"] as? Double)
            let targetLast = try XCTUnwrap(page["expectedLastBaseline"] as? Double)
            XCTAssertEqual(last, targetLast, accuracy: 0.75, detail)
            if shouldFill {
                XCTAssertTrue(bottom, detail)
                XCTAssertEqual(last, try XCTUnwrap(page["targetLastBaseline"] as? Double), accuracy: 0.75, detail)
            }
            if fixture == "short" || fixture == "single-line" {
                XCTAssertFalse(shouldFill, detail)
                XCTAssertTrue(page["justifiedGap"] is NSNull, detail)
            }
            XCTAssertGreaterThan(try XCTUnwrap(page["actualRowCount"] as? Int), 0, detail)
            // Every continuation's glyph x is checked in the harness, retained
            // in firstLineIndentError; normal-page JSON is intentionally compact.
        }
        let cases = try XCTUnwrap(report["caseSamples"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 34)
        for font in [19.0, 24, 28, 32] {
            for bottom in [true, false] {
                let selected = cases.filter { ($0["fontSize"] as? Double) == font && ($0["bottomJustify"] as? Bool) == bottom }
                XCTAssertEqual(Set(selected.compactMap { $0["fixture"] as? String }),
                               Set(["multipage-long-title", "photo-590CCBC1", "short", "single-line"]))
            }
        }
        let reference = try XCTUnwrap(report["referenceBubbleSamples"] as? [[String: Any]])
        XCTAssertEqual(reference.count, 24) // Four comments at each of six sizes, zero count has no attachment.
        for font in [19.0, 20, 23, 24, 28, 32] {
            let samples = reference.filter { ($0["fontSize"] as? Double) == font }
            XCTAssertEqual(Set(samples.compactMap { $0["commentCount"] as? Int }), Set([1, 3, 4, 23]))
        }
        XCTAssertEqual(report["failureCount"] as? Int, 0, "See bottom-bubble-failure-samples.json")
        XCTAssertTrue(failures.isEmpty, "\(failures.count) failed checks; first: \(failures.first ?? [:])")
    }

    func testReferenceParagraphsAndTerminalPageScreenshots() {
        let app = XCUIApplication()
        for tail in [false, true] {
            app.launchArguments = ["--bottom-bubble-mode", "--bottom-bubble-reference"]
                + (tail ? ["--bottom-bubble-tail"] : [])
            app.launch()
            let footer = app.staticTexts["reader-footer-page"]
            XCTAssertTrue(footer.waitForExistence(timeout: 10))
            let pageNumbers = footer.label.split(separator: "/").compactMap { Int($0) }
            XCTAssertEqual(pageNumbers.count, 2)
            if pageNumbers.count == 2 {
                if tail {
                    XCTAssertEqual(pageNumbers[0], pageNumbers[1])
                    XCTAssertGreaterThan(pageNumbers[1], 1)
                } else {
                    XCTAssertEqual(pageNumbers[0], 1)
                }
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = tail ? "bottom-bubble-terminal-production-page"
                : "bottom-bubble-photo-590CCBC1-production-page"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}

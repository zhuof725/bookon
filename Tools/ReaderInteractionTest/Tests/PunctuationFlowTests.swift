import XCTest

final class PunctuationFlowTests: XCTestCase {
    private func audit() throws -> [String: Any] {
        let app = XCUIApplication()
        app.launchArguments = ["--punctuation-flow-mode"]
        app.launch()
        let button = app.buttons["inspect-punctuation-flow"]
        XCTAssertTrue(button.waitForExistence(timeout: 12))
        button.tap()
        let label = app.staticTexts["punctuation-flow-report"]
        let ready = NSPredicate { _, _ in label.exists && label.label.hasPrefix("{") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: label)],
                                    timeout: 60), .completed, String(label.label.prefix(500)))
        let json = label.label
        let attachment = XCTAttachment(string: json)
        attachment.name = "chapter23-new-image-six-dots-glyphs-and-bubble.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(json.data(using: .utf8)))
            as? [String: Any], String(json.prefix(500)))
    }

    func testSixDotsCurlyAndStraightQuotesRetainSourceAndStayWithBubble() throws {
        let report = try audit()
        func bool(_ key: String) -> Bool { report[key] as? Bool == true }
        func number(_ key: String) -> Int { (report[key] as? NSNumber)?.intValue ?? -1 }
        XCTAssertEqual(report["texts"] as? [String], [
            "面王损失一个核心队员，这是绝对的得不偿失！",
            "老赵，老赵！你听得见吗？\"", "砰——！",
            "井盖像是炮弹般被弹飞，冲天而起，黑洞洞的下水道口，一只狰狞的手臂猛地探出，紧接着一个比原先鬼面人大了数倍的怪物从中跃出！",
            "赵空城平静的看着这一幕，缓缓将手中的最后一块告示牌放下，咬破指尖，在告示牌表。涂上一横鲜血。",
            "“湘南，你还记得你曾立下的誓言吗......”",
            "赵空城注视着眼前的鬼面王，微微蹲下身，余光落在了"])
        XCTAssertEqual(report["counts"] as? [Int], [99, 99, 21, 57, 64, 99, 0])
        for key in ["pageSourceOK", "offsetsOK", "renderOK", "terminalNatural",
                    "stressSourceOK", "latinOK"] {
            XCTAssertTrue(bool(key), "\(key): \(String(describing: report[key]))")
        }
        XCTAssertGreaterThanOrEqual(number("renderedPages"), 2,
                                    "Both widths must be hosted; natural pagination may fit either on one page")
        XCTAssertGreaterThan(number("pageParagraphs"), 12)
        XCTAssertGreaterThan(number("stressPages"), 1)
        XCTAssertEqual((report["stressBadPageStarts"] as? [String])?.count, 0)
        let cases = try XCTUnwrap(report["cases"] as? [[String: Any]])
        let failures = try XCTUnwrap(report["failures"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 30)
        // On failure show the exact offending row(s) and glyph samples from the JSON
        // attachment rather than claiming a known screenshot/codepoint mismatch.
        XCTAssertTrue(failures.isEmpty, "Punctuation or attachment flow: \(failures)")
        for width in [351, 362] {
            func sample(_ name: String) throws -> [String: Any] {
                try XCTUnwrap(cases.first { ($0["id"] as? String) == name
                    && ($0["width"] as? NSNumber)?.intValue == width }, "\(name)/\(width)")
            }
            let literal = try sample("screenshot-5")
            let raw = try XCTUnwrap(literal["raw"] as? String)
            XCTAssertEqual(raw.filter { $0 == "." }.count, 6, "Original six U+002E, not U+2026")
            XCTAssertFalse(raw.contains("……"))
            XCTAssertEqual((literal["dotSteps"] as? [Double])?.count, 5,
                           "Every pair of consecutive periods has an actual glyph advance")
            XCTAssertEqual(literal["quoteClosesWithBubble"] as? Bool, true)
            XCTAssertEqual(literal["tailAndBubbleSameRow"] as? Bool, true)
            XCTAssertEqual((literal["clusterRows"] as? [Int])?.count, 6)
            let dialogue = try sample("screenshot-1")
            XCTAssertEqual(dialogue["tailAndBubbleSameRow"] as? Bool, true,
                           "The terminal quote and count 99 cannot occupy separate lines")
            for quotes in ["ascii", "curly", "curly-ascii", "ascii-curly"] {
                for dots in ["six-dots", "two-ellipsis"] {
                    let variant = try sample("\(quotes)-\(dots)")
                    XCTAssertEqual(variant["quoteClosesWithBubble"] as? Bool, true,
                                   "\(quotes)/\(dots)/\(width): \(variant["rows"] ?? [])")
                    let expectedDots = dots == "six-dots" ? 5 : 0
                    XCTAssertEqual((variant["dotSteps"] as? [Double])?.count, expectedDots)
                    XCTAssertEqual((variant["focusGlyphs"] as? [[String: Any]])?.isEmpty, false)
                }
            }
        }
        XCTAssertLessThanOrEqual((report["maxLatinAdvanceError"] as? NSNumber)?.doubleValue ?? .infinity,
                                 0.25, "Western inch marks, contractions and Latin runs must retain native advances")
    }

    func testRealPageContentViewShowsBothWidthsAndUnforcedTerminal() {
        for width in [362, 351] {
            let app = XCUIApplication()
            app.launchArguments = ["--punctuation-flow-mode", "--punctuation-flow-reference-page"]
            if width == 351 { app.launchArguments.append("--punctuation-flow-width-351") }
            app.launch()
            let footer = app.staticTexts["reader-footer-page"]
            XCTAssertTrue(footer.waitForExistence(timeout: 15), "\(width) pt actual PageContentView")
            XCTAssertTrue(footer.label.contains("/"))
            XCTAssertNotEqual(footer.label, "13/15", "Fixture has no earlier chapter content")
            XCTAssertTrue(app.staticTexts["reader-footer-title"].label.contains("第23章 鬼面王"))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "chapter23-quotation-bubble-production-26pt-\(width)pt"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
            app.launchArguments.append("--punctuation-flow-page=0")
            app.launch()
            XCTAssertTrue(app.staticTexts["reader-footer-page"].waitForExistence(timeout: 15))
            let first = XCTAttachment(screenshot: app.screenshot())
            first.name = "chapter23-first-fragment-and-bubbles-production-\(width)pt"
            first.lifetime = .keepAlways
            add(first)
            app.terminate()
        }
    }
}

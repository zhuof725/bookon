import XCTest

final class ReaderPageFlowTests: XCTestCase {
    func testPageBreaksMatchNativeLinesAndPreserveSource() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-page-flow-mode"]
        app.launch()
        let inspect = app.buttons["inspect-reader-page-flow"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 10))
        inspect.tap()
        let output = app.staticTexts["reader-page-flow-report"]
        let ready = NSPredicate { _, _ in output.exists && output.label.hasPrefix("{") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: output)],
                                    timeout: 60), .completed)
        let data = try XCTUnwrap(output.label.data(using: .utf8))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let detail = XCTAttachment(string: output.label)
        detail.name = "reader-page-line-fragment-audit"
        detail.lifetime = .keepAlways
        add(detail)
        XCTAssertEqual(report["cases"] as? Int, 4, output.label)
        XCTAssertGreaterThan(report["splits"] as? Int ?? 0, 8, output.label)
        XCTAssertGreaterThan(report["continuations"] as? Int ?? 0, 8, output.label)
        XCTAssertEqual((report["cuts"] as? [[String: Any]])?.count, 8, output.label)
        for key in ["sourceOK", "boundaryOK", "offsetsOK", "heightsOK",
                    "commentOK", "titleOK", "quoteOK"] {
            XCTAssertEqual(report[key] as? Bool, true, "\(key): \(output.label)")
        }
    }
}

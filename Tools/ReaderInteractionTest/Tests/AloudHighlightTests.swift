import XCTest

final class AloudHighlightTests: XCTestCase {
    func testPagedHighlightProgressAndClear() throws { try verify(paged: true) }
    func testScrollHighlightProgressAndClear() throws { try verify(paged: false) }

    private func inspect(_ app: XCUIApplication) throws -> [String: Any] {
        app.buttons["aloud.inspect"].tap()
        let output = app.staticTexts["aloud.report"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        let ready = NSPredicate { _, _ in output.label.hasPrefix("{") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: output)], timeout: 5), .completed)
        let data = try XCTUnwrap(output.label.data(using: .utf8))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return report
    }
    private func rows(_ report: [String: Any]) throws -> [[String: Any]] {
        let rows = try XCTUnwrap(report["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        return rows
    }
    private func painted(_ row: [String: Any]) throws -> [Int] { try XCTUnwrap(row["painted"] as? [Int]) }
    private func stable(_ old: [[String: Any]], _ new: [[String: Any]]) throws {
        for (a,b) in zip(old,new) {
            XCTAssertEqual(a["text"] as? String, b["text"] as? String)
            XCTAssertEqual(a["breaks"] as? [Int], b["breaks"] as? [Int])
            XCTAssertEqual(try XCTUnwrap(a["height"] as? Double), try XCTUnwrap(b["height"] as? Double), accuracy: 0.01)
            XCTAssertEqual(b["permanentBackground"] as? Bool, false)
            XCTAssertEqual(b["attachment"] as? Bool, true)
        }
    }
    private func verify(paged: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--aloud-highlight"] + (paged ? ["--aloud-paged"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["aloud.first"].waitForExistence(timeout: 10))
        let baseline = try rows(inspect(app))
        XCTAssertTrue(try baseline.allSatisfy { try painted($0).isEmpty })
        app.buttons["aloud.first"].tap()
        let first = try inspect(app)
        let firstRows = try rows(first)
        let prefix = try XCTUnwrap(first["prefixUTF16"] as? Int)
        XCTAssertGreaterThan(prefix, 3)
        XCTAssertEqual(try painted(firstRows[0]), Array(0..<prefix))
        XCTAssertTrue(try painted(firstRows[1]).isEmpty)
        try stable(baseline, firstRows)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = paged ? "aloud-highlight-page" : "aloud-highlight-scroll"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["aloud.second"].tap()
        let second = try inspect(app)
        let secondRows = try rows(second)
        let length = try XCTUnwrap(second["textUTF16"] as? Int)
        XCTAssertTrue(try painted(secondRows[0]).isEmpty)
        XCTAssertEqual(try painted(secondRows[1]), Array(0..<length), "附件和分隔空格不能着色")
        try stable(baseline, secondRows)
        app.buttons["aloud.width"].tap()
        let resized = try rows(inspect(app))
        XCTAssertLessThan(try XCTUnwrap(resized[1]["width"] as? Double), try XCTUnwrap(secondRows[1]["width"] as? Double))
        XCTAssertEqual(try painted(resized[1]), Array(0..<length), "重排后高亮不能消失")
        app.buttons["aloud.clear"].tap()
        let cleared = try rows(inspect(app))
        XCTAssertTrue(try cleared.allSatisfy { try painted($0).isEmpty })
        try stable(resized, cleared)
    }
}

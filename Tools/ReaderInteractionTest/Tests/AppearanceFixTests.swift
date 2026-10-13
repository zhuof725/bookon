import XCTest
import UIKit

final class AppearanceFixTests: XCTestCase {
    func testWallpaperOnRealAppearancePageAndTransparentPNGAssets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--appearance-fix-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); defer { app.terminate() }
        let report = app.staticTexts["fix.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 15))
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'PASS'"), object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 20), .completed, report.label)
        XCTAssertTrue(app.buttons["theme.add"].waitForExistence(timeout: 10))
        // Side gutter of the actual production scroll view must show blue wallpaper,
        // not a white page background. Wait via predicate for the async image loader.
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = app.screenshot().image.cgImage else { return false }
            let x = Int(Double(image.width) * 0.02), y = Int(Double(image.height) * 0.5)
            guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return false }
            var b = [UInt8](repeating: 0, count: 4)
            b.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return Int(b[2]) > Int(b[0]) + 60
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "appearance-wallpaper-fixed"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["theme.add"].tap()
        let tab = app.buttons["theme.editor.row.tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
        let icon = app.buttons["theme.editor.tab.icon.shelf"]
        for _ in 0..<4 where !icon.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(icon.waitForExistence(timeout: 5)); icon.tap()
        XCTAssertTrue(app.buttons["theme.editor.tab.icon.import"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["内置图标"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'theme.editor.tab.icon.grid.'")).count, 0)
        let picker = XCTAttachment(screenshot: app.screenshot()); picker.name = "tab-import-only"
        picker.lifetime = .keepAlways; add(picker)
    }
}

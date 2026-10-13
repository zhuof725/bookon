import XCTest
import UIKit

final class NativeTabsGlassTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { app.terminate() }
    private func start(_ route: String) {
        app.launchArguments = [route, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }
    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name
        item.lifetime = .keepAlways; add(item)
    }
    func testSystemTabsSelectionIconsAndPush() throws {
        guard #available(iOS 26.0, *) else { XCTFail("Requires actual iOS 26 runtime"); return }
        start("--native-tabs-mode")
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Must be a real system TabBar")
        for (title, page) in [("统计", "statistics"), ("我的", "profile"), ("书架", "shelf")] {
            let button = bar.buttons[title]
            XCTAssertTrue(button.exists); button.tap()
            XCTAssertTrue(app.staticTexts["native.page.\(page)"].waitForExistence(timeout: 5))
            XCTAssertTrue(button.isSelected)
        }
        app.buttons["native.icon"].tap()
        XCTAssertTrue(bar.buttons["书架"].isSelected)
        shot("ios26-native-tabs")
        app.buttons["native.push"].tap()
        XCTAssertTrue(app.staticTexts["native.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(bar.exists, "Pushed content replaces root tab bar")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
    }
    private func pixels() throws -> [Double] {
        let sample = app.otherElements["glass.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = Double(image.width) / app.frame.width
        let rect = sample.frame.insetBy(dx: 30, dy: 30)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
            width: rect.width * scale, height: rect.height * scale)))
        let w = crop.width, h = crop.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // RGB adjacent-pixel variation captures fine checks; broad color variation
        // distinguishes actual translucent blur from painting an opaque flat card.
        var edge = 0.0, sum = 0.0, squared = 0.0
        for y in 0..<h {
            for x in 1..<w {
                let i = (y * w + x) * 4
                for c in 0..<3 { edge += abs(Double(bytes[i+c]) - Double(bytes[i-4+c])) }
                let chroma = Double(bytes[i]) - Double(bytes[i+2])
                sum += chroma; squared += chroma * chroma
            }
        }
        let count = Double(h * (w - 1))
        return [edge / count, squared / count - pow(sum / count, 2)]
    }
    func testFrostedActuallyBlursBackdropNotOpaqueTint() throws {
        start("--native-glass-mode")
        let transparent = try pixels(); shot("glass-transparent")
        app.buttons["glass.mode.frosted"].tap()
        XCTAssertEqual(app.staticTexts["glass.current"].label, "frosted")
        let frosted = try pixels(); shot("glass-frosted")
        app.buttons["glass.mode.opaque"].tap()
        let opaque = try pixels(); shot("glass-opaque")
        let evidence = XCTAttachment(string: "transparent=\(transparent) frosted=\(frosted) opaque=\(opaque)")
        evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertGreaterThan(transparent[0], 10)
        XCTAssertLessThan(frosted[0], transparent[0] * 0.65, "Fine backdrop edges must really blur")
        XCTAssertGreaterThan(frosted[1], opaque[1] + 5, "Blur must preserve background color, not solid fill")
        XCTAssertLessThan(opaque[1], 5)
    }
}

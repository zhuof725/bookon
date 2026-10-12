import XCTest

final class ThemeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app?.terminate() }

    private func launch(dark: Bool = false) {
        app.launchArguments = ["--theme-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if dark { app.launchArguments.append("--theme-dark") }
        app.launch()
        XCTAssertTrue(app.switches["theme.toggle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["theme.mode"].label, dark ? "深色模式" : "浅色模式")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func toggle(_ element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 4))
        let before = try XCTUnwrap(element.value as? String)
        element.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed)
    }

    private func exercise(dark: Bool) throws {
        launch(dark: dark)
        let mode = dark ? "dark" : "light"
        XCTAssertTrue(app.sliders["theme.slider"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "theme.link").firstMatch.exists)
        capture("appearance-\(mode)-native-controls")
        try toggle(app.switches["theme.toggle"])
        app.sliders["theme.slider"].adjust(toNormalizedSliderPosition: 0.7)
        app.buttons["theme.openSheet"].tap()
        XCTAssertTrue(app.switches["theme.sheet.toggle"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.sliders["theme.sheet.slider"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "theme.sheet.link").firstMatch.exists)
        capture("appearance-\(mode)-inherited-sheet")
        try toggle(app.switches["theme.sheet.toggle"])
        app.sliders["theme.sheet.slider"].adjust(toNormalizedSliderPosition: 0.3)
        app.buttons["theme.sheet.done"].tap()
        let navigation = app.buttons["theme.navigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 4))
        navigation.tap()
        XCTAssertTrue(app.staticTexts["theme.destination"].waitForExistence(timeout: 4))
    }

    func testLightNativeControlsAndInheritedSheet() throws { try exercise(dark: false) }
    func testDarkNativeControlsAndInheritedSheet() throws { try exercise(dark: true) }

    func testProductionPaletteIsNeutralAndHighContrastInBothModes() throws {
        launch()
        let probe = app.staticTexts["theme.palette"]
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        let raw = try XCTUnwrap(probe.value as? String)
        let palette = try JSONDecoder().decode([String: [String: [Double]]].self, from: Data(raw.utf8))
        let names: Set<String> = ["accent", "background", "surface", "secondary", "selection",
                                  "border", "placeholderTop", "placeholderBottom", "highlight"]
        XCTAssertEqual(Set(palette.keys), Set(["light", "dark"]))
        for mode in ["light", "dark"] {
            let tokens = try XCTUnwrap(palette[mode])
            XCTAssertEqual(Set(tokens.keys), names)
            for (name, rgba) in tokens {
                XCTAssertEqual(rgba.count, 4, "\(mode).\(name)")
                guard rgba.count == 4 else { continue }
                for channel in rgba { XCTAssertTrue(channel.isFinite && (0...1).contains(channel)) }
                XCTAssertEqual(rgba[0], rgba[1], "\(mode).\(name): red != green")
                XCTAssertEqual(rgba[1], rgba[2], "\(mode).\(name): green != blue")
                XCTAssertEqual(rgba[3], 1, "Production palette must be opaque")
            }
            let accent = try XCTUnwrap(tokens["accent"]?.first)
            let background = try XCTUnwrap(tokens["background"]?.first)
            func luminance(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let a = luminance(accent), b = luminance(background)
            XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 7, mode)
        }
    }
}

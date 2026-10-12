import XCTest
import UIKit

final class CoverPersistenceTests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureID = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        fixtureID = UUID().uuidString
    }

    override func tearDownWithError() throws { app?.terminate() }

    private func launch(seed: Bool) {
        app.launchEnvironment["COVER_PERSISTENCE_FIXTURE_ID"] = fixtureID
        app.launchArguments = ["--cover-persistence-mode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if seed { app.launchArguments.append("--cover-persistence-seed") }
        app.launch()
        expect("cover.fixture", contains: seed ? "PASS seeded legacy-remapped" : "PASS reopened no-reseed")
        XCTAssertTrue(app.staticTexts["cover.fixture"].label.contains(fixtureID))
        XCTAssertTrue(app.staticTexts["cover.fixture"].label.contains("legado-cover://local/900150983cd24fb0d6963f7d28e17f72/cover.img"))
        expect("cover.loader", contains: "image=present source=same")
    }

    private func expect(_ id: String, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts[id]
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, element.label, file: file, line: line)
    }

    func testStaleContainerMigrationSurvivesProcessRelaunchAndHome() {
        launch(seed: true)
        captureRenderedCover("cover-01-seeded-legacy-remapped")
        let before = app.staticTexts["cover.loader"].label
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        expect("cover.loader", contains: "image=present source=same")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: app.staticTexts["cover.loader"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Scene activation probe did not advance")
        captureRenderedCover("cover-02-after-home-activate")

        // A real process termination, retaining only fixture files and env UUID.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        launch(seed: false)
        captureRenderedCover("cover-03-process-relaunch-no-reseed")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        expect("cover.loader", contains: "image=present source=same")
        captureRenderedCover("cover-04-relaunch-after-home")
    }

    func testNativeLoaderCancellationFailureAndRecovery() {
        launch(seed: true)
        captureRenderedCover("cover-loader-before")
        app.buttons["cover.regression"].tap()
        expect("cover.checks", contains: "PASS loader precancel retained-failure restored-retry different-cleared")
        expect("cover.loader", contains: "image=present source=same")
        app.buttons["cover.file"].tap()
        expect("cover.checks", contains: "PASS file=missing image-retained")
        captureRenderedCover("cover-loader-file-unavailable-protected-data-retry")
        app.buttons["cover.file"].tap()
        expect("cover.checks", contains: "PASS file=restored image-retained")
        captureRenderedCover("cover-loader-after-restore-retry")
    }

    func testCanonicalReferenceIdentityTraversalAndRemoteURLs() {
        launch(seed: true)
        app.buttons["cover.resolver"].tap()
        expect("cover.checks", contains: "PASS resolver md5 serialization identity traversal remote")
        captureRenderedCover("cover-resolver-contract")
    }

    // BookCoverImage deliberately hides its decorative image from AX. Verify
    // native fixture pixels in the actual screenshot, independently of the
    // observable loader report. Nothing else on this screen uses these colors.
    private func captureRenderedCover(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return self.hasFixturePixels(self.app.screenshot().image)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 8), .completed,
                       "Production BookCoverImage did not render both PNG color fields", file: file, line: line)
        let screenshot = app.screenshot()
        XCTAssertTrue(hasFixturePixels(screenshot.image), file: file, line: line)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let probes = XCTAttachment(string: app.staticTexts["cover.fixture"].label + "\n" + app.staticTexts["cover.loader"].label + "\n" + app.staticTexts["cover.checks"].label)
        probes.name = name + "-loader-evidence"
        probes.lifetime = .keepAlways
        add(probes)
    }

    private func hasFixturePixels(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        // Normalize color layout rather than assuming simulator screenshot BGRA.
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let pixels = buffer.bindMemory(to: UInt8.self)
            var magenta = 0, cyan = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                if r > 220 && g < 35 && b > 220 { magenta += 1 }
                if r < 35 && g > 220 && b > 220 { cyan += 1 }
            }
            return magenta > 1000 && cyan > 1000
        }
    }
}

import XCTest

/// 音频书播放台回归：起播、下一章预载、队列快路径切章、章末自动连播、停止清理。
/// 音频来自测试 App 内的回环服务器（打包的静音 m4a），不访问外网。
final class AudioPlayerTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws { app.terminate() }

    private func launch() {
        app.launchArguments = ["--audio-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["audio.state"].waitForExistence(timeout: 10))
    }

    private func waitForState(_ text: String, timeout: TimeInterval, _ message: String) {
        let state = app.staticTexts["audio.state"]
        let wait = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: timeout), .completed,
                       "\(message) — state: \(state.label)")
    }

    func testFirstChapterPlaysAndPrerollsNext() {
        launch()
        waitForState("chapter=0", timeout: 15, "first chapter should load")
        waitForState("playing=true", timeout: 15, "playback should start")
        waitForState("queued=1", timeout: 25, "next chapter should be prerolled into the queue")
    }

    func testNextChapterUsesPrerolledQueue() {
        launch()
        waitForState("queued=1", timeout: 25, "next chapter should be prerolled")
        app.buttons["audio.next"].tap()
        waitForState("via=queue", timeout: 5, "queued hop should be used")
        waitForState("chapter=1", timeout: 8, "player should switch to chapter 1")
        waitForState("playing=true", timeout: 8, "playback should continue across the switch")
    }

    func testChapterEndAdvancesThroughQueue() {
        launch()
        waitForState("queued=1", timeout: 25, "next chapter should be prerolled")
        waitForState("chapter=1", timeout: 45, "chapter end should advance through the queue")
        waitForState("adopted=1", timeout: 5, "reader should be told about the adopted chapter")
        waitForState("queued=2", timeout: 25, "the following chapter should be prerolled too")
    }

    func testStopClearsPlaybackState() {
        launch()
        waitForState("playing=true", timeout: 15, "playback should start")
        app.buttons["audio.stop"].tap()
        waitForState("chapter=-1", timeout: 5, "stop should clear the chapter")
        waitForState("playing=false", timeout: 5, "stop should end playback")
    }
}

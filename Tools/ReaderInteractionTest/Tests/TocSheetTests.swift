import XCTest

/// 目录页：书源时间显示、已缓存标识 + 预缓存进度条（在「我的」页面，非目录页）。
/// 全部离线运行：合成章节与合成预缓存服务，不访问网络与真实缓存。
final class TocSheetTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reader-toc-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["precache.start"].waitForExistence(timeout: 10))
        return app
    }

    private func row(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.buttons["reader.toc.row.\(index)"]
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 8) {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [e], timeout: timeout), .completed,
                       "等待 \(element.identifier) 变为「\(value)」超时")
    }

    private func waitForLabel(_ element: XCUIElement, contains fragment: String, timeout: TimeInterval = 25) {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [e], timeout: timeout), .completed,
                       "等待 \(element.identifier) 包含「\(fragment)」超时")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// ① 时间显示 + ④ 已缓存标识（目录页）。
    func testRowsShowSourceTimeAndCacheMarks() {
        let app = launch()
        let first = row(app, 1)
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(first.label.contains("语言课1"), first.label)
        XCTAssertTrue(first.label.contains("2026-10-01"), "目录行应显示书源更新时间：\(first.label)")
        waitForValue(row(app, 5), "已缓存")
        XCTAssertTrue(row(app, 5).label.contains("3分钟前"), row(app, 5).label)
        XCTAssertEqual(row(app, 9).value as? String, "已缓存")
        XCTAssertEqual(row(app, 5).value as? String, "已缓存", "VIP 章节同样显示缓存标识")
        XCTAssertEqual(row(app, 3).value as? String, "未缓存")
        XCTAssertFalse(row(app, 2).label.contains("2026"), "没有时间的章节不显示时间：\(row(app, 2).label)")
        capture(app, "reader-toc-rows")
        row(app, 7).tap()
        XCTAssertEqual(app.staticTexts["reader.toc.harness.selection"].label, "selected=7")
    }

    /// ③ 预缓存进度条在「我的」页面，完成窗口并跳过已缓存章节。
    func testPrecacheProgressCompletesWindowAndSkipsCached() {
        let app = launch()
        waitForValue(row(app, 5), "已缓存")
        app.buttons["precache.start"].tap()
        let status = app.staticTexts["precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("正在预缓存"), status.label)
        XCTAssertTrue(app.progressIndicators["precache.bar"].exists, "预缓存应显示进度条")
        capture(app, "precache-running")
        waitForLabel(status, contains: "预缓存完成")
        XCTAssertEqual(row(app, 9).value as? String, "已缓存")
        // 默认 10 章窗口（第 3~12 章）里有 3 章打开前已缓存：不应重复请求书源。
        XCTAssertEqual(app.staticTexts["reader.toc.harness.loads"].label, "loads=7")
        capture(app, "precache-finished")
    }

    /// ③ 预缓存失败即停并保留进度，重试从失败处续跑。
    func testPrecacheFailureStopsAndRetryResumes() {
        let app = launch(["--reader-toc-fail=8"])
        waitForValue(row(app, 5), "已缓存")
        app.buttons["precache.start"].tap()
        let status = app.staticTexts["precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "进度状态应出现")
        waitForLabel(status, contains: "预缓存中断")
        XCTAssertTrue(status.label.contains("书源暂时拒绝访问"), status.label)
        XCTAssertTrue(app.buttons["precache.retry"].exists, "中断后应提供重试")
        capture(app, "precache-failed")
        app.buttons["precache.retry"].tap()
        waitForLabel(status, contains: "预缓存完成")
        XCTAssertEqual(app.staticTexts["reader.toc.harness.loads"].label, "loads=7")
    }

    /// ③ 预缓存可停止并关闭进度提示。
    func testPrecacheCanBeStoppedAndDismissed() {
        let app = launch(["--reader-toc-slow"])
        app.buttons["precache.start"].tap()
        let status = app.staticTexts["precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let stop = app.buttons["precache.stop"]
        let dismiss = app.buttons["precache.dismiss"]
        if stop.waitForExistence(timeout: 3) {
            // 检查与点击之间进度可能刚好跑完：重试点击，跑完则按完成处理。
            var tapped = false
            for _ in 0..<10 {
                if stop.exists { stop.firstMatch.tap(); tapped = true; break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            if tapped {
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '已停止' OR label CONTAINS '预缓存完成'"), object: status)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed, "停止或完成后应有结果文案")
            }
            XCTAssertFalse(stop.exists, "停止后不再显示停止按钮")
        }
        capture(app, "precache-stopped")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 20), "运行结束后应出现关闭按钮")
        dismiss.tap()
        XCTAssertFalse(status.waitForExistence(timeout: 2), "关闭后进度条应消失")
        XCTAssertTrue(app.buttons["precache.start"].exists, "停止后可再次预缓存")
    }

    /// 目录页右上「刷新目录」按钮：调用一次刷新并显示结果文案。
    func testTocRefreshButtonRunsAndShowsResult() {
        let app = launch()
        let refresh = app.buttons["reader.toc.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), "目录页应有刷新目录按钮")
        refresh.tap()
        let status = app.staticTexts["reader.toc.refreshStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "刷新时应显示状态")
        waitForLabel(status, contains: "目录已刷新", timeout: 8)
        XCTAssertTrue(status.label.contains("新增 2 章"), status.label)
        XCTAssertEqual(app.staticTexts["reader.toc.harness.refreshes"].label, "refreshes=1")
        capture(app, "reader-toc-refresh")
    }

    func testQuickPanelMetadataAndActions() {
        let app = launch(["--reader-quick"])
        app.buttons["reader.quick.open"].tap()
        XCTAssertTrue(app.staticTexts["reader.quick.position"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader.quick.position"].label.contains("4/386"))
        let refresh = app.buttons["reader.quick.refresh"]
        let source = app.buttons["reader.quick.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertLessThan(refresh.frame.minY, source.frame.minY)
        XCTAssertEqual(refresh.frame.minX, source.frame.minX, accuracy: 2)
        XCTAssertFalse(app.buttons["reader.quick.bookmarks"].isEnabled)
        for id in ["refresh", "toc", "clear", "login", "source", "rules", "browser"] {
            let button = app.buttons["reader.quick." + id]
            if !button.isHittable { app.swipeUp() }
            button.tap()
            let status = app.staticTexts["reader.quick.status"]
            XCTAssertTrue(status.waitForExistence(timeout: 4))
            XCTAssertEqual(status.label, "action=" + id)
        }
        capture(app, "reader-quick-panel")
    }

    /// 段评气泡：真实管理页新建/保存/选用，并核对自定义绘制尺寸与非法 SVG 拒绝。
    func testBubbleStyleEditorSavesAndChecksRuntime() {
        let app = launch(["--reader-bubble"])
        XCTAssertEqual(app.staticTexts["reader.bubble.square"].label, "square=true")
        XCTAssertEqual(app.staticTexts["reader.bubble.svgReject"].label, "svgReject=true")
        app.buttons["reader.bubble.open"].tap()
        XCTAssertTrue(app.buttons["bubble.new"].waitForExistence(timeout: 5))
        app.buttons["bubble.new"].tap()
        let save = app.buttons["bubble.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "编辑器应显示保存按钮")
        save.tap()
        XCTAssertTrue(app.buttons["bubble.new"].waitForExistence(timeout: 5), "保存后回到样式列表")
        XCTAssertFalse(app.buttons["bubble.save"].exists)
        capture(app, "reader-bubble-styles")
    }

    /// 滑条调整预缓存窗口章数（默认 10 章，1~50），起播按钮跟随窗口章数。
    func testWindowSliderControlsPrecacheCount() {
        let app = launch(["--reader-toc-setting"])
        let slider = app.sliders["precache.windowSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "预缓存窗口滑条应显示")
        XCTAssertEqual(app.staticTexts["precache.windowValue"].label, "10 章")
        slider.adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertEqual(app.staticTexts["precache.windowValue"].label, "1 章")
        app.buttons["precache.start"].tap()
        let status = app.staticTexts["precache.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        waitForLabel(status, contains: "预缓存完成")
        XCTAssertEqual(app.staticTexts["reader.toc.harness.loads"].label, "loads=1")
        capture(app, "precache-window-slider")
    }
}

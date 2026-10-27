import XCTest

/// AI 服务页：列表分组、配置状态、进入编辑页、视觉截图。
final class AIServiceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ai-service-mode", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProviderListAndEditor() {
        XCTAssertTrue(app.buttons["ai.provider.openai"].waitForExistence(timeout: 8))

        // 九家内置提供商都要在列表里。
        for id in ["openai", "claude", "gemini", "deepseek", "qwen", "doubao", "zhipu", "kimi", "siliconflow"] {
            XCTAssertTrue(app.buttons["ai.provider.\(id)"].exists, "缺少内置提供商 \(id)")
        }
        XCTAssertTrue(app.buttons["ai.addCustom"].exists, "缺少添加自定义服务")
        capture("ai-01-list")

        // 已配置的项应显示模型名，未配置的显示「未配置」。
        XCTAssertTrue(app.buttons["ai.provider.openai"].label.contains("gpt-4o-mini"),
                      "已配置项应显示模型名，实际：\(app.buttons["ai.provider.openai"].label)")
        XCTAssertTrue(app.buttons["ai.provider.claude"].label.contains("未配置"))

        // 进入 OpenAI 配置页。
        app.buttons["ai.provider.openai"].tap()
        XCTAssertTrue(app.buttons["ai.edit.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ai.edit.baseURL"].exists)
        XCTAssertTrue(app.textFields["ai.edit.model"].exists)
        XCTAssertTrue(app.buttons["ai.edit.fetchModels"].exists, "模型字段旁应有「获取模型」按钮")
        capture("ai-02-editor")

        // 返回列表。
        app.buttons["ai.edit.back"].tap()
        XCTAssertTrue(app.buttons["ai.provider.openai"].waitForExistence(timeout: 5))
    }

    func testCustomServiceFlow() {
        XCTAssertTrue(app.buttons["ai.addCustom"].waitForExistence(timeout: 8))
        app.buttons["ai.addCustom"].tap()
        XCTAssertTrue(app.buttons["ai.edit.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ai.edit.name"].exists, "自定义服务需要名称输入")
        XCTAssertTrue(app.textFields["ai.edit.baseURL"].exists)
        capture("ai-03-custom-new")

        app.buttons["ai.edit.back"].tap()
        XCTAssertTrue(app.buttons["ai.addCustom"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ai.edit.save"].exists)
    }
}

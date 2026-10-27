import SwiftUI

/// AI 服务页的视觉夹具：组件是生产代码，只有数据是预置的。
struct AIServiceHarness: View {
    @StateObject private var store = AIServiceStore.shared

    init() {
        let store = AIServiceStore.shared
        guard store.configs.isEmpty else { return }
        var openai = AIServiceConfig(id: "openai", baseURL: "https://api.openai.com/v1",
                                     model: "gpt-4o-mini", temperature: 0.7)
        openai.updatedAt = Date(timeIntervalSince1970: 1_760_000_000)
        store.save(openai)
        store.setKey("sk-harness-not-real", for: "openai")

        var deepseek = AIServiceConfig(id: "deepseek", baseURL: "https://api.deepseek.com/v1",
                                       model: "deepseek-chat")
        deepseek.updatedAt = Date(timeIntervalSince1970: 1_759_000_000)
        store.save(deepseek)
        store.setKey("sk-harness-not-real", for: "deepseek")

        let customID = store.makeCustomID()
        store.save(AIServiceConfig(id: customID, name: "本地 Ollama",
                                   baseURL: "http://192.168.1.9:11434/v1", model: "qwen2.5:7b"))
        store.setKey("ollama", for: customID)
        store.defaultID = "openai"
    }

    var body: some View {
        NavigationStack { AIServiceView() }
    }
}

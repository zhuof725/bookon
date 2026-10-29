import SwiftUI
import UIKit

/// 单个 AI 服务的配置页：密钥、接口地址、模型、温度、启用状态，以及连通性测试。
struct AIProviderEditView: View {
    @ThemePalette private var palette
    @ObservedObject private var store = AIServiceStore.shared
    @Environment(\.dismiss) private var dismiss

    let provider: AIProvider
    let existing: AIServiceConfig?
    let isNewCustom: Bool

    @State private var name: String
    @State private var baseURL: String
    @State private var model: String
    @State private var key: String
    @State private var temperature: Double
    @State private var enabled: Bool
    @State private var revealKey = false
    @State private var makeDefault: Bool
    @State private var proto: AIProtocol
    @State private var appendV1: Bool
    @State private var testing = false
    @State private var probe: AIProbeResult?
    @State private var showModels = false
    @State private var fetchingModels = false
    @State private var modelsError: String?
    @State private var showKeyWarning = false

    init(provider: AIProvider, config: AIServiceConfig?, isNewCustom: Bool = false) {
        self.provider = provider
        self.existing = config
        self.isNewCustom = isNewCustom
        _name = State(initialValue: config?.name ?? "")
        _baseURL = State(initialValue: config?.baseURL ?? provider.baseURL)
        _model = State(initialValue: config?.model ?? provider.defaultModel)
        // 已保存的密钥不回填：留空即保持不变，避免内存里多一份明文。
        _key = State(initialValue: "")
        _temperature = State(initialValue: config?.temperature ?? 0.7)
        _enabled = State(initialValue: config?.enabled ?? true)
        _makeDefault = State(initialValue: config != nil && AIServiceStore.shared.defaultID == config?.id)
        _proto = State(initialValue: config?.proto ?? provider.proto)
        _appendV1 = State(initialValue: config?.appendV1 ?? provider.appendV1)
    }

    private var resolvedID: String { existing?.id ?? (isNewCustom ? "" : provider.id) }

    /// 自定义服务允许在三种协议间切换，其余服务固定。
    private var effectiveProvider: AIProvider {
        var value = provider
        if isCustom { value.proto = proto }
        return value
    }
    private var isCustom: Bool { isNewCustom || provider.isCustom }
    private var tint: Color { AppThemeColor.color(provider.tint) }
    private var title: String {
        if isNewCustom { return "自定义服务" }
        return existing?.displayName ?? provider.name
    }

    private var trimmedBase: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 已保存过密钥（编辑已有服务时）。
    private var hasSavedKey: Bool {
        guard let existing else { return false }
        return AIServiceStore.shared.hasKey(for: existing.id)
    }
    /// 本次请求可用的密钥：输入框优先，其次用已保存的。
    private var effectiveKey: String {
        if !trimmedKey.isEmpty { return trimmedKey }
        guard let existing else { return "" }
        return AIServiceStore.shared.apiKey(for: existing.id) ?? ""
    }

    private var canTest: Bool {
        guard !trimmedBase.isEmpty, !trimmedModel.isEmpty else { return false }
        return !effectiveKey.isEmpty || isCustom
    }
    private var canSave: Bool { !trimmedBase.isEmpty && (isCustom ? !name.trimmingCharacters(in: .whitespaces).isEmpty : true) }

    var body: some View {
        VStack(spacing: AppLayout.gapM) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.gapL) {
                    identityCard
                    protocolCard
                    credentialCard
                    behaviorCard
                    testSection
                    if isCustom && existing != nil { deleteButton }
                }
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.top, AppLayout.gapS)
                .padding(.bottom, 96)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { saveBar }
        .alert("还没有填写 API Key", isPresented: $showKeyWarning) {
            Button("去填写", role: .cancel) {}
            Button("仍然保存") { commitSave() }
        } message: {
            Text("云端服务没有密钥无法使用，探索页也不会生成推荐。如果这是本地或免鉴权服务，可以忽略。")
        }
        .sheet(isPresented: $showModels) {
            AIModelPickerSheet(store: store,
                               serviceID: modelCacheKey,
                               current: trimmedModel,
                               providerName: title,
                               onPick: { model = $0 },
                               onRefresh: { await refreshModels() })
        }
    }

    // MARK: 页头

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44).modifier(ShelfGlass(shape: Circle()))
            }
            .accessibilityLabel("返回")
            .accessibilityIdentifier("ai.edit.back")
            Spacer()
            Text(title).appFont(.headline).lineLimit(1)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.top, AppLayout.gapS)
    }

    // MARK: 分组

    private var identityCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 3) {
                if isCustom {
                    TextField("服务名称，如「本地 Ollama」", text: $name)
                        .appFont(.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ai.edit.name")
                } else {
                    Text(provider.name).appFont(.body)
                }
                HStack(spacing: 6) {
                    Text(protocolLabel)
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                    Text(hasSavedKey ? "已存密钥" : "缺密钥")
                        .appFont(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hasSavedKey ? .green : .orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background {
                            Capsule().fill((hasSavedKey ? Color.green : Color.orange).opacity(0.12))
                        }
                        .accessibilityIdentifier("ai.edit.keyState")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppLayout.pageInset)
        .appGlass(in: RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous),
                  tint: palette.surface)
    }

    private var protocolLabel: String {
        switch effectiveProvider.proto {
        case .openAI: return isCustom ? "OpenAI 兼容接口" : "OpenAI 接口"
        case .anthropic: return "Anthropic Messages 接口"
        case .gemini: return "Google Generative Language 接口"
        }
    }

    /// 自定义服务可选协议；OpenAI 兼容地址决定是否自动补 `/v1`。
    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: AppLayout.gapM) {
            if isCustom {
                VStack(alignment: .leading, spacing: 6) {
                    Text("接口协议").appFont(.caption).foregroundStyle(palette.secondary)
                    Picker("接口协议", selection: $proto) {
                        Text("OpenAI 兼容").tag(AIProtocol.openAI)
                        Text("Anthropic").tag(AIProtocol.anthropic)
                        Text("Gemini").tag(AIProtocol.gemini)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ai.edit.proto")
                }
            }
            if effectiveProvider.proto == .openAI {
                Toggle("自动补 /v1", isOn: $appendV1)
                    .appFont(.body)
                    .accessibilityIdentifier("ai.edit.appendV1")
                Text(appendV1
                     ? "地址只填到域名即可，会拼成 域名/v1/chat/completions。也支持直接贴完整端点。"
                     : "地址按原样使用并拼 /chat/completions，需要自己带上版本路径，例如 https://api.deepseek.com/v1。")
                    .appFont(.caption).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppLayout.pageInset)
        .appGlass(in: RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous),
                  tint: palette.surface)
    }

    private var credentialCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldRow("API Key") {
                HStack(spacing: 6) {
                    Group {
                        let prompt = hasSavedKey ? "已保存 · 留空则不修改" : "sk-…"
                        if revealKey {
                            TextField("", text: $key, prompt: Text(prompt))
                        } else {
                            SecureField("", text: $key, prompt: Text(prompt))
                        }
                    }
                    .appFont(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai.edit.key")

                    Button { revealKey.toggle() } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealKey ? "隐藏密钥" : "显示密钥")
                }
            }
            separator
            fieldRow("接口地址") {
                TextField("https://…", text: $baseURL)
                    .appFont(.system(.callout, design: .monospaced))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai.edit.baseURL")
            }
            separator
            fieldRow("模型") {
                HStack(spacing: 8) {
                    TextField("模型名称", text: $model)
                        .appFont(.system(.callout, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ai.edit.model")
                    if fetchingModels {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { openModelPicker() } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(palette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("获取模型列表")
                        .accessibilityIdentifier("ai.edit.fetchModels")
                    }
                    if !provider.modelHints.isEmpty {
                        Menu {
                            ForEach(provider.modelHints, id: \.self) { hint in
                                Button(hint) { model = hint }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                        }
                        .accessibilityLabel("选择常用模型")
                    }
                }
                if let modelsError {
                    Text(modelsError)
                        .appFont(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !availableModels.isEmpty {
                    Text("已缓存 \(availableModels.count) 个模型，点左侧按钮选择。")
                        .appFont(.caption).foregroundStyle(palette.secondary)
                }
            }
        }
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.vertical, AppLayout.gapXS)
        .appGlass(in: RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous),
                  tint: palette.surface)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("启用").appFont(.body)
                    Text("停用后不会出现在可选择列表里").appFont(.caption).foregroundStyle(palette.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden()
                    .accessibilityIdentifier("ai.edit.enabled")
            }
            .padding(.vertical, 10)
            separator
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("设为默认").appFont(.body)
                    Text("生成推荐语时优先使用这个服务").appFont(.caption).foregroundStyle(palette.secondary)
                }
                Spacer()
                Toggle("", isOn: $makeDefault).labelsHidden()
                    .accessibilityIdentifier("ai.edit.makeDefault")
            }
            .padding(.vertical, 10)
            separator
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("温度").appFont(.body)
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .appFont(.system(.footnote, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                Slider(value: $temperature, in: 0...1.5, step: 0.1) { Text("温度") }
                    .accessibilityIdentifier("ai.edit.temperature")
                Text("越低越稳定，越高越发散。推荐语这类改写用 0.6~0.8。")
                    .appFont(.caption).foregroundStyle(palette.secondary)
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, AppLayout.pageInset)
        .appGlass(in: RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous),
                  tint: palette.surface)
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.gapS) {
            Button { runTest() } label: {
                HStack(spacing: 8) {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal")
                    }
                    Text(testing ? "正在连接…" : "测试连接").appFont(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .appGlass(in: Capsule(), tint: palette.surface)
            }
            .buttonStyle(.plain)
            .disabled(!canTest || testing)
            .opacity(canTest ? 1 : 0.5)
            .accessibilityIdentifier("ai.edit.test")

            if let probe {
                probeCard(probe)
            } else if !canTest {
                Text(isCustom && trimmedKey.isEmpty
                     ? "本地或无需鉴权的服务可以不填密钥；填好地址和模型后即可测试。"
                     : "填好密钥、地址和模型后可以测试。")
                    .appFont(.caption).foregroundStyle(palette.secondary)
            }
        }
    }

    /// 测试结果：结论 + 服务端原文 + 实际请求地址，失败时可直接复制发给别人排查。
    private func probeCard(_ result: AIProbeResult) -> some View {
        let tint = result.ok ? Color.green : Color.red
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(tint)
                Text(result.title).appFont(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(String(format: "%.1f s", result.seconds))
                    .appFont(.caption).foregroundStyle(palette.secondary)
            }
            if !result.detail.isEmpty {
                Text(result.detail)
                    .appFont(.footnote)
                    .foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(result.url)
                .appFont(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
            if !result.ok && !result.raw.isEmpty && result.raw != result.detail {
                Text(result.raw)
                    .appFont(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            Button {
                UIPasteboard.general.string = result.summary
                    + (result.raw.isEmpty ? "" : "\n\n响应：\(result.raw)")
            } label: {
                Label("复制诊断信息", systemImage: "doc.on.doc")
                    .appFont(.caption)
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(AppLayout.gapM)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.radiusControl, style: .continuous)
                .fill(tint.opacity(0.09))
        }
        .accessibilityIdentifier("ai.edit.testResult")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if let existing { store.delete(existing.id) }
            dismiss()
        } label: {
            Text("删除这个服务").appFont(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity).frame(height: 44)
                .foregroundStyle(.red)
                .background {
                    RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai.edit.delete")
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Button { save() } label: {
                Text("保存")
                    .appFont(.headline)
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .accessibilityIdentifier("ai.edit.save")
            .padding(.horizontal, AppLayout.pageInset)
            .padding(.vertical, AppLayout.gapS)
        }
        .background(.ultraThinMaterial)
    }

    private var separator: some View {
        Rectangle().fill(palette.primary.opacity(0.07))
            .frame(height: AppLayout.hairline)
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).appFont(.caption).foregroundStyle(palette.secondary)
            content()
                .frame(minHeight: 28)
                .foregroundStyle(palette.primary)
        }
        .padding(.vertical, 10)
    }

    // MARK: 状态

    /// 未保存的自定义服务也要有稳定的缓存位置。
    private var modelCacheKey: String {
        resolvedID.isEmpty ? "custom-draft" : resolvedID
    }

    private var availableModels: [AIModelSummary] {
        store.cachedModels(for: modelCacheKey)
    }

    private func openModelPicker() {
        if !availableModels.isEmpty {
            showModels = true
        } else {
            fetchModels(openAfter: true)
        }
    }

    private func fetchModels(openAfter: Bool = false) {
        fetchingModels = true
        modelsError = nil
        let provider = effectiveProvider
        let config = draftConfig()
        let key = effectiveKey
        let cacheKey = modelCacheKey
        Task {
            do {
                let list = try await AIModelFetcher().fetch(provider: provider, config: config, apiKey: key)
                store.setCachedModels(list, for: cacheKey)
                if openAfter { showModels = true }
            } catch {
                modelsError = error.localizedDescription
            }
            fetchingModels = false
        }
    }

    private func draftConfig() -> AIServiceConfig {
        AIServiceConfig(id: resolvedID,
                        name: isCustom ? name.trimmingCharacters(in: .whitespaces) : nil,
                        baseURL: trimmedBase,
                        model: trimmedModel,
                        temperature: temperature,
                        enabled: enabled,
                        appendV1: (isCustom || effectiveProvider.proto == .openAI) ? appendV1 : nil,
                        proto: isCustom ? proto : nil,
                        updatedAt: existing?.updatedAt ?? Date())
    }

    private func refreshModels() async {
        let provider = effectiveProvider
        let config = draftConfig()
        let key = effectiveKey
        let cacheKey = modelCacheKey
        do {
            let list = try await AIModelFetcher().fetch(provider: provider, config: config, apiKey: key)
            store.setCachedModels(list, for: cacheKey)
            modelsError = nil
        } catch {
            modelsError = error.localizedDescription
        }
    }

    private func runTest() {
        testing = true
        probe = nil
        let provider = effectiveProvider
        let config = draftConfig()
        let apiKey = effectiveKey
        Task {
            let result = await AIClient().probe(provider: provider, config: config, apiKey: apiKey)
            probe = result
            testing = false
        }
    }

    /// 本地/局域网端点可以没有密钥；云端服务没有密钥一定用不了。
    private var looksLocal: Bool {
        let value = trimmedBase.lowercased()
        return value.contains("127.0.0.1") || value.contains("localhost")
            || value.contains("192.168.") || value.contains("10.0.") || value.contains("172.16.")
    }

    private func save() {
        // 没有密钥也没存过：云端服务保存了也用不了，先确认一次。
        if trimmedKey.isEmpty, !hasSavedKey, !looksLocal {
            showKeyWarning = true
            return
        }
        commitSave()
    }

    private func commitSave() {
        let id = resolvedID.isEmpty ? store.makeCustomID() : resolvedID
        var config = draftConfig()
        config.id = id
        config.appendV1 = (isCustom || provider.proto == .openAI) ? appendV1 : nil
        store.save(config)
        // 留空表示沿用已有密钥；新建服务留空则不写。
        if !trimmedKey.isEmpty { store.setKey(trimmedKey, for: id) }
        if makeDefault || store.defaultID == nil {
            store.defaultID = id
        }
        dismiss()
    }
}

import SwiftUI

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
    @State private var test: TestState = .idle
    @State private var showValidation = false

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
    }

    private var resolvedID: String { existing?.id ?? (isNewCustom ? "" : provider.id) }
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

    private var canTest: Bool { !trimmedBase.isEmpty && !trimmedModel.isEmpty && !effectiveKey.isEmpty }
    private var canSave: Bool { !trimmedBase.isEmpty && (isCustom ? !name.trimmingCharacters(in: .whitespaces).isEmpty : true) }

    var body: some View {
        VStack(spacing: AppLayout.gapM) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.gapL) {
                    identityCard
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
                Text(protocolLabel)
                    .appFont(.footnote).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppLayout.pageInset)
        .appGlass(in: RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous),
                  tint: palette.surface)
    }

    private var protocolLabel: String {
        switch provider.proto {
        case .openAI: return isCustom ? "OpenAI 兼容接口" : "OpenAI 接口"
        case .anthropic: return "Anthropic Messages 接口"
        case .gemini: return "Google Generative Language 接口"
        }
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
                HStack(spacing: 6) {
                    TextField("模型名称", text: $model)
                        .appFont(.system(.callout, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ai.edit.model")
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
                    if case .running = test {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal")
                    }
                    Text(isTesting ? "正在连接…" : "测试连接").appFont(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .appGlass(in: Capsule(), tint: palette.surface)
            }
            .buttonStyle(.plain)
            .disabled(!canTest || isTesting)
            .opacity(canTest ? 1 : 0.5)
            .accessibilityIdentifier("ai.edit.test")

            switch test {
            case .idle:
                if !canTest {
                    Text("填好密钥、地址和模型后可以测试。")
                        .appFont(.caption).foregroundStyle(palette.secondary)
                }
            case .running:
                EmptyView()
            case let .success(message):
                resultRow(message, symbol: "checkmark.circle.fill", color: .green)
            case let .failure(message):
                resultRow(message, symbol: "xmark.octagon.fill", color: .red)
            }
        }
    }

    private func resultRow(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .appFont(.footnote)
                .foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppLayout.gapM)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.radiusControl, style: .continuous)
                .fill(color.opacity(0.10))
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

    private enum TestState: Equatable {
        case idle, running
        case success(String)
        case failure(String)
    }

    private var isTesting: Bool {
        if case .running = test { return true }
        return false
    }

    private func draftConfig() -> AIServiceConfig {
        AIServiceConfig(id: resolvedID,
                        name: isCustom ? name.trimmingCharacters(in: .whitespaces) : nil,
                        baseURL: trimmedBase,
                        model: trimmedModel,
                        temperature: temperature,
                        enabled: enabled,
                        updatedAt: existing?.updatedAt ?? Date())
    }

    private func runTest() {
        test = .running
        let provider = self.provider
        let config = draftConfig()
        let apiKey = effectiveKey
        Task {
            do {
                let result = try await AIClient().ping(provider: provider, config: config, apiKey: apiKey)
                let seconds = String(format: "%.1f", result.seconds)
                test = .success("连通正常（\(seconds)s）：\(result.text.prefix(60))")
            } catch {
                test = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        let id = resolvedID.isEmpty ? store.makeCustomID() : resolvedID
        var config = draftConfig()
        config.id = id
        store.save(config)
        // 留空表示沿用已有密钥；新建服务留空则不写。
        if !trimmedKey.isEmpty { store.setKey(trimmedKey, for: id) }
        if makeDefault || store.defaultID == nil {
            store.defaultID = id
        }
        dismiss()
    }
}

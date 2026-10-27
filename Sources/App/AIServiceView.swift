import SwiftUI

/// AI 服务总览：内置提供商 + 自定义服务。
/// 视觉沿用应用其它设置页：自绘页头、玻璃卡片、20 圆角。
struct AIServiceView: View {
    @ThemePalette private var palette
    @ObservedObject private var store = AIServiceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var addingCustom = false

    var body: some View {
        VStack(spacing: AppLayout.gapM) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.gapXL) {
                    section("提供商") {
                        card {
                            ForEach(Array(AICatalog.builtins.enumerated()), id: \.element.id) { index, provider in
                                if index > 0 { divider }
                                NavigationLink {
                                    AIProviderEditView(provider: provider, config: store.config(for: provider.id))
                                } label: {
                                    AIServiceRow(provider: provider,
                                                 config: store.config(for: provider.id),
                                                 hasKey: store.hasKey(for: provider.id),
                                                 isDefault: store.defaultID == provider.id)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ai.provider.\(provider.id)")
                            }
                        }
                    }

                    section("自定义服务") {
                        card {
                            ForEach(Array(store.customConfigs.enumerated()), id: \.element.id) { index, config in
                                if index > 0 { divider }
                                NavigationLink {
                                    AIProviderEditView(provider: AICatalog.custom, config: config)
                                } label: {
                                    AIServiceRow(provider: AICatalog.custom,
                                                 config: config,
                                                 hasKey: store.hasKey(for: config.id),
                                                 isDefault: store.defaultID == config.id,
                                                 overrideName: config.displayName)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ai.custom.\(config.id)")
                            }
                            if !store.customConfigs.isEmpty { divider }
                            NavigationLink {
                                AIProviderEditView(provider: AICatalog.custom,
                                                   config: nil, isNewCustom: true)
                            } label: {
                                addRow
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ai.addCustom")
                        }
                    }

                    if store.insecureKeyStorage {
                        Label("当前安装包无法写入系统钥匙串，API Key 以明文保存在应用沙盒内。",
                              systemImage: "exclamationmark.triangle.fill")
                            .appFont(.footnote)
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppLayout.gapXS)
                    }

                    Text("Key 只保存在本机，不会上传。所有请求直接发往你填写的服务地址。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppLayout.gapXS)
                }
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.top, AppLayout.gapS)
                .padding(.bottom, AppLayout.gapXL)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44).modifier(ShelfGlass(shape: Circle()))
            }
            .accessibilityLabel("返回")
            .accessibilityIdentifier("ai.back")
            Spacer()
            Text("AI 提供商").appFont(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.top, AppLayout.gapS)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppLayout.gapS) {
            Text(title)
                .appFont(.subheadline)
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, AppLayout.gapXS)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .appGlass(in: RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous),
                      tint: palette.surface)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.primary.opacity(0.07))
            .frame(height: AppLayout.hairline)
            .padding(.leading, 62)
    }

    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
            Text("添加自定义服务").appFont(.body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondary.opacity(0.5))
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, AppLayout.pageInset)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// 单条提供商：彩色符号 + 名称 + 状态。
private struct AIServiceRow: View {
    @ThemePalette private var palette
    let provider: AIProvider
    let config: AIServiceConfig?
    let hasKey: Bool
    let isDefault: Bool
    var overrideName: String? = nil

    private var tint: Color { AppThemeColor.color(provider.tint) }

    private var status: String {
        if let config { return config.summary(hasKey: hasKey) }
        return "未配置"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(overrideName ?? provider.name).appFont(.body)
                    if isDefault && hasKey {
                        Text("默认")
                            .appFont(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.accent.opacity(0.12)))
                    }
                }
                Text(status)
                    .appFont(.footnote)
                    .foregroundStyle(hasKey ? palette.secondary : palette.secondary.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondary.opacity(0.5))
        }
        .padding(.horizontal, AppLayout.pageInset)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(overrideName ?? provider.name)，\(status)")
    }
}

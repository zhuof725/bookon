import SwiftUI

/// 朗读净化设置：内置清理 + 自定义替换规则 + 效果预览。
struct AloudPurifySettingsView: View {
    @ObservedObject private var store = AloudPurifyStore.shared
    @ThemePalette private var palette
    @State private var editing: BodyReplaceRule?
    @State private var sample = "本章未完，请点击下一页继续阅读 https://example.com\n他抬头看了看天，淡淡道：“走吧。”"

    var body: some View {
        List {
            Section {
                Toggle("启用朗读净化", isOn: $store.enabled)
                    .accessibilityIdentifier("aloud.purify.enabled")
                Toggle("同时应用「正文替换规则」", isOn: $store.useBodyRules)
                    .accessibilityIdentifier("aloud.purify.useBodyRules")
            } footer: {
                Text("朗读前去掉网址、站点广告、本章完等无关文字；只影响送进朗读的文字，不改阅读页正文。")
            }

            Section {
                if store.rules.isEmpty {
                    Text("还没有自定义规则。内置清理已经会去掉网址和常见尾注。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                } else {
                    ForEach(store.rules) { rule in
                        HStack(spacing: 12) {
                            Button {
                                editing = rule
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.name).appFont(.body)
                                    Text(rule.pattern)
                                        .appFont(.caption2)
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Toggle("", isOn: enabledBinding(rule))
                                .labelsHidden()
                                .accessibilityLabel("启用 \(rule.name)")
                        }
                    }
                    .onDelete { indexes in
                        store.rules.remove(atOffsets: indexes)
                    }
                }
                Button {
                    let existing = Set(store.rules.map(\.id))
                    let added = AloudPurifyStore.recommendedRules.filter { !existing.contains($0.id) }
                    store.rules.append(contentsOf: added)
                } label: {
                    Label("添加推荐规则", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("aloud.purify.recommended")

                Button {
                    editing = BodyReplaceRule(id: UUID().uuidString, name: "", pattern: "",
                                              replacement: "", isRegex: false, enabled: true)
                } label: {
                    Label("添加自定义规则", systemImage: "plus.circle")
                }
                .disabled(store.rules.count >= 50)
                .accessibilityIdentifier("aloud.purify.add")
            } header: {
                Text("自定义规则 · \(store.rules.count)/50")
            } footer: {
                Text("按列表顺序执行；正则模式支持 $1 捕获组。规则只作用于送进朗读的文字。")
            }

            Section {
                TextEditor(text: $sample)
                    .appFont(.callout)
                    .frame(minHeight: 90)
                    .accessibilityIdentifier("aloud.purify.sample")
                Text(store.purify(sample).isEmpty ? "（净化后为空）" : store.purify(sample))
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("aloud.purify.preview")
            } header: {
                Text("效果预览")
            } footer: {
                Text("预览使用上面这段示例文字，实时显示净化后的朗读文本。")
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("朗读净化")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { rule in
            BodyReplaceRuleEditor(
                rule: rule,
                existing: store.rules.contains { $0.id == rule.id },
                contextTitle: "净化规则",
                onSave: { changed in
                    if let index = store.rules.firstIndex(where: { $0.id == changed.id }) {
                        store.rules[index] = changed
                    } else {
                        store.rules.append(changed)
                    }
                    editing = nil
                    return nil
                },
                onDelete: {
                    store.rules.removeAll { $0.id == rule.id }
                    editing = nil
                })
        }
    }

    private func enabledBinding(_ rule: BodyReplaceRule) -> Binding<Bool> {
        Binding(get: { store.rules.first { $0.id == rule.id }?.enabled ?? false },
                set: { value in
                    guard let index = store.rules.firstIndex(where: { $0.id == rule.id }) else { return }
                    store.rules[index].enabled = value
                })
    }
}

import SwiftUI

struct BodyReplaceRulesView: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [BodyReplaceRule] = []
    @State private var editing: BodyReplaceRule?
    @State private var deleting: BodyReplaceRule?
    @State private var pendingDeletion: BodyReplaceRule?
    @State private var error: String?
    private let repository: BodyReplaceRepository

    init(defaults: UserDefaults = .standard) { repository = BodyReplaceRepository(defaults: defaults) }

    private func persist(_ updated: [BodyReplaceRule]) -> String? {
        do { try repository.save(updated); rules = updated; return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 22, weight: .medium))
                        .frame(width: 46, height: 46).modifier(ShelfGlass(shape: Circle()))
                }.buttonStyle(.plain).accessibilityLabel("返回").accessibilityIdentifier("bodyRules.back")
                Spacer()
                Text("正文替换规则").appFont(.headline)
                Spacer()
                Color.clear.frame(width: 46, height: 46)
            }.padding(.horizontal, 18).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("规则列表 · \(rules.count)/50").appFont(.title2.bold()).padding(.horizontal, 18)
                    VStack(spacing: 8) {
                        if rules.isEmpty {
                            Text("还没有正文替换规则\n添加规则可清理阅读正文中的指定文字。")
                                .foregroundStyle(palette.secondary).padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(SettingsGlassSurface())
                                .accessibilityIdentifier("bodyRules.empty")
                        }
                        ForEach(rules) { rule in
                            HStack(spacing: 12) {
                                Button { editing = rule } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(rule.name).appFont(.system(size: 19)).foregroundStyle(palette.primary)
                                        Text(rule.isRegex ? "正则表达式" : "字面替换").appFont(.caption).foregroundStyle(palette.secondary)
                                        Text(rule.pattern).appFont(.system(size: 14, design: .monospaced))
                                            .foregroundStyle(palette.secondary).lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("bodyRules.rule." + rule.id)
                                Toggle("启用 \(rule.name)", isOn: Binding(get: {
                                    rules.first(where: { $0.id == rule.id })?.enabled ?? false
                                }, set: { enabled in
                                    var updated = rules
                                    if let index = updated.firstIndex(where: { $0.id == rule.id }) {
                                        updated[index].enabled = enabled; error = persist(updated)
                                    }
                                })).labelsHidden().accessibilityIdentifier("bodyRules.enabled." + rule.id)
                            }.padding(18).modifier(SettingsGlassSurface())
                            .contextMenu {
                                Button("编辑") { editing = rule }
                                Button("删除", role: .destructive) { deleting = rule }
                            }
                        }
                        Button {
                            editing = BodyReplaceRule(id: UUID().uuidString, name: "", pattern: "", replacement: "", isRegex: false, enabled: true)
                        } label: {
                            Label("添加替换规则", systemImage: "plus.circle").appFont(.system(size: 20))
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).modifier(SettingsGlassSurface()).disabled(rules.count >= 50).accessibilityIdentifier("bodyRules.add")
                    }
                    Text("按列表顺序执行已启用规则，仅改变阅读正文的显示，不修改原文、缓存或标题，也不处理图片或链接。保存后请退出并重新进入阅读器，新阅读会话才会使用新规则。")
                        .appFont(.footnote).foregroundStyle(palette.secondary).padding(.horizontal, 8)
                    Text("每个段落单独匹配，正则表达式不能跨段。替换内容留空表示删除匹配文字；超时或超出长度限制时，该条规则保持处理前的段落。")
                        .appFont(.footnote).foregroundStyle(palette.secondary).padding(.horizontal, 8)
                }.padding(.horizontal, 18).padding(.bottom, 28)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar).modifier(MonochromeAppStyle())
        .onAppear { rules = repository.rules() }
        .sheet(item: $editing, onDismiss: {
            if let pendingDeletion { deleting = pendingDeletion; self.pendingDeletion = nil }
        }) { rule in
            BodyReplaceRuleEditor(rule: rule, existing: rules.contains(where: { $0.id == rule.id }), onSave: { changed in
                var updated = rules
                if let index = updated.firstIndex(where: { $0.id == changed.id }) { updated[index] = changed }
                else { updated.append(changed) }
                if let message = persist(updated) { return message }
                editing = nil; return nil
            }, onDelete: { pendingDeletion = rule; editing = nil }).modifier(MonochromeAppStyle())
        }
        .alert("删除正文替换规则？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) {
                if let deleting { error = persist(rules.filter { $0.id != deleting.id }) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("只删除这条规则，不会修改书籍原文或缓存。") }
        .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct BodyReplaceRuleEditor: View {
    @ThemePalette private var palette
    let existing: Bool
    let onSave: (BodyReplaceRule) -> String?
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BodyReplaceRule
    @State private var sample = ""
    @State private var preview: String?
    @State private var savingError: String?
    @FocusState private var activeField: String?

    init(rule: BodyReplaceRule, existing: Bool, onSave: @escaping (BodyReplaceRule) -> String?, onDelete: @escaping () -> Void) {
        self.existing = existing; self.onSave = onSave; self.onDelete = onDelete
        _draft = State(initialValue: rule)
    }

    private func editor(_ text: Binding<String>, id: String) -> some View {
        TextEditor(text: text).appFont(.system(.callout, design: .monospaced))
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .focused($activeField, equals: id)
            .frame(minHeight: 80).accessibilityIdentifier("bodyRules." + id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("名称") { editor($draft.name, id: "name") }
                    Section("选项") {
                        Toggle("启用规则", isOn: $draft.enabled).accessibilityIdentifier("bodyRules.enabled")
                        Toggle("正则表达式", isOn: $draft.isRegex).accessibilityIdentifier("bodyRules.regex")
                    }
                    Section("查找内容") {
                        editor($draft.pattern, id: "pattern")
                        if let invalid = draft.validationMessage { Text(invalid).appFont(.footnote).foregroundStyle(.red) }
                    }
                    Section("替换内容") {
                        editor($draft.replacement, id: "replacement")
                        Text("留空表示删除。字面替换会原样插入 $ 和反斜杠；正则模式支持 $1、$2 等捕获组。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    Section("测试正文") {
                        editor($sample, id: "sample")
                        Text("测试当前规则（忽略启用开关），每行视为一个段落，不跨段匹配。超限时保留该段原文。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                        Button("测试替换") {
                            var candidate = draft; candidate.enabled = true
                            let engine = BodyReplaceEngine(rules: [candidate])
                            preview = sample.components(separatedBy: .newlines).map { engine.apply($0) }.joined(separator: "\n")
                        }.disabled(draft.validationMessage != nil || sample.utf16.count > 20_000)
                            .accessibilityIdentifier("bodyRules.test")
                        if sample.utf16.count > 20_000 { Text("测试内容不能超过 20000 个 UTF-16 单位").appFont(.footnote).foregroundStyle(.red) }
                        if let preview {
                            Text(preview.isEmpty ? "（替换结果为空）" : preview).textSelection(.enabled)
                                .accessibilityIdentifier("bodyRules.result")
                        }
                    }
                    Section {
                        Text("保存仅影响下一次进入阅读器的会话。原文、缓存、标题、图片与链接不变。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    if existing {
                        Section { Button("删除规则", role: .destructive, action: onDelete).foregroundStyle(.red).accessibilityIdentifier("bodyRules.delete") }
                    }
                    if let savingError { Text(savingError).foregroundStyle(.red) }
                }
                .independentGlassRow()
            }
            .foregroundStyle(palette.primary)
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(existing ? "编辑正文替换" : "添加正文替换").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { activeField = nil }
                        .accessibilityIdentifier("bodyRules.hideKeyboard")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("bodyRules.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var changed = draft; changed.name = changed.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        savingError = onSave(changed)
                    }.disabled(draft.validationMessage != nil).accessibilityIdentifier("bodyRules.save")
                }
            }
            .onChange(of: draft) { _ in preview = nil; savingError = nil }
            .onChange(of: sample) { _ in preview = nil }
        }
    }
}

import SwiftUI

struct TxtTocRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var custom: [TxtTocRule] = []
    @State private var editing: TxtTocRule?
    @State private var deleting: TxtTocRule?
    @State private var pendingDeletion: TxtTocRule?
    @State private var error: String?
    private let repository: TxtTocRuleRepository

    init(defaults: UserDefaults = .standard) {
        repository = TxtTocRuleRepository(defaults: defaults)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 22, weight: .medium))
                        .frame(width: 46, height: 46)
                        .modifier(ShelfGlass(shape: Circle()))
                }.buttonStyle(.plain).accessibilityLabel("返回").accessibilityIdentifier("tocRules.back")
                Spacer()
                Text("目录规则").appFont(.headline)
                Spacer()
                Color.clear.frame(width: 46, height: 46)
            }.padding(.horizontal, 18).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("规则列表").appFont(.title2.bold()).padding(.horizontal, 18)
                    VStack(spacing: 0) {
                        ForEach(TxtTocRule.builtIns + custom) { rule in
                            if rule.isBuiltIn {
                                ruleContent(rule)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("tocRules.rule." + rule.id)
                            } else {
                                Button { editing = rule } label: { ruleContent(rule) }
                                    .buttonStyle(.plain).accessibilityIdentifier("tocRules.rule." + rule.id)
                                    .contextMenu {
                                        Button("编辑") { editing = rule }
                                        Button("删除", role: .destructive) { deleting = rule }
                                    }
                            }
                            Divider().overlay(AppPalette.background)
                        }
                        Button {
                            editing = TxtTocRule(id: UUID().uuidString, name: "", pattern: "", isBuiltIn: false)
                        } label: {
                            Label("添加自定义规则", systemImage: "plus.circle")
                                .appFont(.system(size: 20)).padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("tocRules.add")
                    }.background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 25))
                    Text("适用于新导入的 TXT 文件，内置与自定义规则共同识别标题。已有目录不自动重建，EPUB 和书源目录不受影响。")
                        .appFont(.footnote).foregroundStyle(.secondary).padding(.horizontal, 8)
                }.padding(.horizontal, 18).padding(.bottom, 28)
            }
        }
        .background(AppPalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { custom = repository.customRules() }
        .sheet(item: $editing, onDismiss: {
            if let pendingDeletion { deleting = pendingDeletion; self.pendingDeletion = nil }
        }) { rule in
            TxtTocRuleEditor(rule: rule, onSave: { changed in
                var updated = custom
                if let index = updated.firstIndex(where: { $0.id == changed.id }) { updated[index] = changed }
                else { updated.append(changed) }
                do { try repository.save(updated); custom = updated; editing = nil; return nil }
                catch { return error.localizedDescription }
            }, onDelete: {
                pendingDeletion = rule
                editing = nil
            })
            .modifier(MonochromeAppStyle())
        }
        .alert("删除自定义规则？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) {
                guard let deleting, !deleting.isBuiltIn else { return }
                let updated = custom.filter { $0.id != deleting.id }
                do { try repository.save(updated); custom = updated }
                catch { self.error = error.localizedDescription }
                self.deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("只删除这条规则，不会删除书籍或改变已有目录。") }
        .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func ruleContent(_ rule: TxtTocRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(rule.name).appFont(.system(size: 19)).foregroundStyle(.primary)
                Text(rule.isBuiltIn ? "内置" : "自定义")
                    .appFont(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(AppPalette.selection, in: RoundedRectangle(cornerRadius: 5))
            }
            Text(rule.pattern).appFont(.system(size: 14, design: .monospaced))
                .foregroundStyle(.secondary).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

}

private struct TxtTocRuleEditor: View {
    let rule: TxtTocRule
    let onSave: (TxtTocRule) -> String?
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pattern: String
    @State private var sample = ""
    @State private var preview: String?
    @State private var savingError: String?

    init(rule: TxtTocRule, onSave: @escaping (TxtTocRule) -> String?, onDelete: @escaping () -> Void) {
        self.rule = rule; self.onSave = onSave; self.onDelete = onDelete
        _name = State(initialValue: rule.name)
        _pattern = State(initialValue: rule.pattern)
    }
    private var invalid: String? { TxtTocRule.validationMessage(name: name, pattern: pattern) }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    if rule.isBuiltIn { Text(name) }
                    else { TextField("规则名称", text: $name).accessibilityIdentifier("tocRules.name") }
                }
                Section("正则表达式") {
                    if rule.isBuiltIn { Text(pattern).appFont(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                    else {
                        TextEditor(text: $pattern).appFont(.system(.callout, design: .monospaced))
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .frame(minHeight: 100).accessibilityIdentifier("tocRules.pattern")
                        if let invalid { Text(invalid).appFont(.footnote).foregroundStyle(.secondary) }
                    }
                    Text("逐行匹配完整标题；建议使用 ^ 和 $ 限定首尾。标题候选行最多 160 个 UTF-16 单位。")
                        .appFont(.footnote).foregroundStyle(.secondary)
                }
                Section("测试标题") {
                    TextField("输入一行标题", text: $sample).autocorrectionDisabled()
                        .textInputAutocapitalization(.never).accessibilityIdentifier("tocRules.sample")
                    Button("测试匹配") {
                        let candidate = TxtTocRule(id: rule.id, name: name, pattern: pattern, isBuiltIn: rule.isBuiltIn)
                        preview = TxtTocMatcher(rules: [candidate]).isHeading(sample) ? "匹配成功" : "未匹配"
                    }.disabled(invalid != nil).accessibilityIdentifier("tocRules.test")
                    if let preview { Text(preview).accessibilityIdentifier("tocRules.result") }
                }
                if rule.isBuiltIn {
                    Section { Text("内置规则只读，不能修改或删除。需要其他格式时可添加自定义规则。").appFont(.footnote).foregroundStyle(.secondary) }
                } else if !rule.name.isEmpty {
                    Section { Button("删除规则", role: .destructive, action: onDelete).accessibilityIdentifier("tocRules.delete") }
                }
                if let savingError { Text(savingError).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden).background(AppPalette.background)
            .navigationTitle(rule.isBuiltIn ? "内置目录规则" : "自定义目录规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("tocRules.close") }
                if !rule.isBuiltIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let changed = TxtTocRule(id: rule.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), pattern: pattern, isBuiltIn: false)
                            savingError = onSave(changed)
                        }.disabled(invalid != nil).accessibilityIdentifier("tocRules.save")
                    }
                }
            }
            .onChange(of: pattern) { _ in preview = nil }
            .onChange(of: sample) { _ in preview = nil }
        }
    }
}

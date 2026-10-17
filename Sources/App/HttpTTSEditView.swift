import SwiftUI

/// HTTP 朗读引擎编辑：字段名与原版 `dialog_http_tts_edit.xml` 一致。
/// 取消不保存；保存校验名称与 URL 非空。
struct HttpTTSEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HTTPTTS
    let onSave: (HTTPTTS?) -> Void

    init(engine: HTTPTTS?, onSave: @escaping (HTTPTTS?) -> Void) {
        _draft = State(initialValue: engine ?? HTTPTTS())
        self.onSave = onSave
    }

    /// 没有改动过内容时直接返回；有改动点击取消直接退出即可（编辑器数据是一次性副本）。
    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    row("名称", text: $draft.name, hint: "必填", mono: false)
                    row("URL", text: $draft.url, hint: "支持 {{speakText}}/{{speakSpeed}}/@js:", mono: true)
                    optRow("Content-Type", text: $draft.contentType, hint: "audio/wav（留空不校验）", mono: true)
                    optRow("并发率", text: $draft.concurrentRate, hint: "N/M 或毫秒间隔，0 不限", mono: true)
                    optRow("请求头(header)", text: $draft.header, hint: "JSON 对象，支持模板语法", mono: true)
                }
                Section("登录") {
                    optRow("登录地址(loginUrl)", text: $draft.loginUrl, hint: "函数库或网址", mono: true)
                    optRow("登录界面(loginUi)", text: $draft.loginUi, hint: "字段 JSON 数组或 @js:", mono: true)
                    optRow("登录检查(loginCheckJs)", text: $draft.loginCheckJs, hint: "响应返回后执行的 JS", mono: true)
                }
                Section("高级") {
                    optRow("JS 库(jsLib)", text: $draft.jsLib, hint: "URL/登录脚本可调用的函数", mono: true)
                    Toggle("启用 CookieJar", isOn: Binding(
                        get: { draft.enabledCookieJar ?? false },
                        set: { draft.enabledCookieJar = $0 }))
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(draft.displayName == "未命名引擎" ? "新建朗读引擎" : draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onSave(nil) }
                        .accessibilityIdentifier("tts.edit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var value = draft
                        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.url = value.url.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(value)
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("tts.edit.save")
                }
            }
        }
    }

    private func row(_ title: String, text: Binding<String>, hint: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            TextField(hint, text: text, axis: .vertical)
                .lineLimit(1...8)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .accessibilityIdentifier("tts.edit.field.\(title)")
        }.padding(.vertical, 2)
    }

    private func optRow(_ title: String, text: Binding<String?>, hint: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            TextField(hint, text: Binding(get: { text.wrappedValue ?? "" },
                                          set: { text.wrappedValue = $0.isEmpty ? nil : $0 }),
                      axis: .vertical)
                .lineLimit(1...12)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .accessibilityIdentifier("tts.edit.field.\(title)")
        }.padding(.vertical, 2)
    }
}

import SwiftUI

/// 有声书「音色」面板：音色来自书源自己（例如番茄源的 jsLib `_getTones()`）。
///
/// 书源没有这套约定时只显示当前音色 + 「打开书源设置」入口。
/// 换音色后需要重新取一次本章音频，由 `onApplied` 交给阅读器处理。
struct SourceToneSheet: View {
    let source: BookSource
    var onApplied: () -> Void

    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var tones: [SourceTone.Item] = []
    @State private var currentName = ""
    @State private var currentValue = ""
    @State private var loading = true
    @State private var applying = false
    @State private var message: String?
    @State private var showSourceSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Text(currentName.isEmpty ? "默认音色" : currentName)
                            .appFont(.body)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if !currentValue.isEmpty {
                            Text(currentValue)
                                .appFont(.caption).foregroundStyle(palette.secondary)
                        }
                    }
                    .accessibilityIdentifier("tone.current")
                } header: {
                    Text("当前音色")
                }

                Section {
                    if loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在读取书源音色…").appFont(.footnote).foregroundStyle(palette.secondary)
                        }
                    } else if tones.isEmpty {
                        Text("这个书源没有提供音色列表。\n可以打开「书源设置」切换朗读音色，切完重新进入本章。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    } else {
                        ForEach(tones) { tone in
                            toneRow(tone)
                        }
                    }
                } header: {
                    Text("可选音色")
                } footer: {
                    if !tones.isEmpty {
                        Text("音色由书源提供；切换后会重新加载本章音频。")
                    }
                }

                Section {
                    Button { showSourceSettings = true } label: {
                        HStack(spacing: 12) {
                            Label("打开书源设置", systemImage: "slider.horizontal.3")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tone.sourceSettings")
                }

                if let message {
                    Section {
                        Text(message).appFont(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("音色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("tone.close")
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showSourceSettings) {
            SourceLoginView(source: source)
        }
    }

    private func toneRow(_ tone: SourceTone.Item) -> some View {
        let selected = tone.value == currentValue
        return Button {
            apply(tone)
        } label: {
            HStack(spacing: 10) {
                Text(tone.name).appFont(.body)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(applying)
        .accessibilityIdentifier("tone.option.\(tone.index)")
    }

    private func load() async {
        let src = source
        let result = await Task.detached { () -> (tones: [SourceTone.Item], name: String, value: String) in
            let tones = SourceTone.tones(source: src)
            let current = SourceTone.current(source: src)
            return (tones, current.name, current.value)
        }.value
        tones = result.tones
        currentName = result.name
        currentValue = result.value
        loading = false
    }

    private func apply(_ tone: SourceTone.Item) {
        let src = source
        applying = true
        message = nil
        Task {
            let ok = await Task.detached { SourceTone.apply(tone, source: src) }.value
            applying = false
            guard ok else {
                message = "切换失败：书源脚本没有接受这个音色"
                return
            }
            currentName = tone.name
            currentValue = tone.value
            onApplied()
            dismiss()
        }
    }
}

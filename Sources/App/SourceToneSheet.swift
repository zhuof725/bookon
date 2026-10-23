import SwiftUI

/// 书源音色列表：音色来自书源自己。
///
/// - 函数式（番茄源）：jsLib `_getTones()` + `setVoice(n)`。
/// - 声明式（书山聚合这类）：脚本里 `xxxTones = [{id,name}, …]`，写配置 `xxx_tts_tone`。
///
/// 既用在有声书播放器的「音色」面板，也嵌在朗读播放器的音色面板里。
struct SourceToneList: View {
    let source: BookSource
    /// 换音色后的回调（有声书播放器用来重新取本章音频）。
    var onApplied: (() -> Void)? = nil

    @ThemePalette private var palette
    @State private var groups: [SourceTone.Group] = []
    @State private var summary = ""
    @State private var loading = true
    @State private var applying = false
    @State private var message: String?
    @State private var showSourceSettings = false

    var body: some View {
        List {
            Section {
                Text(summary.isEmpty ? "默认音色" : summary)
                    .appFont(.body)
                    .lineLimit(2)
                    .accessibilityIdentifier("tone.current")
            } header: {
                Text("当前音色")
            }

            if loading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取书源音色…").appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                }
            } else if groups.isEmpty {
                Section {
                    Text("这个书源没有提供音色列表。\n可以打开「书源设置」切换朗读音色，切完重新进入本章。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tones) { tone in
                            toneRow(tone, group: group)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }

            if !groups.isEmpty {
                Section {
                    Text("音色由书源提供；有声书切换后会重新加载本章音频。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
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
        .task { await load() }
        .sheet(isPresented: $showSourceSettings) {
            SourceLoginView(source: source)
        }
    }

    private func toneRow(_ tone: SourceTone.Item, group: SourceTone.Group) -> some View {
        let selected = !tone.value.isEmpty && tone.value == group.currentValue
        return Button {
            apply(tone, group: group)
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
        .accessibilityIdentifier("tone.option.\(group.id).\(tone.index)")
    }

    private func load() async {
        let src = source
        let result = await Task.detached { () -> ([SourceTone.Group], String) in
            (SourceTone.groups(source: src), SourceTone.summary(source: src))
        }.value
        groups = result.0
        summary = result.1
        loading = false
    }

    private func apply(_ tone: SourceTone.Item, group: SourceTone.Group) {
        let src = source
        applying = true
        message = nil
        Task {
            let ok = await Task.detached { SourceTone.apply(tone, in: group, source: src) }.value
            applying = false
            guard ok else {
                message = "切换失败：书源脚本没有接受这个音色"
                return
            }
            groups = groups.map { item in
                guard item.id == group.id else { return item }
                return SourceTone.Group(id: item.id, title: item.title, kind: item.kind,
                                        tones: item.tones, currentValue: tone.value)
            }
            summary = SourceTone.summary(source: source)
            onApplied?()
        }
    }
}

/// 有声书的「音色」面板：包一层导航栏，选完自动关闭。
struct SourceToneSheet: View {
    let source: BookSource
    var onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourceToneList(source: source, onApplied: {
                onApplied()
                dismiss()
            })
            .navigationTitle("音色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("tone.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

import SwiftUI

/// 分享/文件打开进来的书源 JSON：先展示条数和名称，用户确认后再导入。
struct PendingSourceImport: Identifiable {
    let id = UUID()
    let fileName: String
    let sources: [BookSource]
    /// 从 Documents/Inbox 扫描到的分享文件；确认/取消后删除，避免每次启动重复弹。
    var inboxFileURL: URL? = nil
}

/// 全屏覆盖层而不是 sheet：冷启动/其他弹窗存在时也能稳定出现。
struct SourceImportConfirmation: View {
    @ThemePalette private var palette
    @ObservedObject var store: AppStore
    let pending: PendingSourceImport
    let onCancel: () -> Void
    /// 只导入勾选的条目，返回结果文案。
    let onImport: ([BookSource]) -> String

    @State private var selected: Set<String> = []
    @State private var result: String?

    private var existingURLs: Set<String> { Set(store.sources.map(\.bookSourceUrl)) }
    private var allSelected: Bool {
        !pending.sources.isEmpty && selected.count == pending.sources.count
    }
    private var selectedSources: [BookSource] {
        pending.sources.filter { selected.contains($0.bookSourceUrl) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(pending.sources, id: \.bookSourceUrl) { source in
                        row(source)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let result {
                    resultBar(result)
                } else {
                    bottomBar
                }
            }
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .onAppear {
            if selected.isEmpty {
                selected = Set(pending.sources.map(\.bookSourceUrl))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Text("导入书源")
                    .appFont(.title3.weight(.bold))
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(palette.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sourceImport.cancel")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(palette.accent)
                Text(pending.fileName)
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(palette.surface.opacity(0.55))
    }

    private func row(_ source: BookSource) -> some View {
        let isSelected = selected.contains(source.bookSourceUrl)
        let exists = existingURLs.contains(source.bookSourceUrl)
        return Button {
            if isSelected { selected.remove(source.bookSourceUrl) }
            else { selected.insert(source.bookSourceUrl) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondary)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.accent)
                Text(source.bookSourceName)
                    .appFont(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(exists ? "覆盖" : "新增")
                    .appFont(.footnote)
                    .foregroundStyle(exists ? palette.secondary : palette.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.08) : palette.surface.opacity(0.45))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent.opacity(0.35) : palette.border.opacity(0.6),
                                  lineWidth: 0.6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sourceImport.row.\(source.bookSourceUrl)")
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(allSelected ? "取消全选" : "全选（\(selected.count)/\(pending.sources.count)）") {
                if allSelected { selected.removeAll() }
                else { selected = Set(pending.sources.map(\.bookSourceUrl)) }
            }
            .appFont(.subheadline)
            .accessibilityIdentifier("sourceImport.selectAll")

            Button("反选") {
                selected = Set(pending.sources.map(\.bookSourceUrl).filter { !selected.contains($0) })
            }
            .appFont(.subheadline)
            .accessibilityIdentifier("sourceImport.invert")

            Spacer(minLength: 4)

            Button {
                result = onImport(selectedSources)
            } label: {
                Text("导入")
                    .appFont(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 20).frame(minHeight: 42)
                    .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
            .disabled(selectedSources.isEmpty)
            .opacity(selectedSources.isEmpty ? 0.45 : 1)
            .accessibilityIdentifier("sourceImport.confirm")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func resultBar(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .appFont(.subheadline)
                .foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onCancel) {
                Text("完成")
                    .appFont(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sourceImport.done")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

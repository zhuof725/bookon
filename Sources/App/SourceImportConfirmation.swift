import SwiftUI

/// 分享/文件打开进来的书源 JSON：先展示条数和名称，用户确认后再导入。
struct PendingSourceImport: Identifiable {
    let id = UUID()
    let fileName: String
    let text: String
    let sourceNames: [String]
}

struct SourceImportConfirmation: View {
    @ThemePalette private var palette
    let pending: PendingSourceImport
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(pending.fileName)
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                    Text("发现 \(pending.sourceNames.count) 个书源")
                        .appFont(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(pending.sourceNames.prefix(8).enumerated()), id: \.offset) { _, name in
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up")
                                    .foregroundStyle(palette.accent)
                                Text(name).lineLimit(1)
                            }
                        }
                        if pending.sourceNames.count > 8 {
                            Text("等 \(pending.sourceNames.count) 个")
                                .appFont(.footnote)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(SettingsGlassSurface())
                    Text("导入后会替换同名书源，不影响书架里的书。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                        .accessibilityIdentifier("sourceImport.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入", action: onImport)
                        .accessibilityIdentifier("sourceImport.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

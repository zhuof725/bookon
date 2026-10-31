import SwiftUI

/// 分享/文件打开进来的书源 JSON：先展示条数和名称，用户确认后再导入。
struct PendingSourceImport: Identifiable {
    let id = UUID()
    let fileName: String
    let text: String
    let sourceNames: [String]
}

/// 全屏覆盖层而不是 sheet：冷启动/其他弹窗存在时也能稳定出现。
struct SourceImportConfirmation: View {
    @ThemePalette private var palette
    let pending: PendingSourceImport
    let onCancel: () -> Void
    /// 返回导入结果文案；非 nil 时页面切换到结果状态。
    let onImport: () -> String

    @State private var result: String?

    var body: some View {
        ZStack {
            AppThemeCanvas().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("导入书源").appFont(.title2.weight(.bold))
                    Spacer()
                    Button("取消", action: onCancel)
                        .accessibilityIdentifier("sourceImport.cancel")
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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

                        if let result {
                            Text(result)
                                .appFont(.body)
                                .foregroundStyle(palette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("导入后会替换同名书源，不影响书架里的书。")
                                .appFont(.footnote)
                                .foregroundStyle(palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if result == nil {
                    Button {
                        result = onImport()
                    } label: {
                        Text("导入")
                            .appFont(.headline)
                            .foregroundStyle(palette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Capsule().fill(palette.accent))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sourceImport.confirm")
                } else {
                    Button(action: onCancel) {
                        Text("完成")
                            .appFont(.headline)
                            .foregroundStyle(palette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Capsule().fill(palette.accent))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sourceImport.done")
                }
            }
            .padding(20)
        }
        .foregroundStyle(palette.primary)
    }
}

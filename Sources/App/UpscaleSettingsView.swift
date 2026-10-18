import SwiftUI

/// 图片超分设置：漫画页 / 封面开关、档位与模型管理。
/// 模型来自 Aidoku 的公开模型仓库（waifu2x 1.1MB、Real-ESRGAN 34MB），下载后本机缓存。
struct UpscaleSettingsView: View {
    @ThemePalette private var palette
    @AppStorage(UpscaleSettings.mangaKey) private var mangaEnabled = false
    @AppStorage(UpscaleSettings.coverKey) private var coverEnabled = false
    @AppStorage(UpscaleSettings.qualityKey) private var qualityRaw = UpscaleQuality.fast.rawValue

    @State private var models: [UpscaleModelInfo] = []
    @State private var installed: [String] = []
    @State private var progressByFile: [String: Double] = [:]
    @State private var notice: String?

    private var quality: Binding<UpscaleQuality> {
        Binding(get: { UpscaleQuality(rawValue: qualityRaw) ?? .fast },
                set: { qualityRaw = $0.rawValue })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                toggleRow(title: "漫画页超分",
                          subtitle: "阅读器里的图片按需放大 2 倍，原图已经够大时自动跳过",
                          isOn: $mangaEnabled)
                toggleRow(title: "封面超分",
                          subtitle: "书架与详情页的封面放大 2 倍，结果会缓存到本机",
                          isOn: $coverEnabled)

                VStack(alignment: .leading, spacing: 10) {
                    Text("档位").appFont(.body).foregroundStyle(palette.primary)
                    Picker("档位", selection: quality) {
                        ForEach(UpscaleQuality.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(quality.wrappedValue.detail)
                        .appFont(.caption).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SettingsGlassSurface())

                ForEach(modelRows, id: \.file) { row in
                    modelRow(row)
                }

                if let notice {
                    Text(notice)
                        .appFont(.caption).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("超分用 Core ML 模型在本机推理，不上传图片。放大只在原图小于显示尺寸时进行：长条漫与高清单图会跳过，避免内存和耗时失控。模型文件下载后保存在本机，可随时删除。")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("图片超分")
        .toolbar(.visible, for: .navigationBar)
        .task { await refresh() }
    }

    // MARK: 行

    private struct ModelRow {
        let file: String
        let name: String
        let info: String
        let size: Int
        let installed: Bool
        let progress: Double?
    }

    private var modelRows: [ModelRow] {
        var rows: [ModelRow] = []
        for quality in UpscaleQuality.allCases {
            let info = models.first { $0.fileName == quality.modelFile }
            rows.append(ModelRow(
                file: quality.modelFile,
                name: info?.name ?? quality.title,
                info: quality.detail,
                size: info?.size ?? quality.modelSize,
                installed: installed.contains(quality.modelFile),
                progress: progressByFile[quality.modelFile]))
        }
        // 仓库里额外的模型（如果以后加了）也列出来。
        for info in models where !UpscaleQuality.allCases.contains(where: { $0.modelFile == info.fileName }) {
            rows.append(ModelRow(file: info.fileName,
                                 name: info.name,
                                 info: info.info ?? "",
                                 size: info.size ?? 0,
                                 installed: installed.contains(info.fileName),
                                 progress: progressByFile[info.fileName]))
        }
        return rows
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                Text(title).appFont(.body).foregroundStyle(palette.primary)
            }
            .accessibilityIdentifier("upscale.\(title)")
            Text(subtitle)
                .appFont(.caption).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsGlassSurface())
    }

    @ViewBuilder
    private func modelRow(_ row: ModelRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).appFont(.body).foregroundStyle(palette.primary)
                    if !row.info.isEmpty {
                        Text(row.info).appFont(.caption).foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Text(row.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(row.size), countStyle: .file) : "")
                    .appFont(.caption).foregroundStyle(palette.secondary).fixedSize()
            }
            if let progress = row.progress {
                ProgressView(value: progress)
                    .tint(palette.accent)
            } else {
                HStack(spacing: 10) {
                    if row.installed {
                        Label("已安装", systemImage: "checkmark.circle.fill")
                            .appFont(.caption).foregroundStyle(palette.accent)
                        Spacer(minLength: 8)
                        Button(role: .destructive) {
                            Task { await remove(row.file) }
                        } label: {
                            Text("删除").appFont(.caption)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Spacer(minLength: 8)
                        Button {
                            Task { await download(row.file) }
                        } label: {
                            Text("下载").appFont(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsGlassSurface())
    }

    // MARK: 动作

    private func refresh() async {
        let store = UpscaleModelStore.shared
        models = await store.availableModels()
        installed = await store.installedFileNames()
    }

    private func download(_ file: String) async {
        guard let info = models.first(where: { $0.fileName == file }) else { return }
        let store = UpscaleModelStore.shared
        progressByFile[file] = 0
        do {
            try await store.download(info) { value in
                Task { @MainActor in progressByFile[file] = value }
            }
            progressByFile[file] = nil
            installed = await store.installedFileNames()
            notice = "\(info.name) 已安装"
            UpscaleImageCache.pruneIfNeeded()
        } catch {
            progressByFile[file] = nil
            notice = "下载失败：\(error.localizedDescription)"
        }
    }

    private func remove(_ file: String) async {
        await UpscaleModelStore.shared.remove(file)
        installed = await UpscaleModelStore.shared.installedFileNames()
        notice = "已删除模型"
    }
}

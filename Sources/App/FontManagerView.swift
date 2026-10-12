import SwiftUI
import UniformTypeIdentifiers

struct FontManagerView: View {
    @ObservedObject private var manager: ReadingFontManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var importProgress = ""
    @State private var pendingRemoval: ImportedReadingFont?
    @State private var showingRemoval = false
    @State private var resultMessage: String?
    @State private var showingResult = false

    init(manager: ReadingFontManager = .shared) {
        _manager = ObservedObject(wrappedValue: manager)
    }

    private var supportedTypes: [UTType] {
        [.font] + ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    if let notice = manager.notice { noticeCard(notice) }
                    if isImporting {
                        HStack(spacing: 12) {
                            ProgressView().tint(AppPalette.accent)
                            Text(importProgress).font(.subheadline)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 16)))
                        .accessibilityIdentifier("fonts.loading")
                    }
                    builtInSection
                    importedSection
                    Text("仅使用设备已有字体或你选择的本地文件。不会联网下载字体，也不会改变应用界面的字体。请确认你拥有所导入字体的使用权。")
                        .font(.footnote).foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 32)
            }
        }
        .foregroundStyle(AppPalette.accent)
        .background(AppPalette.background.ignoresSafeArea())
        .tint(AppPalette.accent)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isImporting)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: supportedTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                    presentResult("无法打开字体文件：\(error.localizedDescription)")
                }
            }
        }
        .confirmationDialog("移除字体文件？", isPresented: $showingRemoval, titleVisibility: .visible) {
            Button("移除字体文件", role: .destructive) { removePendingFont() }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let file = pendingRemoval {
                Text("将移除「\(file.originalName)」中的全部字体，仅删除应用内副本。如果正在使用其中的字体，将恢复系统默认。原始文件不受影响。")
            }
        }
        .alert("字体管理", isPresented: $showingResult) {
            Button("好", role: .cancel) { resultMessage = nil }
        } message: { Text(resultMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .modifier(ShelfGlass(shape: Circle()))
            .accessibilityLabel("返回").accessibilityIdentifier("fonts.back")
            .disabled(isImporting)
            Text("阅读字体").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { showingImporter = true } label: {
                Label("导入", systemImage: "plus").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).frame(minHeight: 44)
            }
            .modifier(ShelfGlass(shape: Capsule()))
            .accessibilityLabel("导入字体文件").accessibilityIdentifier("fonts.import")
            .disabled(isImporting)
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("让文字，合你心意。")
                .font(.system(size: 26, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("当前：\(manager.selectedDisplayName)")
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("fonts.current")
            Text("支持 TTF / OTF / TTC · 单文件不超过 32 MB · 最多 30 个文件。导入后请点选字体，切换字体会重新分页。")
                .font(.footnote).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("设备字体", detail: "仅显示本机可用字体")
            VStack(spacing: 0) {
                ForEach(manager.builtInFonts) { choice in
                    choiceRow(choice)
                    if choice.id != manager.builtInFonts.last?.id { Divider().padding(.horizontal, 16) }
                }
            }
            .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 20)))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .disabled(isImporting)
        }
    }

    private var importedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("我的字体", detail: "\(manager.importedFonts.count) / 30 个文件")
            if manager.importedFonts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "textformat").font(.system(size: 30, weight: .light))
                    Text("还没有导入字体").font(.headline)
                    Text("点右上角「导入」，从“文件”选择字体。\n只保存应用内副本，不会修改原文件。")
                        .font(.footnote).foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(28).frame(maxWidth: .infinity)
                .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 20)))
                .accessibilityIdentifier("fonts.empty")
            } else {
                ForEach(manager.importedFonts) { file in fileCard(file) }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(detail).font(.caption).foregroundStyle(AppPalette.secondary)
        }
    }

    private func choiceRow(_ choice: ReadingFontChoice) -> some View {
        let selected = manager.selectedPostScriptName == choice.id
        return Button {
            do { try manager.select(choice.id) }
            catch { presentResult(error.localizedDescription) }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(choice.name).font(.subheadline.weight(.semibold))
                        if !choice.id.isEmpty {
                            Text(choice.id).font(.caption2).foregroundStyle(AppPalette.secondary)
                                .lineLimit(2).textSelection(.disabled)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).accessibilityHidden(true)
                }
                Text("春风有信，花开有期。\nThe quick brown fox 0123456789")
                    .font(choice.id.isEmpty ? .system(size: 20) : .custom(choice.id, size: 20))
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(choice.id.isEmpty ? "沿用阅读器原有默认字体" : "缺失字形由系统字体补全")
                    .font(.caption2).foregroundStyle(AppPalette.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppPalette.selection.opacity(0.55) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name + (choice.id.isEmpty ? "，沿用原有默认字体" : "，" + choice.id))
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityHint("设为阅读字体并重新分页")
        .accessibilityIdentifier(choice.id.isEmpty ? "fonts.system" : "fonts.choice." + choice.id)
    }

    private func fileCard(_ file: ImportedReadingFont) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.originalName).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(file.faces.count) 个字形样式 · \(ByteCountFormatter.string(fromByteCount: Int64(file.fileSize), countStyle: .file))")
                        .font(.caption).foregroundStyle(AppPalette.secondary)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    pendingRemoval = file
                    showingRemoval = true
                } label: {
                    Image(systemName: "trash").font(.system(size: 16))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.accent)
                .accessibilityLabel("移除字体文件：" + file.originalName)
                .accessibilityIdentifier("fonts.delete." + file.id)
            }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 12)
            Divider().padding(.horizontal, 16)
            if file.faces.isEmpty {
                Text("文件缺失或无法加载。可移除后重新导入。")
                    .font(.footnote).foregroundStyle(AppPalette.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(file.faces) { choice in
                    choiceRow(choice)
                    if choice.id != file.faces.last?.id { Divider().padding(.horizontal, 16) }
                }
            }
        }
        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 20)))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .disabled(isImporting)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fonts.file." + file.id)
    }

    private func noticeCard(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").accessibilityHidden(true)
            Text(notice).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { manager.dismissNotice() } label: {
                Image(systemName: "xmark").font(.caption).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain).accessibilityLabel("关闭字体提示")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 16)))
        .accessibilityIdentifier("fonts.notice")
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        importProgress = "正在准备导入…"
        // Mutations stay on the main actor. Yield between files so the native
        // progress indicator and controls update, without actor-isolating the model.
        Task { @MainActor in
            var added = 0
            var duplicates = 0
            var failures: [String] = []
            defer {
                isImporting = false
                importProgress = ""
            }
            for (index, url) in urls.enumerated() {
                importProgress = "正在导入 \(index + 1) / \(urls.count)：\(url.lastPathComponent)"
                // Give SwiftUI a frame to present the progress state before bounded I/O.
                try? await Task.sleep(nanoseconds: 20_000_000)
                let before = Set(manager.importedFonts.map(\.id))
                do {
                    let file = try manager.importFont(from: url)
                    if before.contains(file.id) { duplicates += 1 } else { added += 1 }
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }
            var summary = "新增 \(added) 个文件，跳过 \(duplicates) 个重复文件，失败 \(failures.count) 个。"
            summary += "\n当前阅读字体未改变；请在列表中点选要使用的字体。"
            if !failures.isEmpty { summary += "\n\n" + failures.joined(separator: "\n\n") }
            presentResult(summary)
        }
    }

    private func removePendingFont() {
        guard let file = pendingRemoval else { return }
        pendingRemoval = nil
        do { try manager.remove(file) }
        catch { presentResult(error.localizedDescription) }
    }

    private func presentResult(_ text: String) {
        resultMessage = text
        showingResult = true
    }
}

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// File-provider access and image validation are delegated to the owned asset store.
struct ThemeImagePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.loadViewIfNeeded()
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.title = "选择主题图片"
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        var onCancel: () -> Void
        private var finished = false
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }; finished = true
            if let url = urls.first { onPick(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }; finished = true; onCancel()
        }
    }
}

enum ThemeEditorImageKind: String, Identifiable {
    case cover, launch, background
    var id: String { rawValue }
    var keyPath: WritableKeyPath<ThemeCustomization, String?> {
        switch self {
        case .cover: return \.defaultCoverImage
        case .launch: return \.launchImage
        case .background: return \.pageBackgroundImage
        }
    }
    var title: String {
        switch self {
        case .cover: return "默认封面"
        case .launch: return "启动图"
        case .background: return "背景图片"
        }
    }
    var emptyLabel: String {
        switch self {
        case .cover: return "系统默认封面"
        case .launch: return "启动图已关闭"
        case .background: return "使用主题底色"
        }
    }
    var resetLabel: String {
        switch self {
        case .cover: return "恢复系统默认"
        case .launch: return "移除并关闭启动图"
        case .background: return "移除背景图片"
        }
    }
    var detail: String {
        switch self {
        case .cover: return "仅用于没有可用封面的书籍，不替换书籍已有封面。预览显示所选原图，书架会按封面比例裁切。"
        case .launch: return "这是应用打开后的启动展示层，并非 iOS 系统启动屏。应用主题后，下次打开时显示，且始终可以跳过。移除图片即可关闭。"
        case .background: return "应用页面使用所选图片，文字区域仍保留可读底色。移除图片后，恢复下方设置的纯色或渐变。阅读纸张不受影响。"
        }
    }
}

struct ThemeEditorImageSettings: View {
    let kind: ThemeEditorImageKind
    @Binding var assetID: String?
    let importImage: () -> Void
    @State private var showingLaunchPreview = false
    private var image: UIImage? { ThemeAssetStore.shared.image(for: assetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind.detail).appFont(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: kind == .cover ? 240 : 200)
                    .padding(14).themeEditorSurface()
                    .accessibilityLabel("\(kind.title)原图预览")
                    .accessibilityIdentifier("theme.editor.image.\(kind.rawValue).preview")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: kind == .cover ? "book.closed" : "photo")
                        .font(.system(size: 34, weight: .light)).accessibilityHidden(true)
                    Text(assetID == nil ? kind.emptyLabel : "图片不可用，请重新选择或移除")
                        .appFont(.body).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(minHeight: 150)
                .padding(16).themeEditorSurface()
                .accessibilityIdentifier("theme.editor.image.\(kind.rawValue).empty")
            }
            Button(action: importImage) {
                Label(assetID == nil ? "从文件选择图片" : "更换图片", systemImage: "folder")
                    .appFont(.body).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("theme.editor.image.\(kind.rawValue).import")
            if assetID != nil {
                Button(kind.resetLabel, role: .destructive) { assetID = nil }
                    .appFont(.body).frame(minHeight: 44)
                    .accessibilityIdentifier("theme.editor.image.\(kind.rawValue).remove")
            }
            if kind == .launch, image != nil {
                Button("预览启动展示") { showingLaunchPreview = true }
                    .appFont(.body).frame(minHeight: 44)
                    .accessibilityIdentifier("theme.editor.launch.preview")
            }
        }
        .fullScreenCover(isPresented: $showingLaunchPreview) {
            if let image {
                ThemeLaunchOverlay(image: image, onDismiss: { showingLaunchPreview = false })
            }
        }
    }
}

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Native UIKit Files importer. Copy mode supplies temporary local copies;
/// ReadingFontManager then validates and persists its own owned copies.
struct FontDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    static var contentTypes: [UTType] {
        var identifiers = Set<String>()
        return ([.font] + ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) })
            .filter { identifiers.insert($0.identifier).inserted }
    }

    static func makePicker(delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = delegate
        picker.title = "导入字体"
        picker.view.tintColor = .label
        return picker
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        Self.makePicker(delegate: context.coordinator)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void
        var onCancel: () -> Void
        private var finished = false

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }
            finished = true
            if urls.isEmpty { onCancel() }
            else { onPick(urls) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            onCancel()
        }
    }
}

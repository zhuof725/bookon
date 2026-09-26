import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit document picker wrapped for SwiftUI (per user's request).
struct DocumentPicker: UIViewControllerRepresentable {
    var types: [String] = ["txt"]
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var utTypes: [UTType] = types.compactMap { UTType(filenameExtension: $0) }
        if types.contains("txt") { utTypes += [.plainText, .text] }
        if types.contains("json") { utTypes.append(.json) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: utTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

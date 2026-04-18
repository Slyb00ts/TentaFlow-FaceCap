// =============================================================================
// Plik: FilesAppExporter.swift
// Opis: UIDocumentPickerViewController w trybie forExporting dla jednego pliku .face.
// =============================================================================

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Eksporter do aplikacji „Pliki” — prezentuje natywny picker i pozwala
/// zapisać plik `.face` w iCloud Drive, Dropbox, OneDrive, itd.
public struct FilesAppExporter: UIViewControllerRepresentable {

    private let fileURL: URL
    private let onCompletion: (Bool) -> Void

    public init(fileURL: URL, onCompletion: @escaping (Bool) -> Void) {
        self.fileURL = fileURL
        self.onCompletion = onCompletion
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        vc.delegate = context.coordinator
        vc.shouldShowFileExtensions = true
        return vc
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public final class Coordinator: NSObject, UIDocumentPickerDelegate {

        private let onCompletion: (Bool) -> Void

        init(onCompletion: @escaping (Bool) -> Void) {
            self.onCompletion = onCompletion
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController,
                                   didPickDocumentsAt urls: [URL]) {
            onCompletion(!urls.isEmpty)
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(false)
        }
    }
}

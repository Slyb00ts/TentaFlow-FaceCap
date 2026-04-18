// =============================================================================
// Plik: ShareSheetController.swift
// Opis: UIViewControllerRepresentable wokół UIActivityViewController (share sheet).
// =============================================================================

import SwiftUI
import UIKit

/// SwiftUI wrapper na system share sheet — prezentuje plik lub URL do wyboru
/// różnych akcji (AirDrop, Files, Mail, Messages, itd.).
public struct ShareSheetController: UIViewControllerRepresentable {

    private let items: [Any]
    private let excludedActivityTypes: [UIActivity.ActivityType]
    private let onCompletion: ((Bool) -> Void)?

    public init(items: [Any],
                excludedActivityTypes: [UIActivity.ActivityType] = [],
                onCompletion: ((Bool) -> Void)? = nil) {
        self.items = items
        self.excludedActivityTypes = excludedActivityTypes
        self.onCompletion = onCompletion
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes
        vc.completionWithItemsHandler = { _, completed, _, _ in
            self.onCompletion?(completed)
        }
        return vc
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

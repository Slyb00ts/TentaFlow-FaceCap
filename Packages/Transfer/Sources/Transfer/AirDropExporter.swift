// =============================================================================
// Plik: AirDropExporter.swift
// Opis: Wrapper nad share sheet ograniczony tylko do akcji AirDrop.
// =============================================================================

import SwiftUI
import UIKit

/// Eksporter AirDrop — otwiera share sheet z wszystkimi typami akcji wyłączonymi
/// poza AirDropem (użytkownik widzi tylko listę pobliskich urządzeń).
public struct AirDropExporter: View {

    private let fileURL: URL
    private let onCompletion: ((Bool) -> Void)?

    public init(fileURL: URL, onCompletion: ((Bool) -> Void)? = nil) {
        self.fileURL = fileURL
        self.onCompletion = onCompletion
    }

    public var body: some View {
        ShareSheetController(
            items: [fileURL],
            excludedActivityTypes: [
                .addToReadingList,
                .assignToContact,
                .copyToPasteboard,
                .mail,
                .markupAsPDF,
                .message,
                .openInIBooks,
                .postToFacebook,
                .postToFlickr,
                .postToTencentWeibo,
                .postToTwitter,
                .postToVimeo,
                .postToWeibo,
                .print,
                .saveToCameraRoll
            ],
            onCompletion: onCompletion
        )
    }
}

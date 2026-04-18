// =============================================================================
// Plik: TransferProgressView.swift
// Opis: Wybór transferu (AirDrop / Files / Wi-Fi) i pokazanie postępu.
// =============================================================================

import SwiftUI
import Shared
import Transfer

struct TransferProgressView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment

    @State private var selectedMethod: TransferMethod = .wifi
    @State private var showShareSheet = false
    @State private var showFilesPicker = false
    @State private var error: String?
    @State private var isUploading = false

    enum TransferMethod: String, CaseIterable, Identifiable {
        case airdrop, files, wifi
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("transfer.title", comment: ""))
                .font(.largeTitle.bold())

            if let url = environment.session.lastExportedFileURL {
                Text(url.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Picker(NSLocalizedString("transfer.method", comment: ""), selection: $selectedMethod) {
                    Text(NSLocalizedString("transfer.airdrop", comment: "")).tag(TransferMethod.airdrop)
                    Text(NSLocalizedString("transfer.files", comment: "")).tag(TransferMethod.files)
                    Text(NSLocalizedString("transfer.wifi", comment: "")).tag(TransferMethod.wifi)
                }
                .pickerStyle(.segmented)

                ProgressView(value: environment.transferProgress.progress) {
                    Text(environment.transferProgress.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.accent)
                .padding()

                statusText

                Spacer()

                Button(NSLocalizedString("transfer.send", comment: "")) {
                    start(url: url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(isUploading)

                Button(NSLocalizedString("transfer.finish", comment: "")) {
                    router.advance()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            } else {
                Text(NSLocalizedString("transfer.nofile", comment: ""))
                Button(NSLocalizedString("common.back", comment: "")) {
                    router.back()
                }
            }
        }
        .padding()
        .sheet(isPresented: $showShareSheet) {
            if let url = environment.session.lastExportedFileURL {
                AirDropExporter(fileURL: url) { completed in
                    showShareSheet = false
                    if completed { environment.transferProgress.setStatus(.finished) }
                }
            }
        }
        .sheet(isPresented: $showFilesPicker) {
            if let url = environment.session.lastExportedFileURL {
                FilesAppExporter(fileURL: url) { completed in
                    showFilesPicker = false
                    if completed { environment.transferProgress.setStatus(.finished) }
                }
            }
        }
        .alert(NSLocalizedString("transfer.error.title", comment: ""),
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch environment.transferProgress.status {
        case .idle:
            Text(NSLocalizedString("transfer.status.idle", comment: "")).foregroundStyle(.secondary)
        case .preparing:
            Text(NSLocalizedString("transfer.status.preparing", comment: "")).foregroundStyle(.orange)
        case .transferring:
            Text(NSLocalizedString("transfer.status.transferring", comment: "")).foregroundStyle(.blue)
        case .finished:
            Text(NSLocalizedString("transfer.status.finished", comment: "")).foregroundStyle(.green)
        case .failed(let why):
            Text(why).foregroundStyle(.red)
        }
    }

    private func start(url: URL) {
        environment.transferProgress.reset()
        switch selectedMethod {
        case .airdrop:
            showShareSheet = true
        case .files:
            showFilesPicker = true
        case .wifi:
            isUploading = true
            Task {
                let uploader = WiFiUploader(progress: environment.transferProgress)
                do {
                    try await uploader.upload(fileURL: url)
                } catch {
                    self.error = error.localizedDescription
                    environment.transferProgress.setStatus(.failed(error.localizedDescription))
                }
                isUploading = false
            }
        }
    }
}

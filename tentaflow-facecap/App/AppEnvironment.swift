// =============================================================================
// Plik: AppEnvironment.swift
// Opis: Kontener zależności — sesje kamery, coordynator skanu, permissions.
// =============================================================================

import Foundation
import AVFoundation
import Combine
import SwiftUI
import Shared
import Export
import Transfer

/// Model trzymany w sesji — gromadzi dane zbierane w trakcie flow.
@MainActor
public final class SessionModel: ObservableObject {

    // Skan głowy.
    @Published public var scannedMeshVertices: [Vec3] = []
    @Published public var scannedMeshNormals: [Vec3] = []
    @Published public var scannedMeshUVs: [Vec2] = []
    @Published public var scannedMeshTriangles: [SIMD3<UInt16>] = []
    @Published public var scannedTexture: CGImage?
    @Published public var lidarUsed: Bool = false
    @Published public var coverage: Double = 0.0

    // Neutral baseline.
    @Published public var neutralValidated: Bool = false

    // Kalibracja — wagi docelowe i delty per AU.
    @Published public var calibratedDeltas: [Int: [Vec3]] = [:]
    @Published public var acceptedAU: Set<Int> = []
    @Published public var skippedAU: Set<Int> = []

    // Performance clips.
    @Published public var performanceClips: [PerformanceClip] = []

    // Preview i export.
    @Published public var profileName: String = "twarz_01"
    @Published public var lastExportedFileURL: URL?
}

/// Kontener DI — lazy stored properties, aby uniknąć tworzenia ciężkich obiektów
/// zanim są potrzebne.
@MainActor
public final class AppEnvironment: ObservableObject {

    // Współdzielone zależności.
    public lazy var session: SessionModel = SessionModel()
    public lazy var transferProgress: TransferProgress = TransferProgress()
    public lazy var thermalObserver: ThermalStateObserver = ThermalStateObserver()
    public lazy var writer: FaceFileWriter = FaceFileWriter()
    public lazy var validator: FaceFileValidator = FaceFileValidator()

    @Published public var cameraAuthorized: Bool = false
    @Published public var microphoneAuthorized: Bool = false

    public init() {}

    // MARK: — Uprawnienia

    /// Prosi o zgodę na kamerę i mikrofon. Wywoływane z Onboardingu.
    public func requestPermissions() async {
        let cam = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                c.resume(returning: granted)
            }
        }
        let mic = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                c.resume(returning: granted)
            }
        }
        await MainActor.run {
            self.cameraAuthorized = cam
            self.microphoneAuthorized = mic
        }
        AppLog.app.info("Permissions: cam=\(cam), mic=\(mic)")
    }

    /// Aktualny stan uprawnień (bez pytania).
    public func refreshPermissions() {
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

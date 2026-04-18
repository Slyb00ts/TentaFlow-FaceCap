// =============================================================================
// Plik: DeviceCapabilities.swift
// Opis: Wykrywa możliwości urządzenia (LiDAR, TrueDepth, model, thermal state).
// =============================================================================

import Foundation
import UIKit
#if canImport(ARKit)
import ARKit
#endif
import Combine

/// Informacje o możliwościach urządzenia dostarczane aplikacji.
public struct DeviceCapabilities: Sendable {

    /// Czy urządzenie ma skaner LiDAR (iPhone 12 Pro+, iPad Pro 2020+).
    public static var hasLiDAR: Bool {
        #if canImport(ARKit)
        if #available(iOS 13.4, *) {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
        return false
        #else
        return false
        #endif
    }

    /// Czy urządzenie ma kamerę TrueDepth (iPhone X+).
    public static var hasTrueDepth: Bool {
        #if canImport(ARKit)
        return ARFaceTrackingConfiguration.isSupported
        #else
        return false
        #endif
    }

    /// Zidentyfikowany model urządzenia (np. „iPhone15,3”).
    public static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// Czytelna nazwa systemu, np. „iOS 17.4”.
    public static var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
}

/// Obserwator stanu termicznego — publikuje każdą zmianę.
public final class ThermalStateObserver: ObservableObject {

    @Published public private(set) var state: ProcessInfo.ThermalState

    private var observer: NSObjectProtocol?

    public init() {
        self.state = ProcessInfo.processInfo.thermalState
        self.observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.state = ProcessInfo.processInfo.thermalState
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Zwraca `true`, gdy urządzenie jest gorące (serious/critical).
    public var isHot: Bool {
        state == .serious || state == .critical
    }
}

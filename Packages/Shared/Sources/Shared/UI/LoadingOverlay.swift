// =============================================================================
// Plik: LoadingOverlay.swift
// Opis: Nakładka SwiftUI z animowanym pierścieniem postępu — używana globalnie.
// =============================================================================

import SwiftUI

/// Nakładka ładowania z animowanym pierścieniem. Może pokazywać tekst statusu
/// i procentowy postęp (0…1).
public struct LoadingOverlay: View {

    private let title: String
    private let progress: Double?

    public init(title: String, progress: Double? = nil) {
        self.title = title
        self.progress = progress
    }

    @State private var rotation: Double = 0

    public var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                        .frame(width: 72, height: 72)

                    if let progress {
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 72, height: 72)
                    } else {
                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(rotation))
                            .frame(width: 72, height: 72)
                            .onAppear {
                                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                                    rotation = 360
                                }
                            }
                    }
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let progress {
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

#Preview {
    LoadingOverlay(title: "Zapisywanie pliku .face v3", progress: 0.64)
}

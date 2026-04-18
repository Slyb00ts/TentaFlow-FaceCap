// =============================================================================
// Plik: HeadScanBriefView.swift
// Opis: Brief przed skanowaniem — animowany diagram + lista wymagań + CTA.
// =============================================================================

import SwiftUI
import Shared

struct HeadScanBriefView: View {

    @EnvironmentObject private var router: AppRouter
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animowany diagram — ikona głowy obracająca się wokół osi Y.
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(rotation))
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .foregroundStyle(Color.accentColor)
                    .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
            }
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }

            Text(NSLocalizedString("scan.brief.title", comment: ""))
                .font(.title.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                row(icon: "sun.max.fill", text: NSLocalizedString("scan.req.light", comment: ""))
                row(icon: "face.smiling", text: NSLocalizedString("scan.req.neutral", comment: ""))
                row(icon: "eyebrow", text: NSLocalizedString("scan.req.hair", comment: ""))
                row(icon: "eyeglasses", text: NSLocalizedString("scan.req.glasses", comment: ""))
                row(icon: "ruler", text: NSLocalizedString("scan.req.distance", comment: ""))
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            Spacer()

            Button(NSLocalizedString("scan.brief.cta", comment: "")) {
                router.advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)

            Button(NSLocalizedString("common.back", comment: "")) {
                router.back()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
        .padding()
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.accent).frame(width: 24)
            Text(text)
            Spacer()
        }
    }
}

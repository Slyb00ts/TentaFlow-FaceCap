// =============================================================================
// Plik: CalibrationBriefView.swift
// Opis: Krótki przegląd 52 AU — co będzie się działo i dlaczego to ma znaczenie.
// =============================================================================

import SwiftUI
import Shared

struct CalibrationBriefView: View {

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(NSLocalizedString("calib.brief.title", comment: ""))
                    .font(.largeTitle.bold())

                Text(NSLocalizedString("calib.brief.intro", comment: ""))
                    .foregroundStyle(.secondary)

                Group {
                    label(icon: "number", title: NSLocalizedString("calib.brief.count.title", comment: ""),
                          text: NSLocalizedString("calib.brief.count.desc", comment: ""))
                    label(icon: "stopwatch", title: NSLocalizedString("calib.brief.time.title", comment: ""),
                          text: NSLocalizedString("calib.brief.time.desc", comment: ""))
                    label(icon: "checkmark.seal", title: NSLocalizedString("calib.brief.quality.title", comment: ""),
                          text: NSLocalizedString("calib.brief.quality.desc", comment: ""))
                    label(icon: "face.smiling.fill", title: NSLocalizedString("calib.brief.neutral.title", comment: ""),
                          text: NSLocalizedString("calib.brief.neutral.desc", comment: ""))
                }

                Divider()

                Text(NSLocalizedString("calib.brief.hint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 24)

                Button(NSLocalizedString("calib.brief.cta", comment: "")) {
                    router.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("common.back", comment: "")) {
                    router.back()
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private func label(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

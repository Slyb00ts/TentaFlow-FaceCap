// =============================================================================
// Plik: HeadScanPreviewView.swift
// Opis: Podgląd wyskanowanej siatki 3D w RealityView — akceptuj lub powtórz.
// =============================================================================

import SwiftUI
import RealityKit
import Shared

struct HeadScanPreviewView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment

    @State private var rotationY: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("scan.preview.title", comment: ""))
                .font(.title2.bold())

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.5))
                RealityView { content in
                    let mesh = buildMeshResource()
                    let material = SimpleMaterial(color: UIColor(white: 0.95, alpha: 1.0), isMetallic: false)
                    let entity = ModelEntity(mesh: mesh, materials: [material])
                    entity.transform.rotation = simd_quatf(angle: Float(rotationY * .pi / 180), axis: [0, 1, 0])
                    let anchor = AnchorEntity(world: .zero)
                    anchor.addChild(entity)
                    content.add(anchor)
                } update: { content in
                    if let anchor = content.entities.first,
                       let model = anchor.children.first as? ModelEntity {
                        model.transform.rotation = simd_quatf(
                            angle: Float(rotationY * .pi / 180),
                            axis: [0, 1, 0]
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .onAppear {
                    withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                        rotationY = 360
                    }
                }
            }
            .padding(.horizontal)

            VStack(spacing: 6) {
                Text(String(format: NSLocalizedString("scan.preview.verts", comment: ""),
                            environment.session.scannedMeshVertices.count))
                Text(String(format: NSLocalizedString("scan.preview.tris", comment: ""),
                            environment.session.scannedMeshTriangles.count))
                Text(String(format: NSLocalizedString("scan.preview.coverage", comment: ""),
                            Int(environment.session.coverage * 100)))
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Button(NSLocalizedString("scan.preview.retry", comment: "")) {
                    router.go(to: .headScanCapture)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("scan.preview.accept", comment: "")) {
                    router.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    /// Buduje `MeshResource` z danych sesji.
    private func buildMeshResource() -> MeshResource {
        let verts = environment.session.scannedMeshVertices
        let tris = environment.session.scannedMeshTriangles

        var descriptor = MeshDescriptor(name: "head-scan")
        descriptor.positions = MeshBuffers.Positions(verts.map { SIMD3<Float>($0.x, $0.y, $0.z) })

        var indices: [UInt32] = []
        indices.reserveCapacity(tris.count * 3)
        for t in tris {
            indices.append(UInt32(t.x))
            indices.append(UInt32(t.y))
            indices.append(UInt32(t.z))
        }
        descriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            // Fallback — prosta kula, gdyby mesh był pusty.
            AppLog.headscan.error("Mesh generation failed: \(error.localizedDescription, privacy: .public)")
            return MeshResource.generateSphere(radius: 0.1)
        }
    }
}

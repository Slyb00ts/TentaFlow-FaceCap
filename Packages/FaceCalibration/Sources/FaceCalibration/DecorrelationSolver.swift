// =============================================================================
// Plik: DecorrelationSolver.swift
// Opis: Dekorelacja 52 AU przez rozwiązanie W·D = D_obs (LAPACK dgesv_) per wierzchołek.
// =============================================================================

import Foundation
import Accelerate
import simd

/// Rozwiązuje układ W · D = D_obs dla 52 AU per wierzchołek.
/// W — macierz 52×52 zaobserwowanych wag, każdy wiersz to observedWeights konkretnego przechwytu.
/// D_obs — obserwowana delta wierzchołka, rozbita na 3 komponenty (x, y, z).
/// D — "czysta" delta dekorelowana.
public struct DecorrelationSolver: Sendable {
    public init() {}

    /// Wykonuje dekorelację.
    /// - Parameter observedDeltas: lista delta, kolejność odpowiada ArkitAU.rawValue (długość 52).
    /// - Returns: 52 nowe delta z "czystą" geometrią.
    public func decorrelate(observedDeltas: [BlendshapeDelta]) throws -> [BlendshapeDelta] {
        let auCount = ArkitAU.allCases.count
        guard observedDeltas.count == auCount else {
            throw FaceCalibrationError.solverFailed(reason: "Oczekiwano \(auCount) delta, dostałem \(observedDeltas.count).")
        }
        guard let first = observedDeltas.first else {
            throw FaceCalibrationError.solverFailed(reason: "Pusta tablica delta.")
        }
        let vertexCount = first.verts.count
        guard vertexCount > 0 else {
            throw FaceCalibrationError.solverFailed(reason: "Brak wierzchołków w delta.")
        }

        // Budujemy macierz W 52×52 (kolumna-major wymagane przez LAPACK).
        // W[i][j] = observedDeltas[i].observedWeights[j]
        // Wiersz i odpowiada obserwacji AU i (idealnie W diagonal=1).
        var W = [Double](repeating: 0, count: auCount * auCount)
        for i in 0..<auCount {
            let weights = observedDeltas[i].observedWeights
            guard weights.count == auCount else {
                throw FaceCalibrationError.solverFailed(reason: "observedWeights dla AU \(i) nie ma \(auCount) elementów.")
            }
            for j in 0..<auCount {
                // LAPACK kolumna-major: W[i + j*auCount].
                W[i + j * auCount] = Double(weights[j])
            }
        }

        // Regularyzacja — dodajemy ε·I, żeby ryzyko osobliwości było znikome.
        let epsilon = 1e-4
        for i in 0..<auCount {
            W[i + i * auCount] += epsilon
        }

        // Każdy wierzchołek: 3 niezależne komponenty (x,y,z) → batch RHS.
        // Rozwiązujemy W · X = B gdzie B to macierz 52 × (vertexCount*3) — RHS kolumna-major.
        let rhsCount = vertexCount * 3

        // Przygotuj bufor B (output jest in-place).
        var B = [Double](repeating: 0, count: auCount * rhsCount)
        for auIdx in 0..<auCount {
            let delta = observedDeltas[auIdx].verts
            guard delta.count == vertexCount else {
                throw FaceCalibrationError.solverFailed(reason: "Delta AU \(auIdx) ma \(delta.count) wierzchołków, oczekiwano \(vertexCount).")
            }
            for v in 0..<vertexCount {
                let vec = delta[v]
                // Kolumny w B: [v*3 + 0] = x, [v*3 + 1] = y, [v*3 + 2] = z.
                // B[auIdx + col*auCount].
                B[auIdx + (v * 3 + 0) * auCount] = Double(vec.x)
                B[auIdx + (v * 3 + 1) * auCount] = Double(vec.y)
                B[auIdx + (v * 3 + 2) * auCount] = Double(vec.z)
            }
        }

        var n = __CLPK_integer(auCount)
        var nrhs = __CLPK_integer(rhsCount)
        var lda = n
        var ldb = n
        var info: __CLPK_integer = 0
        var ipiv = [__CLPK_integer](repeating: 0, count: auCount)

        W.withUnsafeMutableBufferPointer { wPtr in
            B.withUnsafeMutableBufferPointer { bPtr in
                ipiv.withUnsafeMutableBufferPointer { ipivPtr in
                    dgesv_(
                        &n,
                        &nrhs,
                        wPtr.baseAddress,
                        &lda,
                        ipivPtr.baseAddress,
                        bPtr.baseAddress,
                        &ldb,
                        &info
                    )
                }
            }
        }

        if info < 0 {
            throw FaceCalibrationError.solverFailed(reason: "dgesv_: zły argument \(-info).")
        }
        if info > 0 {
            throw FaceCalibrationError.solverFailed(reason: "Macierz W osobliwa (U[\(info),\(info)] = 0).")
        }

        // Post-processing — non-negative clamp (przybliżenie NNLS przez clipping).
        // Dla delta geometrii delta może być ujemna (np. cofnięcie warg) — nie clampujemy.
        // Kolumna B[:, v*3 + k] to dekorelowana wartość komponentu k wierzchołka v w przestrzeni AU.

        // Rekonstrukcja — dla każdej AU, dla każdego wierzchołka, składamy nowy delta.
        var result: [BlendshapeDelta] = []
        result.reserveCapacity(auCount)
        for auIdx in 0..<auCount {
            var newVerts = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: vertexCount)
            for v in 0..<vertexCount {
                let x = Float(B[auIdx + (v * 3 + 0) * auCount])
                let y = Float(B[auIdx + (v * 3 + 1) * auCount])
                let z = Float(B[auIdx + (v * 3 + 2) * auCount])
                newVerts[v] = SIMD3<Float>(x, y, z)
            }
            // Wagi obserwowane — ustawiamy diag=1 (po dekorelacji).
            var cleanWeights = [Float](repeating: 0, count: auCount)
            cleanWeights[auIdx] = 1.0
            result.append(BlendshapeDelta(
                auID: observedDeltas[auIdx].auID,
                verts: newVerts,
                observedWeights: cleanWeights
            ))
        }
        return result
    }
}

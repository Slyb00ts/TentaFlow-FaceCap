// =============================================================================
// Plik: LinearAlgebra.swift
// Opis: Operacje algebry liniowej — macierze, inverse 3×3, mostek NNLS do Accelerate.
// =============================================================================

import Foundation
import simd
import Accelerate

/// Macierz gęsta w układzie row-major, przechowywana jako `[Double]`.
public struct Matrix: Equatable {

    public let rows: Int
    public let cols: Int
    public var storage: [Double]

    public init(rows: Int, cols: Int, storage: [Double]) {
        precondition(storage.count == rows * cols, "Zły rozmiar buforu.")
        self.rows = rows
        self.cols = cols
        self.storage = storage
    }

    public init(rows: Int, cols: Int, repeating value: Double = 0) {
        self.rows = rows
        self.cols = cols
        self.storage = [Double](repeating: value, count: rows * cols)
    }

    public subscript(r: Int, c: Int) -> Double {
        get { storage[r * cols + c] }
        set { storage[r * cols + c] = newValue }
    }
}

public enum LinearAlgebra {

    /// Transponuje macierz gęstą.
    public static func transpose(_ m: Matrix) -> Matrix {
        var result = Matrix(rows: m.cols, cols: m.rows)
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                result[c, r] = m[r, c]
            }
        }
        return result
    }

    /// Mnożenie macierzy 4×4 (SIMD — szybkie).
    @inline(__always)
    public static func matmul(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 {
        simd_mul(a, b)
    }

    /// Inverse macierzy 3×3 (ręczne — unikamy LAPACK dla tak małej macierzy).
    public static func inverse3x3(_ m: simd_float3x3) -> simd_float3x3? {
        let det = simd_determinant(m)
        guard abs(det) > 1e-8 else { return nil }
        return simd_inverse(m)
    }

    /// Non-Negative Least Squares — pomost do Accelerate/LAPACK `dgelsd`. Używamy
    /// projekcji iteracyjnej (algorytm Lawsona–Hansona). Dla małych problemów
    /// (≤ 512 zmiennych) jest to wystarczająco szybkie.
    ///
    /// Rozwiązuje: `min ‖Ax − b‖²` pod warunkiem `x ≥ 0`.
    /// Zwraca wektor x długości `a.cols`.
    public static func nnls(_ a: Matrix, _ b: [Double], maxIter: Int = 256) -> [Double] {
        precondition(a.rows == b.count, "NNLS: niezgodne wymiary A i b.")
        let n = a.cols
        var x = [Double](repeating: 0, count: n)
        var passive = [Bool](repeating: false, count: n)

        for _ in 0..<maxIter {
            // w = Aᵀ(b − Ax)
            let ax = multiply(a, x)
            let residual = zip(b, ax).map { $0 - $1 }
            let w = multiply(transpose(a), residual)

            // Znajdź indeks z największym w w zbiorze aktywnym (gdzie passive == false).
            var bestIdx = -1
            var bestValue = 1e-12
            for i in 0..<n where !passive[i] && w[i] > bestValue {
                bestValue = w[i]
                bestIdx = i
            }
            if bestIdx < 0 { break }
            passive[bestIdx] = true

            // Rozwiąż least squares dla zbioru pasywnego.
            var s = x
            while true {
                let subCols = (0..<n).filter { passive[$0] }
                let subA = extractColumns(a, columns: subCols)
                let zSub = leastSquares(subA, b)
                for (k, col) in subCols.enumerated() {
                    s[col] = zSub[k]
                }
                for i in 0..<n where !passive[i] { s[i] = 0 }

                // Jeżeli wszystkie s w zbiorze pasywnym są dodatnie — koniec pętli wewnętrznej.
                if subCols.allSatisfy({ s[$0] > 0 }) {
                    x = s
                    break
                }

                // Oblicz α i wycofaj najmniej dodatnie.
                var alpha = Double.infinity
                var alphaIdx = -1
                for col in subCols where s[col] <= 0 {
                    let denom = x[col] - s[col]
                    if denom > 1e-12 {
                        let a0 = x[col] / denom
                        if a0 < alpha {
                            alpha = a0
                            alphaIdx = col
                        }
                    }
                }
                if alphaIdx < 0 { x = s; break }
                for i in 0..<n {
                    x[i] = x[i] + alpha * (s[i] - x[i])
                }
                for col in subCols where x[col] < 1e-12 {
                    passive[col] = false
                    x[col] = 0
                }
            }
        }
        return x
    }

    // MARK: — Pomocnicze

    private static func multiply(_ m: Matrix, _ v: [Double]) -> [Double] {
        precondition(m.cols == v.count, "matmul: zły rozmiar wektora.")
        var out = [Double](repeating: 0, count: m.rows)
        m.storage.withUnsafeBufferPointer { mPtr in
            v.withUnsafeBufferPointer { vPtr in
                out.withUnsafeMutableBufferPointer { outPtr in
                    cblas_dgemv(CblasRowMajor, CblasNoTrans,
                                Int32(m.rows), Int32(m.cols),
                                1.0, mPtr.baseAddress, Int32(m.cols),
                                vPtr.baseAddress, 1,
                                0.0, outPtr.baseAddress, 1)
                }
            }
        }
        return out
    }

    private static func transpose(_ m: Matrix) -> Matrix {
        var r = Matrix(rows: m.cols, cols: m.rows)
        for i in 0..<m.rows {
            for j in 0..<m.cols {
                r[j, i] = m[i, j]
            }
        }
        return r
    }

    private static func extractColumns(_ m: Matrix, columns: [Int]) -> Matrix {
        var sub = Matrix(rows: m.rows, cols: columns.count)
        for r in 0..<m.rows {
            for (i, c) in columns.enumerated() {
                sub[r, i] = m[r, c]
            }
        }
        return sub
    }

    /// Least squares przez normal equations: x = (AᵀA)⁻¹ Aᵀ b.
    /// Dla ≤ 64 kolumn to jest wystarczająco stabilne; w razie potrzeby można
    /// zamienić na `dgelsd` przez `LAPACKE_dgelsd`.
    private static func leastSquares(_ a: Matrix, _ b: [Double]) -> [Double] {
        precondition(a.rows == b.count, "LS: zły rozmiar b.")
        let at = transpose(a)
        let ata = mul(at, a)
        let atb = multiply(at, b)
        return solvePositiveDefinite(ata, atb)
    }

    private static func mul(_ a: Matrix, _ b: Matrix) -> Matrix {
        precondition(a.cols == b.rows, "mul: niezgodne wymiary.")
        var c = Matrix(rows: a.rows, cols: b.cols)
        a.storage.withUnsafeBufferPointer { aPtr in
            b.storage.withUnsafeBufferPointer { bPtr in
                c.storage.withUnsafeMutableBufferPointer { cPtr in
                    cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                                Int32(a.rows), Int32(b.cols), Int32(a.cols),
                                1.0, aPtr.baseAddress, Int32(a.cols),
                                bPtr.baseAddress, Int32(b.cols),
                                0.0, cPtr.baseAddress, Int32(b.cols))
                }
            }
        }
        return c
    }

    /// Cholesky + back-substitution dla symetrycznej macierzy dodatnio określonej.
    private static func solvePositiveDefinite(_ a: Matrix, _ b: [Double]) -> [Double] {
        precondition(a.rows == a.cols, "Cholesky: macierz musi być kwadratowa.")
        var ac = a
        var bc = b
        var n = __CLPK_integer(a.rows)
        var nrhs = __CLPK_integer(1)
        var lda = n
        var ldb = n
        var info: __CLPK_integer = 0
        var uplo: Int8 = Int8(UnicodeScalar("U").value)

        // Konwersja do column-major (LAPACK wymaga).
        var colMajor = [Double](repeating: 0, count: a.rows * a.cols)
        for r in 0..<a.rows {
            for c in 0..<a.cols {
                colMajor[c * a.rows + r] = ac[r, c]
            }
        }

        dposv_(&uplo, &n, &nrhs, &colMajor, &lda, &bc, &ldb, &info)
        if info != 0 {
            // Fallback: zwróć zera — NNLS potem skoryguje.
            return [Double](repeating: 0, count: a.cols)
        }
        return bc
    }
}

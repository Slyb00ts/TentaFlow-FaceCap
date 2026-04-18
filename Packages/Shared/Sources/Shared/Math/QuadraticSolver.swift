// =============================================================================
// Plik: QuadraticSolver.swift
// Opis: Numerycznie stabilny solver równania kwadratowego (rozwiązania rzeczywiste).
// =============================================================================

import Foundation

/// Rozwiązania równania kwadratowego.
public struct QuadraticRoots: Equatable, Sendable {
    public let first: Double
    public let second: Double

    public init(first: Double, second: Double) {
        self.first = first
        self.second = second
    }
}

/// Numerycznie stabilny solver równania `a·x² + b·x + c = 0`.
///
/// Używamy formuły Citardauq dla przypadku, gdy `b` jest znacznie większe od `4ac`:
/// - `x₁ = −2c / (b + sign(b)·√Δ)`,
/// - `x₂ = c / (a · x₁)`,
///
/// co unika utraty precyzji przy odejmowaniu dużych liczb.
/// Zwraca `nil`, gdy rozwiązań rzeczywistych nie ma lub `a == 0` (równanie liniowe).
public enum QuadraticSolver {

    public static func solve(a: Double, b: Double, c: Double) -> QuadraticRoots? {
        guard a != 0 else {
            // Liniowe: b·x + c = 0.
            guard b != 0 else { return nil }
            let x = -c / b
            return QuadraticRoots(first: x, second: x)
        }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let sqrtD = discriminant.squareRoot()
        let q: Double
        if b >= 0 {
            q = -0.5 * (b + sqrtD)
        } else {
            q = -0.5 * (b - sqrtD)
        }
        // Zabezpieczenie przed dzieleniem przez 0 — bardzo mało prawdopodobne, ale możliwe.
        let x1 = q != 0 ? q / a : 0
        let x2 = q != 0 ? c / q : 0
        return QuadraticRoots(first: x1, second: x2)
    }
}

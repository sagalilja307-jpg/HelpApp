//
//  TextEmbedding.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//

import Foundation

/// Dummy vectorizer — returns a simple hashed vector for demonstration purposes.
/// Replace this with real embedding logic (e.g. via LLM, ML model, etc.)
func vectorize(_ text: String) -> [Float] {
    let hash = abs(text.hashValue)
    let seed = UInt64(hash)
    var rng = SeededGenerator(seed: seed)

    // Return 128-dimensional "embedding"
    return (0..<128).map { _ in Float.random(in: -1...1, using: &rng) }
}

// MARK: - Helper: deterministic seeded RNG

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed != 0 ? seed : 0xdeadbeef
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}
extension Array where Element == Float {
    func toData() -> Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

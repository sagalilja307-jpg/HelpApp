//
//  ClusterTitleGenerator.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

final class ClusterTitleGenerator {

    private let llmClient: LLMClient

    init(llmClient: LLMClient = LLMClient()) {
        self.llmClient = llmClient
    }

    // MARK: - Public API

    /// Returns a human-friendly title for a cluster.
    /// Tries local heuristics first, then LLM fallback.
    func generateTitle(for cluster: Cluster) async -> String {
        if let localTitle = generateLocalTitle(for: cluster) {
            return localTitle
        }

        guard case .available = LLMAvailability.check() else {
            return "Untitled"
        }

        do {
            return try await generateLLMTitle(for: cluster)
        } catch {
            return "Untitled"
        }
    }

    // MARK: - Local heuristic

    private func generateLocalTitle(for cluster: Cluster) -> String? {
        let texts = cluster.items
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map { $0.rawText }

        guard !texts.isEmpty else { return nil }

        // Very simple heuristic:
        // If the same noun-ish word appears in multiple texts, use it
        let words = texts
            .joined(separator: " ")
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        let frequencies = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }

        if let (word, count) = frequencies.max(by: { $0.value < $1.value }),
           count >= 2,
           word.count > 3 {
            return word.capitalized
        }

        return nil
    }

    // MARK: - LLM fallback

    private func generateLLMTitle(for cluster: Cluster) async throws -> String {

        let samples = cluster.items
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(4)
            .map { "• \($0.rawText)" }
            .joined(separator: "\n")

        let prompt = """
        Give a short, human-friendly title (max 4 words)
        for this group of related information.

        Do NOT include dates unless absolutely necessary.
        Do NOT include the words "email", "note", "message", or "meeting".

        Texts:
        \(samples)
        """

        let response = try await llmClient.respond(to: prompt)

        return response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init) ?? "Untitled"
    }
}

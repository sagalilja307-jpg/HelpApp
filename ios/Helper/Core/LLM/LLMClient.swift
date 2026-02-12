//
//  LLMClient.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation
import FoundationModels

public final class LLMClient {

    public init() {}

    public func respond(to prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}

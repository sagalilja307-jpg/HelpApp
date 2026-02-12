//
//  ChatViewModel.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-30.
//

import Foundation
import Observation

@Observable
final class ChatViewModel {
    
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        let timestamp: Date = .now
    }

    // MARK: - UI-state

    var messages: [ChatMessage] = []
    var query: String = ""
    var extraContext: String = ""
    var isSending = false
    var error: String? = nil

    // MARK: - Pipeline

    private let pipeline: QueryPipeline

    init(pipeline: QueryPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Skicka prompt

    func send() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        
        isSending = true
        error = nil
        
        messages.append(.init(role: .user, text: trimmed))
        query = ""
        
        // 🧠 Lägg till kontext i prompt om den finns
        let fullPrompt: String
        if !extraContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullPrompt = """
            Du är en hjälpsam assistent. När relevant, använd den här extra kontexten mellan <context>…</context>.
            <context>
            \(extraContext)
            </context>
            
            Fråga:
            \(trimmed)
            """
        } else {
            fullPrompt = trimmed
        }
        
        do {
            let uq = UserQuery(
                text: fullPrompt,
                source: .userTyped
            )
            let result = try await pipeline.run(uq)
            let responseText = result.answer ?? "(Inget svar från modellen)"
            messages.append(.init(role: .assistant, text: responseText))
        } catch {
            self.error = error.localizedDescription
            messages.append(.init(role: .assistant, text: "Förlåt, något gick fel (\(error.localizedDescription))."))
        }

        isSending = false
    }
}

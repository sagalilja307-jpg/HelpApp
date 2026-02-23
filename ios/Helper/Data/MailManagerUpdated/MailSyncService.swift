import Foundation
import SwiftData

enum MailSyncError: LocalizedError {
    case failedToFetch
    case invalidHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .failedToFetch:
            return "Kunde inte hämta mejl från Gmail."
        case .invalidHTTPStatus(let statusCode):
            return "Gmail API svarade med status \(statusCode)."
        }
    }
}

struct GmailMessageSummary: Sendable, Equatable {
    let id: String
    let threadId: String
    let snippet: String
    let internalDate: Date
    let from: String
    let subject: String
    let isUnread: Bool
}

private struct GmailListResponse: Decodable {
    struct MessageRef: Decodable {
        let id: String
        let threadId: String?
    }

    let messages: [MessageRef]?
}

private struct GmailMessageResponse: Decodable {
    struct Payload: Decodable {
        struct Header: Decodable {
            let name: String
            let value: String
        }

        let headers: [Header]?
    }

    let id: String
    let threadId: String?
    let snippet: String?
    let internalDate: String?
    let labelIds: [String]?
    let payload: Payload?
}

private struct MailRawPayload: Codable {
    let kind: String
    let messageId: String
    let threadId: String
    let from: String
    let subject: String
    let snippet: String
    let internalDate: Date
    let isUnread: Bool
}

final class MailSyncService {
    static let shared = MailSyncService()

    private init() {}

    func fetchMessages(
        accessToken: String,
        gmailQuery: String?,
        maxResults: Int = 50
    ) async throws -> [GmailMessageSummary] {
        let refs = try await listMessageRefs(
            accessToken: accessToken,
            gmailQuery: gmailQuery,
            maxResults: maxResults
        )

        var result: [GmailMessageSummary] = []
        result.reserveCapacity(refs.count)

        for ref in refs {
            if let message = try await fetchMessage(
                accessToken: accessToken,
                messageId: ref.id,
                fallbackThreadId: ref.threadId
            ) {
                result.append(message)
            }
        }

        return result.sorted { $0.internalDate > $1.internalDate }
    }

    @MainActor
    func syncInbox(
        accessToken: String,
        gmailQuery: String?,
        maxResults: Int,
        memory: MemoryService,
        in context: ModelContext
    ) async throws -> [QueryResult.Entry] {
        let messages = try await fetchMessages(
            accessToken: accessToken,
            gmailQuery: gmailQuery,
            maxResults: maxResults
        )
        let contentObjects = makeContentObjects(from: messages)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for (message, content) in zip(messages, contentObjects) {
            let rawPayload = MailRawPayload(
                kind: "mail",
                messageId: message.id,
                threadId: message.threadId,
                from: message.from,
                subject: message.subject,
                snippet: message.snippet,
                internalDate: message.internalDate,
                isUnread: message.isUnread
            )
            let payloadData = try encoder.encode(rawPayload)
            let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
            let rawEventID = "mail:\(message.id)"

            try memory.putRawEvent(
                actor: .system,
                id: rawEventID,
                source: "mail",
                timestamp: message.internalDate,
                payloadJSON: payloadJSON,
                text: content.rawText,
                in: context
            )

            try memory.putEmbedding(
                actor: .system,
                embeddingId: rawEventID,
                sourceType: "mail",
                sourceId: message.id,
                vector: vectorize(content.rawText),
                in: context
            )
        }

        return messages.map { message in
            QueryResult.Entry(
                id: UUID(),
                source: .mail,
                title: message.subject.isEmpty ? "(Utan ämne)" : message.subject,
                body: message.snippet.isEmpty ? nil : message.snippet,
                date: message.internalDate
            )
        }
    }

    func syncGmail(
        accessToken: String,
        days: Int = 90,
        maxResults: Int = 50
    ) async throws {
        let memory = try MemoryService()
        let context = memory.context()
        _ = try await syncInbox(
            accessToken: accessToken,
            gmailQuery: "newer_than:\(max(1, days))d",
            maxResults: maxResults,
            memory: memory,
            in: context
        )
    }

    func makeContentObjects(from messages: [GmailMessageSummary]) -> [ContentObject] {
        messages.map { message in
            let rawText = [
                "Från: \(message.from)",
                "Ämne: \(message.subject.isEmpty ? "(Utan ämne)" : message.subject)",
                "Snippet: \(message.snippet)"
            ].joined(separator: "\n")

            return ContentObject(
                rawText: rawText,
                source: .mail,
                createdAt: message.internalDate,
                originalDateHint: message.internalDate,
                relatedEntityId: message.id
            )
        }
    }
}

private extension MailSyncService {
    func listMessageRefs(
        accessToken: String,
        gmailQuery: String?,
        maxResults: Int
    ) async throws -> [GmailListResponse.MessageRef] {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(max(1, min(maxResults, 100))))
        ]
        if let gmailQuery, !gmailQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: gmailQuery))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MailSyncError.failedToFetch
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MailSyncError.invalidHTTPStatus(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(GmailListResponse.self, from: data)
        return payload.messages ?? []
    }

    func fetchMessage(
        accessToken: String,
        messageId: String,
        fallbackThreadId: String?
    ) async throws -> GmailMessageSummary? {
        var components = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)"
        )
        components?.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject")
        ]

        guard let url = components?.url else {
            throw MailSyncError.failedToFetch
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MailSyncError.invalidHTTPStatus(httpResponse.statusCode)
        }

        let message = try JSONDecoder().decode(GmailMessageResponse.self, from: data)
        guard let internalDate = parseInternalDate(message.internalDate) else {
            return nil
        }

        let headers = Dictionary(
            uniqueKeysWithValues: (message.payload?.headers ?? []).map {
                ($0.name.lowercased(), $0.value)
            }
        )

        return GmailMessageSummary(
            id: message.id,
            threadId: message.threadId ?? fallbackThreadId ?? "",
            snippet: message.snippet ?? "",
            internalDate: internalDate,
            from: headers["from"] ?? "Okänd avsändare",
            subject: headers["subject"] ?? "(Utan ämne)",
            isUnread: (message.labelIds ?? []).contains("UNREAD")
        )
    }

    func parseInternalDate(_ value: String?) -> Date? {
        guard let value, let millis = Double(value) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000.0)
    }
}

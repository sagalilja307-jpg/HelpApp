import Foundation

struct SupportSettingsSnapshot: Codable, Equatable {
    var supportLevel: Int
    var paused: Bool
    var adaptationEnabled: Bool
    var dailyCaps: [String: Int]
    var timeCriticalWindowHours: Int
    var effectivePolicy: [String: AnyCodable]

    static let fallback = SupportSettingsSnapshot(
        supportLevel: 1,
        paused: false,
        adaptationEnabled: true,
        dailyCaps: ["0": 0, "1": 2, "2": 3, "3": 5],
        timeCriticalWindowHours: 24,
        effectivePolicy: [:]
    )
}

struct LearningPatternSnapshot: Codable, Identifiable, Equatable {
    let key: String
    let value: AnyCodable

    var id: String { key }
}

struct LearningEventSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let eventType: String
    let payload: [String: AnyCodable]
    let createdAt: String
}

struct LearningSettingsSnapshot: Codable, Equatable {
    var adaptationEnabled: Bool
    var patterns: [LearningPatternSnapshot]
    var events: [LearningEventSnapshot]

    static let empty = LearningSettingsSnapshot(
        adaptationEnabled: true,
        patterns: [],
        events: []
    )
}

struct LearningResetSnapshot: Codable, Equatable {
    let removedKeys: [String]
    let removedCount: Int
}

enum SupportSettingsCache {
    private static let supportKey = "helper.support.settings.cache.v1"
    private static let learningKey = "helper.support.learning.cache.v1"

    static func loadSupport() -> SupportSettingsSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: supportKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SupportSettingsSnapshot.self, from: data)
    }

    static func saveSupport(_ settings: SupportSettingsSnapshot) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: supportKey)
    }

    static func loadLearning() -> LearningSettingsSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: learningKey) else {
            return nil
        }
        return try? JSONDecoder().decode(LearningSettingsSnapshot.self, from: data)
    }

    static func saveLearning(_ learning: LearningSettingsSnapshot) {
        guard let data = try? JSONEncoder().encode(learning) else { return }
        UserDefaults.standard.set(data, forKey: learningKey)
    }
}

enum SupportSettingsServiceError: LocalizedError {
    case invalidBaseURL
    case badResponse(Int, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ogiltig backend-URL."
        case .badResponse(let statusCode, let message):
            return "Backend-fel (\(statusCode)): \(message)"
        case .decodingFailed:
            return "Kunde inte tolka backend-svar."
        }
    }
}

@MainActor
final class SupportSettingsAPIService {
    static let shared = SupportSettingsAPIService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func syncSupportSettingsCache() async {
        _ = try? await fetchSupportSettings()
        _ = try? await fetchLearningSettings()
    }

    func fetchSupportSettings() async throws -> SupportSettingsSnapshot {
        let data = try await request(path: "/settings/support", method: "GET", body: nil)
        let decoder = Self.makeDecoder()
        guard let decoded = try? decoder.decode(SupportSettingsSnapshot.self, from: data) else {
            throw SupportSettingsServiceError.decodingFailed
        }
        SupportSettingsCache.saveSupport(decoded)
        return decoded
    }

    func updateSupportSettings(
        supportLevel: Int? = nil,
        paused: Bool? = nil,
        adaptationEnabled: Bool? = nil
    ) async throws -> SupportSettingsSnapshot {
        let payload = SupportSettingsUpdatePayload(
            supportLevel: supportLevel,
            paused: paused,
            adaptationEnabled: adaptationEnabled
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let responseData = try await request(path: "/settings/support", method: "POST", body: data)
        let decoder = Self.makeDecoder()
        guard let decoded = try? decoder.decode(SupportSettingsSnapshot.self, from: responseData) else {
            throw SupportSettingsServiceError.decodingFailed
        }
        SupportSettingsCache.saveSupport(decoded)
        return decoded
    }

    func fetchLearningSettings() async throws -> LearningSettingsSnapshot {
        let data = try await request(path: "/settings/learning", method: "GET", body: nil)
        let decoder = Self.makeDecoder()
        guard let decoded = try? decoder.decode(LearningSettingsSnapshot.self, from: data) else {
            throw SupportSettingsServiceError.decodingFailed
        }
        SupportSettingsCache.saveLearning(decoded)
        return decoded
    }

    func setLearningPaused(_ paused: Bool) async throws -> LearningSettingsSnapshot {
        let payload = LearningPausePayload(paused: paused)
        let bodyData = try JSONEncoder().encode(payload)
        let data = try await request(path: "/settings/learning/pause", method: "POST", body: bodyData)
        let decoder = Self.makeDecoder()
        guard let decoded = try? decoder.decode(LearningSettingsSnapshot.self, from: data) else {
            throw SupportSettingsServiceError.decodingFailed
        }
        SupportSettingsCache.saveLearning(decoded)
        return decoded
    }

    func resetLearning() async throws -> LearningResetSnapshot {
        let data = try await request(path: "/settings/learning/reset", method: "POST", body: Data("{}".utf8))
        let decoder = Self.makeDecoder()
        guard let decoded = try? decoder.decode(LearningResetSnapshot.self, from: data) else {
            throw SupportSettingsServiceError.decodingFailed
        }
        let learning = try? await fetchLearningSettings()
        if let learning {
            SupportSettingsCache.saveLearning(learning)
        }
        return decoded
    }

    private func request(path: String, method: String, body: Data?) async throws -> Data {
        let baseURLs = Self.backendBaseURLs()
        guard !baseURLs.isEmpty else {
            throw SupportSettingsServiceError.invalidBaseURL
        }

        var lastConnectivityError: URLError?
        for baseURL in baseURLs {
            guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SupportSettingsServiceError.badResponse(-1, "No HTTP response")
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let message = Self.parseErrorMessage(from: data) ?? "Okänt fel"
                    throw SupportSettingsServiceError.badResponse(httpResponse.statusCode, message)
                }
                return data
            } catch let urlError as URLError where Self.shouldTryNextBaseURL(urlError) {
                lastConnectivityError = urlError
                continue
            }
        }

        if let lastConnectivityError {
            throw lastConnectivityError
        }
        throw SupportSettingsServiceError.badResponse(-1, "No HTTP response")
    }

    private static func backendBaseURLs() -> [URL] {
        AppIntegrationConfig.resolvedBackendBaseURLs()
    }

    private static func shouldTryNextBaseURL(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = object as? [String: Any],
            let errorDict = dict["error"] as? [String: Any],
            let message = errorDict["message"] as? String
        else {
            return nil
        }
        return message
    }
}

private struct SupportSettingsUpdatePayload: Codable {
    let supportLevel: Int?
    let paused: Bool?
    let adaptationEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case supportLevel = "support_level"
        case paused
        case adaptationEnabled = "adaptation_enabled"
    }
}

private struct LearningPausePayload: Codable {
    let paused: Bool
}

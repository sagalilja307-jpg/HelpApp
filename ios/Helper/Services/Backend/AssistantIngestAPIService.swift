import Foundation

protocol AssistantIngesting {
    func ingest(items: [UnifiedItemDTO]) async throws
}

enum AssistantIngestAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ogiltig backend-URL för ingest."
        case .invalidResponse:
            return "Ogiltigt svar från backend under ingest."
        case let .serverError(statusCode, message):
            return "Ingest misslyckades (\(statusCode)): \(message)"
        }
    }
}

final class AssistantIngestAPIService: AssistantIngesting {
    static let shared = AssistantIngestAPIService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func ingest(items: [UnifiedItemDTO]) async throws {
        guard !items.isEmpty else { return }
        let payload = IngestRequestDTO(items: items)
        let body = try Self.encoder.encode(payload)
        let data = try await performRequest(path: "/ingest", method: "POST", body: body)

        guard (try? JSONSerialization.jsonObject(with: data, options: [])) is [String: Any] else {
            throw AssistantIngestAPIError.invalidResponse
        }
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> Data {
        let baseURLs = Self.backendBaseURLs()
        guard !baseURLs.isEmpty else {
            throw AssistantIngestAPIError.invalidBaseURL
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
                    throw AssistantIngestAPIError.invalidResponse
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let message = Self.parseErrorMessage(from: data) ?? "Okänt fel"
                    throw AssistantIngestAPIError.serverError(httpResponse.statusCode, message)
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
        throw AssistantIngestAPIError.invalidResponse
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
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

    private static func parseErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = object as? [String: Any]
        else {
            return nil
        }

        if let detail = dict["detail"] as? String {
            return detail
        }
        if let errorDict = dict["error"] as? [String: Any],
           let message = errorDict["message"] as? String {
            return message
        }
        return nil
    }
}

import Foundation

enum MemoryProcessingAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case decodingFailed
    case encodingFailed
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ogiltig backend-URL för memory processing."
        case .invalidResponse:
            return "Ogiltigt svar från backend under memory processing."
        case .decodingFailed:
            return "Kunde inte tolka backend-svar från memory processing."
        case .encodingFailed:
            return "Kunde inte serialisera memory processing-request."
        case let .serverError(statusCode, message):
            switch statusCode {
            case 503:
                return "Tjänsten för minnessparning är tillfälligt otillgänglig (503)."
            case 429:
                return "För många förfrågningar just nu. Försök igen om en stund."
            case 500...599:
                return "Backendfel vid minnessparning (\(statusCode))."
            default:
                return "Memory processing misslyckades (\(statusCode)): \(message)"
            }
        }
    }
}

protocol MemoryProcessingAPI: AnyObject {
    func processMemory(text: String, language: String) async throws -> ProcessMemoryResponseDTO
}

struct ProcessMemoryRequestDTO: Codable, Sendable {
    let text: String
    let language: String
}

struct ProcessMemoryResponseDTO: Codable, Sendable, Equatable {
    let cleanText: String
    let suggestedType: String
    let tags: [String]
    let embedding: [Float]
}

final class MemoryProcessingAPIService: MemoryProcessingAPI {
    static let shared = MemoryProcessingAPIService()
    private static let lastWorkingBaseURLDefaultsKey = "helper.backend.base_url.last_working.memory"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func processMemory(text: String, language: String) async throws -> ProcessMemoryResponseDTO {
        let payload = ProcessMemoryRequestDTO(text: text, language: language)
        guard let body = try? Self.encoder.encode(payload) else {
            throw MemoryProcessingAPIError.encodingFailed
        }

        let data = try await performRequest(path: "/process-memory", method: "POST", body: body)
        guard !data.isEmpty else { throw MemoryProcessingAPIError.invalidResponse }

        guard let decoded = try? Self.decoder.decode(ProcessMemoryResponseDTO.self, from: data) else {
            throw MemoryProcessingAPIError.decodingFailed
        }

        return decoded
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> Data {
        let baseURLs = Self.backendBaseURLs()
        guard !baseURLs.isEmpty else {
            throw MemoryProcessingAPIError.invalidBaseURL
        }

        var lastConnectivityError: URLError?
        for baseURL in baseURLs {
            guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else { continue }

            var request = URLRequest(url: endpoint)
            request.httpMethod = method
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MemoryProcessingAPIError.invalidResponse
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let message = Self.parseErrorMessage(from: data) ?? "Okänt fel"
                    throw MemoryProcessingAPIError.serverError(httpResponse.statusCode, message)
                }

                Self.persistWorkingBaseURL(baseURL)
                return data
            } catch let urlError as URLError where Self.shouldTryNextBaseURL(urlError) {
                lastConnectivityError = urlError
                continue
            }
        }

        if let lastConnectivityError { throw lastConnectivityError }
        throw MemoryProcessingAPIError.invalidResponse
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func backendBaseURLs() -> [URL] {
        var urls = AppIntegrationConfig.resolvedBackendBaseURLs()
        guard
            let raw = UserDefaults.standard.string(forKey: lastWorkingBaseURLDefaultsKey),
            let preferred = URL(string: raw)
        else {
            return urls
        }

        guard let idx = urls.firstIndex(where: { $0.absoluteString.caseInsensitiveCompare(preferred.absoluteString) == .orderedSame }) else {
            return urls
        }

        let hit = urls.remove(at: idx)
        urls.insert(hit, at: 0)
        return urls
    }

    private static func persistWorkingBaseURL(_ baseURL: URL) {
        UserDefaults.standard.set(baseURL.absoluteString, forKey: lastWorkingBaseURLDefaultsKey)
    }

    private static func shouldTryNextBaseURL(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
             .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = object as? [String: Any]
        else { return nil }

        if let detail = dict["detail"] as? String { return detail }

        if let detailEntries = dict["detail"] as? [[String: Any]] {
            let messages = detailEntries.compactMap { $0["msg"] as? String }
            if !messages.isEmpty { return messages.joined(separator: ", ") }
        }

        if let errorDict = dict["error"] as? [String: Any],
           let message = errorDict["message"] as? String {
            return message
        }

        if let error = dict["error"] as? String { return error }
        if let message = dict["message"] as? String { return message }

        return nil
    }
}

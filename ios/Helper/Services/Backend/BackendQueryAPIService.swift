import Foundation

protocol BackendQuerying {
    func query(
        text: String,
        days: Int,
        sources: [String],
        dataFilter: [String: AnyCodable]?
    ) async throws -> BackendLLMResponseDTO
}

enum BackendQueryAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case decodingFailed
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ogiltig backend-URL för query."
        case .invalidResponse:
            return "Ogiltigt svar från backend under query."
        case .decodingFailed:
            return "Kunde inte tolka backend-svar från query."
        case let .serverError(statusCode, message):
            return "Query misslyckades (\(statusCode)): \(message)"
        }
    }
}

final class BackendQueryAPIService: BackendQuerying {
    static let shared = BackendQueryAPIService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func query(
        text: String,
        days: Int,
        sources: [String],
        dataFilter: [String: AnyCodable]? = nil
    ) async throws -> BackendLLMResponseDTO {
        let payload = BackendQueryRequestDTO(
            query: text,
            language: "sv",
            sources: sources,
            days: days,
            dataFilter: dataFilter
        )

        let body = try Self.encoder.encode(payload)
        let data = try await performRequest(path: "/query", method: "POST", body: body)

        guard !data.isEmpty else {
            throw BackendQueryAPIError.invalidResponse
        }

        guard let decoded = try? Self.decoder.decode(BackendLLMResponseDTO.self, from: data) else {
            throw BackendQueryAPIError.decodingFailed
        }

        return decoded
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> Data {
        guard
            let baseURL = Self.backendBaseURL(),
            let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL
        else {
            throw BackendQueryAPIError.invalidBaseURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendQueryAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.parseErrorMessage(from: data) ?? "Okänt fel"
            throw BackendQueryAPIError.serverError(httpResponse.statusCode, message)
        }

        return data
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

    private static func backendBaseURL() -> URL? {
        AppIntegrationConfig.resolvedBackendBaseURL()
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

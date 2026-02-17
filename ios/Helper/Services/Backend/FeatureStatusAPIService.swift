import Foundation

protocol FeatureStatusFetching {
    func fetchFeatureStatus() async throws -> BackendFeatureStatusDTO
}

enum FeatureStatusAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case decodingFailed
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ogiltig backend-URL för feature-status."
        case .invalidResponse:
            return "Ogiltigt svar från backend för feature-status."
        case .decodingFailed:
            return "Kunde inte tolka feature-status från backend."
        case let .serverError(statusCode, message):
            return "Feature-status misslyckades (\(statusCode)): \(message)"
        }
    }
}

final class FeatureStatusAPIService: FeatureStatusFetching {
    static let shared = FeatureStatusAPIService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchFeatureStatus() async throws -> BackendFeatureStatusDTO {
        let data = try await performRequest(path: "/assistant/feature-status", method: "GET")
        guard !data.isEmpty else {
            throw FeatureStatusAPIError.invalidResponse
        }
        guard let decoded = try? BackendQueryAPIService.decoder.decode(BackendFeatureStatusDTO.self, from: data) else {
            throw FeatureStatusAPIError.decodingFailed
        }
        return decoded
    }

    private func performRequest(path: String, method: String) async throws -> Data {
        guard
            let baseURL = AppIntegrationConfig.resolvedBackendBaseURL(),
            let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL
        else {
            throw FeatureStatusAPIError.invalidBaseURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeatureStatusAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.parseErrorMessage(from: data) ?? "Okänt fel"
            throw FeatureStatusAPIError.serverError(httpResponse.statusCode, message)
        }

        return data
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


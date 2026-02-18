import Foundation

protocol BackendQuerying {
    func query(
        text: String,
        days: Int,
        sources: [String],
        dataFilter: [String: AnyCodable]?
    ) async throws -> BackendDataIntentResponseDTO
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
    ) async throws -> BackendDataIntentResponseDTO {
        let payload = BackendQueryRequestDTO(
            query: text,
            question: text,
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

        guard let decoded = try? Self.decoder.decode(BackendDataIntentResponseDTO.self, from: data) else {
            throw BackendQueryAPIError.decodingFailed
        }

        return decoded
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> Data {
        let baseURLs = Self.backendBaseURLs()
        guard !baseURLs.isEmpty else {
            throw BackendQueryAPIError.invalidBaseURL
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
                    throw BackendQueryAPIError.invalidResponse
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let message = Self.parseErrorMessage(from: data) ?? "Okänt fel"
                    throw BackendQueryAPIError.serverError(httpResponse.statusCode, message)
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
        throw BackendQueryAPIError.invalidResponse
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = parseDate(rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawValue)"
            )
        }
        return decoder
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

        if let detailEntries = dict["detail"] as? [[String: Any]] {
            let messages = detailEntries.compactMap { $0["msg"] as? String }
            if !messages.isEmpty {
                return messages.joined(separator: ", ")
            }
        }

        if let errorDict = dict["error"] as? [String: Any],
           let message = errorDict["message"] as? String {
            return message
        }

        if let error = dict["error"] as? String {
            return error
        }

        if let message = dict["message"] as? String {
            return message
        }

        return nil
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        if let date = DateService.shared.parseISO8601(rawValue) {
            return date
        }

        for formatter in fallbackDateFormatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }

    private static let fallbackDateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ]

        return formats.map { format in
            DateService.shared.dateFormatter(
                dateFormat: format,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone(secondsFromGMT: 0)
            )
        }
    }()
}

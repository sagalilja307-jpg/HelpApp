import Foundation

final class HelperAPIClient {
    static let shared = HelperAPIClient()
    private init() {}

    private var accessToken: String?

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    func get(path: String, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        var lastConnectivityError: URLError?
        for baseURL in Self.backendBaseURLs() {
            var components = URLComponents(string: baseURL + path)!
            components.queryItems = queryItems

            guard let url = components.url else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
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
        throw URLError(.badServerResponse)
    }

    func post(path: String, body: Data? = nil) async throws -> Data {
        var lastConnectivityError: URLError?
        for baseURL in Self.backendBaseURLs() {
            guard let url = URL(string: baseURL + path) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
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
        throw URLError(.badServerResponse)
    }

    private static func backendBaseURLs() -> [String] {
        let urls = AppIntegrationConfig.resolvedBackendBaseURLs()
        if urls.isEmpty {
            return [AppIntegrationConfig.defaultBackendBaseURL]
        }
        return urls.map { $0.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
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
}

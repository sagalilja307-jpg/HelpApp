import Foundation

final class HelperAPIClient {
    static let shared = HelperAPIClient()
    private init() {}

    private var accessToken: String?

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    func get(path: String, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        var components = URLComponents(string: "http://localhost:8000" + path)!
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }
}

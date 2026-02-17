import Foundation

enum AppIntegrationConfig {
    static let appGroupIdentifier = "group.saga.com.Helper"
    static let sharedItemsKey = "shared_items_v1"

    static let oauthCallbackScheme = "helper-oauth"
    static let gmailRedirectURI = "helper-oauth://oauth/gmail/callback"

    static let backendBaseURLDefaultsKey = "helper.backend.base_url"

    #if targetEnvironment(simulator)
    static let defaultBackendBaseURL = "http://localhost:8000"
    #else
    // Physical devices cannot reach the Mac backend via localhost.
    static let defaultBackendBaseURL = "http://Mac-mini-som-tillhor-Saga.local:8000"
    #endif

    static func resolvedBackendBaseURL() -> URL? {
        if let launchOverride = launchArgumentBackendBaseURL(),
           let url = validatedURL(from: launchOverride) {
            return url
        }

        if let storedOverride = UserDefaults.standard.string(forKey: backendBaseURLDefaultsKey),
           let url = validatedURL(from: storedOverride) {
            return url
        }

        return validatedURL(from: defaultBackendBaseURL)
    }

    private static func launchArgumentBackendBaseURL() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let keyIndex = args.firstIndex(of: "-helper.backend.base_url") else {
            return nil
        }
        let valueIndex = args.index(after: keyIndex)
        guard valueIndex < args.endIndex else {
            return nil
        }
        return args[valueIndex]
    }

    private static func validatedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let scheme = url.scheme else {
            return nil
        }
        guard scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

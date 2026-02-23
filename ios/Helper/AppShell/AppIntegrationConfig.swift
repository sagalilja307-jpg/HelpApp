import Foundation

enum AppIntegrationConfig {
    static let appGroupIdentifier = "group.saga.com.Helper"
    static let sharedItemsKey = "shared_items_v1"

    static var oauthCallbackScheme: String {
        if let reversedClientID = infoPlistString(forKey: "GMAIL_IOS_REVERSED_CLIENT_ID") {
            return reversedClientID
        }
        if let clientID = infoPlistString(forKey: "GMAIL_IOS_CLIENT_ID"),
           let derived = derivedReversedClientID(from: clientID) {
            return derived
        }
        return "helper-oauth"
    }

    static var gmailRedirectURI: String {
        "\(oauthCallbackScheme):/oauth2redirect"
    }

    static let legacyBackendBaseURLDefaultsKey = "helper.backend.base_url"

    static var backendBaseURLDefaultsKey: String {
#if targetEnvironment(simulator)
        return "helper.backend.base_url.simulator"
#else
        return "helper.backend.base_url.device"
#endif
    }

    #if targetEnvironment(simulator)
    static let defaultBackendBaseURL = "http://localhost:8000"
    #else
    // Physical devices cannot reach localhost on the Mac process.
    static let defaultBackendBaseURL = "http://Mac-mini-som-tillhor-Saga.local:8000"
    #endif

    static func resolvedBackendBaseURL() -> URL? {
        resolvedBackendBaseURLs().first
    }

    static func resolvedBackendBaseURLs() -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func appendIfValid(_ raw: String?) {
            guard let raw, let url = validatedURL(from: raw) else { return }
            let key = url.absoluteString.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            candidates.append(url)
        }

        appendIfValid(launchArgumentBackendBaseURL())
        appendIfValid(UserDefaults.standard.string(forKey: backendBaseURLDefaultsKey))
        appendIfValid(UserDefaults.standard.string(forKey: legacyBackendBaseURLDefaultsKey))
        appendIfValid(defaultBackendBaseURL)

        return candidates
    }

    private static func launchArgumentBackendBaseURL() -> String? {
        let args = ProcessInfo.processInfo.arguments
        let keys = [backendBaseURLDefaultsKey, legacyBackendBaseURLDefaultsKey]
        for key in keys {
            let flag = "-\(key)"
            guard let keyIndex = args.firstIndex(of: flag) else {
                continue
            }
            let valueIndex = args.index(after: keyIndex)
            guard valueIndex < args.endIndex else {
                continue
            }
            return args[valueIndex]
        }
        return nil
    }

    private static func validatedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let scheme = url.scheme else {
            return nil
        }
        guard scheme == "http" || scheme == "https" else {
            return nil
        }
#if !targetEnvironment(simulator)
        if isLoopbackHost(url.host) {
            return nil
        }
#endif
        return url
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let normalizedHost = host?.lowercased() else { return false }
        if normalizedHost == "localhost" || normalizedHost == "::1" {
            return true
        }
        return normalizedHost.hasPrefix("127.")
    }

    private static func infoPlistString(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func derivedReversedClientID(from clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let base = String(clientID.dropLast(suffix.count))
        guard !base.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(base)"
    }
}

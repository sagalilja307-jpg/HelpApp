import Foundation

enum AppIntegrationConfig {
    nonisolated(unsafe) static let appGroupIdentifier = "group.saga.com.Helper"
    nonisolated(unsafe) static let sharedItemsKey = "shared_items_v1"

    nonisolated(unsafe) static let oauthCallbackScheme = "helper-oauth"
    nonisolated(unsafe) static let gmailRedirectURI = "helper-oauth://oauth/gmail/callback"

    nonisolated(unsafe) static let backendBaseURLDefaultsKey = "helper.backend.base_url"
    nonisolated(unsafe) static let defaultBackendBaseURL = "http://localhost:8000"
}

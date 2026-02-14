import Foundation

enum AppIntegrationConfig {
    static let appGroupIdentifier = "group.saga.com.Helper"
    static let sharedItemsKey = "shared_items_v1"

    static let oauthCallbackScheme = "helper-oauth"
    static let gmailRedirectURI = "helper-oauth://oauth/gmail/callback"

    static let backendBaseURLDefaultsKey = "helper.backend.base_url"
    static let defaultBackendBaseURL = "http://localhost:8000"
}

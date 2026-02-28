import AuthenticationServices
import Combine
import Foundation

@MainActor
final class AppleAccountStore: ObservableObject {
    struct Profile: Equatable {
        let userID: String
        let fullName: String
        let email: String
    }

    enum CredentialStatus: Equatable {
        case unknown
        case authorized
        case revoked
        case notFound
        case transferred
        case unavailable(String)

        var label: String {
            switch self {
            case .unknown:
                return "Okänd"
            case .authorized:
                return "Verifierad"
            case .revoked:
                return "Återkallad"
            case .notFound:
                return "Ingen inloggning"
            case .transferred:
                return "Överförd"
            case .unavailable:
                return "Kunde inte verifiera"
            }
        }
    }

    private enum Keys {
        static let userID = "helper.account.apple.user_id"
        static let fullName = "helper.account.apple.full_name"
        static let email = "helper.account.apple.email"
    }

    @Published private(set) var profile: Profile?
    @Published private(set) var credentialStatus: CredentialStatus = .unknown
    @Published var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let appleIDProvider = ASAuthorizationAppleIDProvider()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.profile = Self.loadProfile(from: defaults)
        if profile == nil {
            credentialStatus = .notFound
        }
    }

    var isSignedIn: Bool {
        profile != nil
    }

    var displayName: String {
        guard let profile else { return "Inte inloggad" }
        let trimmed = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Apple-användare" : trimmed
    }

    var emailAddress: String {
        profile?.email ?? ""
    }

    var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func refreshCredentialState() async {
        guard let userID = profile?.userID else {
            credentialStatus = .notFound
            return
        }

        await withCheckedContinuation { continuation in
            appleIDProvider.getCredentialState(forUserID: userID) { [weak self] state, error in
                DispatchQueue.main.async {
                    guard let self else {
                        continuation.resume()
                        return
                    }

                    if let error {
                        self.credentialStatus = .unavailable(error.localizedDescription)
                    } else {
                        self.credentialStatus = Self.mapCredentialState(state)
                    }

                    continuation.resume()
                }
            }
        }
    }

    func handleAuthorizationResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                lastErrorMessage = "Fel svar från Apple-inloggning."
                return
            }

            let fallbackName = defaults.string(forKey: Keys.fullName) ?? ""
            let fallbackEmail = defaults.string(forKey: Keys.email) ?? ""

            let givenName = credential.fullName?.givenName ?? ""
            let familyName = credential.fullName?.familyName ?? ""
            let joinedName = [givenName, familyName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            let profile = Profile(
                userID: credential.user,
                fullName: joinedName.isEmpty ? fallbackName : joinedName,
                email: (credential.email ?? fallbackEmail).trimmingCharacters(in: .whitespacesAndNewlines)
            )

            saveProfile(profile)
            self.profile = profile
            self.credentialStatus = .authorized
            self.lastErrorMessage = nil

        case .failure(let error):
            lastErrorMessage = error.localizedDescription
        }
    }

    func signOut() {
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.fullName)
        defaults.removeObject(forKey: Keys.email)

        profile = nil
        credentialStatus = .notFound
        lastErrorMessage = nil
    }

    private static func loadProfile(from defaults: UserDefaults) -> Profile? {
        guard let userID = defaults.string(forKey: Keys.userID), !userID.isEmpty else {
            return nil
        }

        let fullName = defaults.string(forKey: Keys.fullName) ?? ""
        let email = defaults.string(forKey: Keys.email) ?? ""

        return Profile(userID: userID, fullName: fullName, email: email)
    }

    private func saveProfile(_ profile: Profile) {
        defaults.set(profile.userID, forKey: Keys.userID)
        defaults.set(profile.fullName, forKey: Keys.fullName)
        defaults.set(profile.email, forKey: Keys.email)
    }

    private static func mapCredentialState(_ state: ASAuthorizationAppleIDProvider.CredentialState) -> CredentialStatus {
        switch state {
        case .authorized:
            return .authorized
        case .revoked:
            return .revoked
        case .notFound:
            return .notFound
        case .transferred:
            return .transferred
        @unknown default:
            return .unknown
        }
    }
}

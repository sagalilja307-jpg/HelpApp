import Foundation
import Combine

@MainActor
final class ConnectedMailStore: ObservableObject {
    static let shared = ConnectedMailStore()

    @Published private(set) var emails: [String] = []

    private let defaults: UserDefaults
    private let key = "helper.stage3.mail.connected_emails"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.emails = (defaults.stringArray(forKey: key) ?? [])
            .map(Self.normalizeEmail)
            .filter { !$0.isEmpty }
    }

    func addEmail(_ email: String) {
        let normalized = Self.normalizeEmail(email)
        guard !normalized.isEmpty else { return }
        guard !emails.contains(normalized) else { return }

        emails.append(normalized)
        persist()
    }

    private func persist() {
        defaults.set(emails, forKey: key)
    }

    private static func normalizeEmail(_ email: String) -> String {
        email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

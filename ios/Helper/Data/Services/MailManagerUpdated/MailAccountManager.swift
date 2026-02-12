import Foundation
import Combine

struct MailAccount: Codable, Identifiable {
    let id: UUID
    var email: String
    var provider: String
    var accessToken: String
    var refreshToken: String
}

enum MailAccountError: Error {
    case accountNotFound
    case failedToSave
}

final class MailAccountManager: ObservableObject {
    static let shared = MailAccountManager()

    @Published private(set) var accounts: [MailAccount] = []

    private let storageKey = "mailAccounts"
    private let userDefaults = UserDefaults.standard

    private init() {
        loadAccounts()
    }

    // MARK: - Load

    private func loadAccounts() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }

        do {
            let decoded = try JSONDecoder().decode([MailAccount].self, from: data)
            self.accounts = decoded
        } catch {
            print("Kunde inte ladda konton: \(error)")
        }
    }

    // MARK: - Save

    private func saveAccounts() throws {
        do {
            let data = try JSONEncoder().encode(accounts)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            throw MailAccountError.failedToSave
        }
    }

    // MARK: - Public Methods

    func addAccount(_ account: MailAccount) async throws {
        accounts.append(account)
        try await persist()
    }

    func removeAccount(id: UUID) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw MailAccountError.accountNotFound
        }
        accounts.remove(at: index)
        try await persist()
    }

    func updateAccount(_ updated: MailAccount) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == updated.id }) else {
            throw MailAccountError.accountNotFound
        }
        accounts[index] = updated
        try await persist()
    }

    func getAccount(id: UUID) -> MailAccount? {
        return accounts.first { $0.id == id }
    }

    // MARK: - Async Persist Helper

    private func persist() async throws {
        try await Task.sleep(nanoseconds: 100_000_000) // Simulerar async jobb
        try saveAccounts()
    }
}

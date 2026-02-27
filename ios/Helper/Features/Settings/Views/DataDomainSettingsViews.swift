import SwiftUI
import UIKit

struct DataDomainView: View {
    let domain: DataDomain

    @EnvironmentObject private var store: DataSettingsStore
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                domainToggleCard
                sourcesList
                statusSection
                footerPrinciple
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .navigationTitle(domain.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            DataDomainHelpSheet(domain: domain)
        }
    }

    private var domainEnabled: Bool {
        store.isDomainEnabled(domain.id)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(domain.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)

            Text(domain.description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var domainToggleCard: some View {
        let accent = domain.sensitiveAccent ? Color(red: 0.75, green: 0.72, blue: 0.95) : Color.primary.opacity(0.10)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(domain.domainToggleTitle)
                        .font(.system(size: 16, weight: .semibold))
                    if let subtitle = domain.domainToggleSubtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { domainEnabled },
                    set: { newValue in
                        store.setDomain(domain, enabled: newValue)
                    }
                ))
                .labelsHidden()
                .tint(domain.sensitiveAccent ? accent : .accentColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var sourcesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(domain.sources) { source in
                DataSourceRow(
                    domainEnabled: domainEnabled,
                    source: source
                )
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if store.hasDeniedEnabledSources(in: domain) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Systemåtkomst krävs")
                    .font(.system(size: 14, weight: .semibold))

                Text("En eller flera källor behöver tillåtas i systemet för att fungera.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Button {
                    openAppSettings()
                } label: {
                    Text("Öppna Inställningar")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private var footerPrinciple: some View {
        Text(domain.footerText)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct DataSourceRow: View {
    let domainEnabled: Bool
    let source: DataSource

    @EnvironmentObject private var store: DataSettingsStore
    @ObservedObject private var connectedMailStore = ConnectedMailStore.shared
    @State private var gmailOAuthService = GmailOAuthService()
    @State private var isMailAuthorizing = false
    @State private var mailError: String?

    private var isSupported: Bool {
        store.isSourceSupported(source.id)
    }

    private var isMailSource: Bool {
        source.id == .mail
    }

    private var connectedMailAddresses: [String] {
        connectedMailStore.emails
    }

    private var isToggleEnabled: Bool {
        domainEnabled && isSupported && !isMailAuthorizing
    }

    private var statusText: String {
        isSupported ? store.permissionState(for: source.id).label : "Oaktiverad"
    }

    private var sourceToggleBinding: Binding<Bool> {
        Binding(
            get: { store.isSourceEnabled(source.id) },
            set: { newValue in
                Task {
                    await handleToggleChanged(newValue)
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.system(size: 16, weight: .semibold))

                Text(source.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("Status: \(statusText)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.9))

                if isMailSource, store.isSourceEnabled(.mail), !connectedMailAddresses.isEmpty {
                    Text(connectedMailAddresses.joined(separator: ", "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }

                if isMailSource, isMailAuthorizing {
                    Text("Ansluter mejl…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let mailError, isMailSource {
                    Text(mailError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                if !isSupported {
                    Text("Inte tillgänglig i appen ännu.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: sourceToggleBinding)
                    .labelsHidden()
                    .disabled(!isToggleEnabled)
                    .opacity(isToggleEnabled ? 1.0 : 0.45)

                if isMailSource, store.isSourceEnabled(.mail), isSupported {
                    Button {
                        Task {
                            await addAdditionalMailAccount()
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isMailAuthorizing)
                    .accessibilityLabel("Lägg till mejlkonto")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func handleToggleChanged(_ enabled: Bool) async {
        mailError = nil

        guard isMailSource else {
            _ = await store.setSource(source.id, enabled: enabled)
            return
        }

        guard enabled else {
            _ = await store.setSource(.mail, enabled: false)
            return
        }

        isMailAuthorizing = true
        defer { isMailAuthorizing = false }

        do {
            let email = try await ensureMailAuthorization(forceReauthorize: !OAuthTokenManager.shared.hasStoredToken())
            let didEnable = await store.setSource(.mail, enabled: true)
            guard didEnable else {
                mailError = "Kunde inte aktivera mejl."
                return
            }
            if let email {
                connectedMailStore.addEmail(email)
            }
        } catch {
            _ = await store.setSource(.mail, enabled: false)
            mailError = "Kunde inte ansluta mejl: \(error.localizedDescription)"
        }
    }

    private func addAdditionalMailAccount() async {
        mailError = nil
        isMailAuthorizing = true
        defer { isMailAuthorizing = false }

        do {
            if let email = try await ensureMailAuthorization(forceReauthorize: true) {
                connectedMailStore.addEmail(email)
            }
            _ = await store.setSource(.mail, enabled: true)
        } catch {
            mailError = "Kunde inte lägga till mejlkonto: \(error.localizedDescription)"
        }
    }

    private func ensureMailAuthorization(forceReauthorize: Bool) async throws -> String? {
        let accessToken: String

        if forceReauthorize || !OAuthTokenManager.shared.hasStoredToken() {
            let result = try await gmailOAuthService.startAuthorization()
            accessToken = result.accessToken
        } else {
            accessToken = try await validAccessToken()
        }

        return try? await gmailOAuthService.fetchPrimaryEmail(accessToken: accessToken)
    }

    private func validAccessToken() async throws -> String {
        let token = try OAuthTokenManager.shared.loadStoredToken()
        guard token.isExpired else {
            return token.accessToken
        }

        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw GmailOAuthServiceError.missingRefreshToken
        }

        let refreshed = try await gmailOAuthService.refreshAuthorization(refreshToken: refreshToken)
        return refreshed.accessToken
    }

    private var icon: some View {
        let name: String = {
            switch source.id {
            case .calendar:
                return "calendar"
            case .reminders:
                return "checklist"
            case .notifications:
                return "bell"
            case .contacts:
                return "person.2"
            case .mail:
                return "envelope"
            case .files:
                return "folder"
            case .photos:
                return "photo"
            case .camera:
                return "camera"
            case .location:
                return "location"
            case .healthActivity:
                return "figure.walk"
            case .sleep:
                return "bed.double"
            case .mentalHealth:
                return "brain"
            case .vitals:
                return "waveform.path.ecg"
            }
        }()

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: 34, height: 34)
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            )
    }
}

private struct DataDomainHelpSheet: View {
    let domain: DataDomain

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(domain.title)
                        .font(.system(size: 22, weight: .bold))

                    Text("Du kan slå på eller av källor när du vill. Helper använder källor för att ge överblick och sammanhang.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Principer")
                            .font(.system(size: 14, weight: .semibold))

                        Text("• Domän av → alla källor pausas\n• Källa på utan åtkomst → systemet ber om tillåtelse\n• Nekad åtkomst → neutral status + länk till Inställningar")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .padding(18)
            }
            .navigationTitle("Hjälp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }
}

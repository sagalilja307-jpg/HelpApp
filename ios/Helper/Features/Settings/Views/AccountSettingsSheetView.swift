import AuthenticationServices
import SwiftUI

struct AccountSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var accountStore: AppleAccountStore

    private let iCloudSyncCoordinator: ICloudKeyValueSyncCoordinator
    private let memorySyncCoordinator: ICloudMemorySyncCoordinator

    @State private var syncEnabled: Bool
    @State private var autoSyncEnabled: Bool
    @State private var isSyncingNow = false
    @State private var showSignOutConfirmation = false
    @State private var syncStatusMessage: String?

    init(
        accountStore: AppleAccountStore,
        iCloudSyncCoordinator: ICloudKeyValueSyncCoordinator,
        memorySyncCoordinator: ICloudMemorySyncCoordinator
    ) {
        self.accountStore = accountStore
        self.iCloudSyncCoordinator = iCloudSyncCoordinator
        self.memorySyncCoordinator = memorySyncCoordinator
        _syncEnabled = State(initialValue: iCloudSyncCoordinator.isSyncEnabled)
        _autoSyncEnabled = State(initialValue: memorySyncCoordinator.isAutoSyncEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                syncSection

                Section("Om") {
                    Text("Logga in med Apple för att koppla appen till ditt konto. iCloud-synk delar appens helper-inställningar mellan dina enheter.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Konto & synk")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await accountStore.refreshCredentialState()
        }
        .onChange(of: syncEnabled) { _, newValue in
            iCloudSyncCoordinator.setSyncEnabled(newValue)
            guard newValue else {
                memorySyncCoordinator.stopAutoSync()
                return
            }
            if autoSyncEnabled {
                memorySyncCoordinator.startAutoSync()
            }
            Task {
                isSyncingNow = true
                let outcome = await memorySyncCoordinator.syncNow()
                syncStatusMessage = outcome.message
                isSyncingNow = false
            }
        }
        .onChange(of: autoSyncEnabled) { _, newValue in
            memorySyncCoordinator.setAutoSyncEnabled(newValue)
        }
        .alert(
            "Inloggningsfel",
            isPresented: Binding(
                get: { accountStore.lastErrorMessage != nil },
                set: { show in
                    if !show {
                        accountStore.lastErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                accountStore.lastErrorMessage = nil
            }
        } message: {
            Text(accountStore.lastErrorMessage ?? "")
        }
        .alert("Logga ut från appen?", isPresented: $showSignOutConfirmation) {
            Button("Avbryt", role: .cancel) {}
            Button("Logga ut", role: .destructive) {
                accountStore.signOut()
            }
        } message: {
            Text("Det här tar bort kontokopplingen lokalt i appen.")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Apple-konto") {
            if accountStore.isSignedIn {
                LabeledContent("Namn") {
                    Text(accountStore.displayName)
                }

                if !accountStore.emailAddress.isEmpty {
                    LabeledContent("E-post") {
                        Text(accountStore.emailAddress)
                    }
                }

                LabeledContent("Status") {
                    Text(accountStore.credentialStatus.label)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Text("Logga ut")
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    accountStore.handleAuthorizationResult(result)
                    Task {
                        await accountStore.refreshCredentialState()
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

                Text("Inte inloggad")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncSection: some View {
        Section("iCloud") {
            Toggle("Synka appdata via iCloud", isOn: $syncEnabled)
            Toggle("Autosynk minnen", isOn: $autoSyncEnabled)
                .disabled(!syncEnabled)

            HStack(spacing: 10) {
                Image(systemName: accountStore.hasICloudAccount ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(accountStore.hasICloudAccount ? Color.green : Color.secondary)
                Text(accountStore.hasICloudAccount ? "iCloud-konto hittat på enheten" : "Ingen iCloud-inloggning hittad på enheten")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Autosynk hämtar och laddar upp minnen automatiskt ungefär var 5:e minut.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    isSyncingNow = true
                    iCloudSyncCoordinator.syncNow()
                    let outcome = await memorySyncCoordinator.syncNow()
                    syncStatusMessage = outcome.message
                    isSyncingNow = false
                }
            } label: {
                if isSyncingNow {
                    ProgressView()
                } else {
                    Label("Synka nu", systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
            .disabled(!syncEnabled)

            if let syncStatusMessage {
                Text(syncStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

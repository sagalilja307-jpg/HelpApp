import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct DataSourcesSheetView: View {
    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationSnapshotService: LocationSnapshotService?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var calendarStatus: AppPermissionStatus = .notDetermined
    @State private var remindersStatus: AppPermissionStatus = .notDetermined
    @State private var notificationStatus: AppPermissionStatus = .notDetermined
    @State private var calendarEnabled = false
    @State private var remindersEnabled = false
    @State private var notificationsEnabled = false
    @State private var contactsEnabled: Bool
    @State private var photosEnabled: Bool
    @State private var filesEnabled: Bool
    @State private var locationEnabled: Bool
    @State private var mailEnabled: Bool
    @State private var mailConnected: Bool
    @State private var isMailWorking = false
    @State private var photosOCREnabled: Bool
    @State private var filesOCREnabled: Bool
    @State private var hasImportedFiles: Bool
    @State private var isWorking = false
    @State private var showFileImporter = false
    @State private var message: String?
    @State private var lastLocationUpdate: Date?

    init(
        sourceConnectionStore: SourceConnectionStore,
        photosIndexService: PhotosIndexService,
        filesImportService: FilesImportService,
        locationSnapshotService: LocationSnapshotService? = nil
    ) {
        self.sourceConnectionStore = sourceConnectionStore
        self.photosIndexService = photosIndexService
        self.filesImportService = filesImportService
        self.locationSnapshotService = locationSnapshotService

        _contactsEnabled = State(initialValue: sourceConnectionStore.isEnabled(.contacts))
        _photosEnabled = State(initialValue: sourceConnectionStore.isEnabled(.photos))
        _filesEnabled = State(initialValue: sourceConnectionStore.isEnabled(.files))
        _locationEnabled = State(initialValue: sourceConnectionStore.isEnabled(.location))
        _mailEnabled = State(initialValue: sourceConnectionStore.isEnabled(.mail))
        _mailConnected = State(initialValue: OAuthTokenManager.shared.hasStoredToken())
        _photosOCREnabled = State(initialValue: sourceConnectionStore.isOCREnabled(for: .photos))
        _filesOCREnabled = State(initialValue: sourceConnectionStore.isOCREnabled(for: .files))
        _hasImportedFiles = State(initialValue: sourceConnectionStore.hasImportedFiles())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Systembehörigheter")
                        .font(.headline)
                        .padding(.bottom, 2)

                    SourceCardView(
                        icon: "calendar",
                        title: "Kalender",
                        subtitle: "Läs kalenderhändelser för bättre svar om din dag.",
                        isOn: $calendarEnabled,
                        statusBadgeText: permissionBadgeText(for: calendarStatus),
                        onToggle: { enabled in
                            Task { await toggleCalendar(enabled) }
                        }
                    ) {
                        if calendarStatus == .denied {
                            Button("Öppna Inställningar") {
                                openSettings()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            EmptyView()
                        }
                    }

                    SourceCardView(
                        icon: "checklist",
                        title: "Påminnelser",
                        subtitle: "Läs aktiva påminnelser för uppgifter och listor.",
                        isOn: $remindersEnabled,
                        statusBadgeText: permissionBadgeText(for: remindersStatus),
                        onToggle: { enabled in
                            Task { await toggleReminders(enabled) }
                        }
                    ) {
                        if remindersStatus == .denied {
                            Button("Öppna Inställningar") {
                                openSettings()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            EmptyView()
                        }
                    }

                    SourceCardView(
                        icon: "bell.fill",
                        title: "Notiser",
                        subtitle: "Tillåt notiser för uppföljningar och viktiga påminnelser.",
                        isOn: $notificationsEnabled,
                        statusBadgeText: permissionBadgeText(for: notificationStatus),
                        onToggle: { enabled in
                            Task { await toggleNotifications(enabled) }
                        }
                    ) {
                        if notificationStatus == .denied {
                            Button("Öppna Inställningar") {
                                openSettings()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            EmptyView()
                        }
                    }

                    Text("Datakällor")
                        .font(.headline)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                    SourceCardView(
                        icon: "envelope.fill",
                        title: "Mejl",
                        subtitle: "Koppla Gmail för mejlsvar i chatten.",
                        isOn: $mailEnabled,
                        statusBadgeText: mailConnected ? "Ansluten" : "Ej ansluten",
                        onToggle: { enabled in
                            Task { await toggleMail(enabled) }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !mailConnected {
                                Button("Logga in") {
                                    Task { await connectMail() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!mailEnabled || isMailWorking)
                            } else {
                                Button("Synka nu") {
                                    Task { await syncMailNow() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!mailEnabled || isMailWorking)
                            }

                            if isMailWorking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    SourceCardView(
                        icon: "person.2.fill",
                        title: "Kontakter",
                        subtitle: "Indexerar namn, organisation och kontaktvägar.",
                        isOn: $contactsEnabled,
                        onToggle: { enabled in
                            Task { await toggleContacts(enabled) }
                        }
                    ) {
                        EmptyView()
                    }

                    SourceCardView(
                        icon: "photo.on.rectangle.angled",
                        title: "Bilder",
                        subtitle: "Inkrementell indexering med valbar OCR.",
                        isOn: $photosEnabled,
                        isToggleEnabled: false,
                        statusBadgeText: "Always enabled",
                        onToggle: { enabled in
                            Task { await togglePhotos(enabled) }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            SourceSecondaryToggleView(
                                title: "OCR for bilder",
                                isOn: $photosOCREnabled,
                                onToggle: { enabled in
                                    photosOCREnabled = enabled
                                    sourceConnectionStore.setOCREnabled(enabled, for: .photos)
                                }
                            )

                            HStack(spacing: 10) {
                                Button("Skanna nya") {
                                    Task { await runPhotoIndex(fullScan: false) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!photosEnabled || isWorking || isMailWorking)

                                Button("Fullscan") {
                                    Task { await runPhotoIndex(fullScan: true) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!photosEnabled || isWorking || isMailWorking)
                            }
                        }
                    }

                    SourceCardView(
                        icon: "folder.fill",
                        title: "Filer",
                        subtitle: "Import via Files och textindexering per dokument.",
                        isOn: $filesEnabled,
                        onToggle: { enabled in
                            toggleFiles(enabled)
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            SourceSecondaryToggleView(
                                title: "OCR for filer",
                                isOn: $filesOCREnabled,
                                onToggle: { enabled in
                                    filesOCREnabled = enabled
                                    sourceConnectionStore.setOCREnabled(enabled, for: .files)
                                }
                            )

                            Button("Importera filer") {
                                showFileImporter = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(!filesEnabled || isWorking || isMailWorking)

                            if !hasImportedFiles {
                                Text("Ingen fil-data importerad an.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SourceCardView(
                        icon: "location.fill",
                        title: "Plats",
                        subtitle: "Ungefärlig plats för platsfrågor som \"nära mig\".",
                        isOn: $locationEnabled,
                        onToggle: { enabled in
                            Task { await toggleLocation(enabled) }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Uppdatera plats nu") {
                                Task { await refreshLocation() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!locationEnabled || isWorking || isMailWorking)

                            if let lastUpdate = lastLocationUpdate {
                                Text("Senast uppdaterad: \(Self.formatRelativeDate(lastUpdate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Platsdata är alltid ungefärlig och sparas endast i 7 dagar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Datakallor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                Task { await handleFileImportResult(result) }
            }
            .task {
                await refreshImportedFilesState()
                await refreshPermissionStatuses()
                refreshSourceToggles()
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                Task {
                    await refreshPermissionStatuses()
                    await refreshImportedFilesState()
                    refreshSourceToggles()
                }
            }
        }
    }
}

@MainActor
private extension DataSourcesSheetView {

    // MARK: - Contacts

    func toggleContacts(_ enabled: Bool) async {
        guard enabled else {
            sourceConnectionStore.setEnabled(false, for: .contacts)
            contactsEnabled = false
            return
        }

        do {
            _ = try await PermissionManager.shared.requestAccess(for: .contacts)
            let status = await PermissionManager.shared.status(for: .contacts)

            guard status == .granted else {
                contactsEnabled = false
                sourceConnectionStore.setEnabled(false, for: .contacts)
                message = "Kontakter kunde inte aktiveras: behörighet saknas."
                return
            }

            sourceConnectionStore.setEnabled(true, for: .contacts)
            contactsEnabled = true

        } catch {
            contactsEnabled = false
            sourceConnectionStore.setEnabled(false, for: .contacts)
            message = "Kontakter kunde inte aktiveras: \(error.localizedDescription)"
        }
    }

    // MARK: - Photos

    func togglePhotos(_ enabled: Bool) async {
        guard enabled else {
            sourceConnectionStore.setEnabled(true, for: .photos)
            photosEnabled = true
            message = "Bilder är alltid aktiverad."
            return
        }

        do {
            _ = try await PermissionManager.shared.requestAccess(for: .photos)
            let status = await PermissionManager.shared.status(for: .photos)

            guard status == .granted else {
                photosEnabled = false
                sourceConnectionStore.setEnabled(false, for: .photos)
                message = "Bilder kunde inte aktiveras: behörighet saknas."
                return
            }

            sourceConnectionStore.setEnabled(true, for: .photos)
            photosEnabled = true

        } catch {
            photosEnabled = false
            sourceConnectionStore.setEnabled(false, for: .photos)
            message = "Bilder kunde inte aktiveras: \(error.localizedDescription)"
        }
    }

    // MARK: - Files

    func toggleFiles(_ enabled: Bool) {
        sourceConnectionStore.setEnabled(enabled, for: .files)
        filesEnabled = enabled

        if enabled && !hasImportedFiles {
            message = "Importera minst en fil för att aktivera filsvar i chatten."
        }
    }

    func runPhotoIndex(fullScan: Bool) async {
        guard photosEnabled else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let count: Int

            if fullScan {
                count = try await photosIndexService.fullScan(in: modelContext)
            } else {
                count = try await photosIndexService.indexIncremental(in: modelContext)
            }

            message = "Bildindexering klar: \(count) objekt uppdaterade."

        } catch {
            message = "Bildindexering misslyckades: \(error.localizedDescription)"
        }
    }

    func handleFileImportResult(_ result: Result<[URL], Error>) async {
        switch result {

        case .failure(let error):
            message = "Filimport misslyckades: \(error.localizedDescription)"

        case .success(let urls):
            guard !urls.isEmpty else { return }

            isWorking = true
            defer { isWorking = false }

            do {
                let count = try await filesImportService.importDocuments(
                    urls: urls,
                    in: modelContext
                )

                hasImportedFiles = hasImportedFiles || count > 0
                sourceConnectionStore.setHasImportedFiles(hasImportedFiles)

                message = "Filimport klar: \(count) dokument uppdaterade."

            } catch {
                message = "Filimport misslyckades: \(error.localizedDescription)"
            }
        }
    }

    func refreshImportedFilesState() async {
        do {
            let imported = try filesImportService.hasImportedDocuments(in: modelContext)
            hasImportedFiles = imported || sourceConnectionStore.hasImportedFiles()
            sourceConnectionStore.setHasImportedFiles(hasImportedFiles)

        } catch {
            hasImportedFiles = sourceConnectionStore.hasImportedFiles()
        }
    }

    // MARK: - Location

    func toggleLocation(_ enabled: Bool) async {
        guard enabled else {
            sourceConnectionStore.setEnabled(false, for: .location)
            locationEnabled = false
            return
        }

        do {
            _ = try await PermissionManager.shared.requestAccess(for: .location)
            let status = await PermissionManager.shared.status(for: .location)

            guard status == .granted else {
                locationEnabled = false
                sourceConnectionStore.setEnabled(false, for: .location)
                message = "Plats kunde inte aktiveras: behörighet saknas."
                return
            }

            sourceConnectionStore.setEnabled(true, for: .location)
            locationEnabled = true

            message = "Plats aktiverad. Tryck \"Uppdatera plats nu\" för att indexera din position."

        } catch {
            locationEnabled = false
            sourceConnectionStore.setEnabled(false, for: .location)
            message = "Plats kunde inte aktiveras: \(error.localizedDescription)"
        }
    }

    func refreshLocation() async {
        guard locationEnabled,
              let service = locationSnapshotService else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await service.captureSnapshot(in: modelContext)

            lastLocationUpdate = result.snapshot.observedAt

            if result.fallbackUsed {
                message = "Plats uppdaterad (använder tidigare uppmätt position)."
            } else {
                message = "Plats uppdaterad: \(result.snapshot.placeLabel)"
            }

        } catch {
            message = "Platsuppdatering misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - Date Helper

    static func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = DateService.shared.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: DateService.shared.now())
    }

    func refreshPermissionStatuses() async {
        let calendar = await PermissionManager.shared.status(for: .calendar)
        let reminders = await PermissionManager.shared.status(for: .reminder)
        let notifications = await PermissionManager.shared.status(for: .notification)

        calendarStatus = calendar
        remindersStatus = reminders
        notificationStatus = notifications

        calendarEnabled = calendar == .granted
        remindersEnabled = reminders == .granted
        notificationsEnabled = notifications == .granted
    }

    func refreshSourceToggles() {
        contactsEnabled = sourceConnectionStore.isEnabled(.contacts)
        photosEnabled = sourceConnectionStore.isEnabled(.photos)
        filesEnabled = sourceConnectionStore.isEnabled(.files)
        locationEnabled = sourceConnectionStore.isEnabled(.location)
        mailEnabled = sourceConnectionStore.isEnabled(.mail)
        mailConnected = OAuthTokenManager.shared.hasStoredToken()
    }

    // MARK: - System Permissions

    func toggleCalendar(_ enabled: Bool) async {
        guard enabled else {
            calendarEnabled = calendarStatus == .granted
            message = "Kalenderbehörighet återkallas i iOS Inställningar."
            return
        }
        await requestCalendarAccessFromSheet()
    }

    func toggleReminders(_ enabled: Bool) async {
        guard enabled else {
            remindersEnabled = remindersStatus == .granted
            message = "Påminnelsebehörighet återkallas i iOS Inställningar."
            return
        }
        await requestReminderAccessFromSheet()
    }

    func toggleNotifications(_ enabled: Bool) async {
        guard enabled else {
            notificationsEnabled = notificationStatus == .granted
            message = "Notisbehörighet återkallas i iOS Inställningar."
            return
        }
        await requestNotificationAccessFromSheet()
    }

    func requestCalendarAccessFromSheet() async {
        do {
            _ = try await PermissionManager.shared.requestAccess(for: .calendar)
            calendarStatus = await PermissionManager.shared.status(for: .calendar)
            calendarEnabled = calendarStatus == .granted
            if !calendarEnabled {
                message = "Kalender kunde inte aktiveras: behörighet saknas."
            }
        } catch {
            calendarEnabled = false
            calendarStatus = .denied
            message = "Kalender kunde inte aktiveras: \(error.localizedDescription)"
        }
    }

    func requestReminderAccessFromSheet() async {
        do {
            _ = try await PermissionManager.shared.requestAccess(for: .reminder)
            remindersStatus = await PermissionManager.shared.status(for: .reminder)
            remindersEnabled = remindersStatus == .granted
            if !remindersEnabled {
                message = "Påminnelser kunde inte aktiveras: behörighet saknas."
            }
        } catch {
            remindersEnabled = false
            remindersStatus = .denied
            message = "Påminnelser kunde inte aktiveras: \(error.localizedDescription)"
        }
    }

    func requestNotificationAccessFromSheet() async {
        do {
            _ = try await PermissionManager.shared.requestAccess(for: .notification)
            notificationStatus = await PermissionManager.shared.status(for: .notification)
            notificationsEnabled = notificationStatus == .granted
            if !notificationsEnabled {
                message = "Notiser kunde inte aktiveras: behörighet saknas."
            }
        } catch {
            notificationsEnabled = false
            notificationStatus = .denied
            message = "Notiser kunde inte aktiveras: \(error.localizedDescription)"
        }
    }

    // MARK: - Mail

    func toggleMail(_ enabled: Bool) async {
        sourceConnectionStore.setEnabled(enabled, for: .mail)
        mailEnabled = sourceConnectionStore.isEnabled(.mail)

        guard enabled else {
            message = "Mejl är avstängd som datakälla."
            return
        }

        if !mailConnected {
            message = "Mejl aktiverad. Logga in på Gmail för att börja synka."
        }
    }

    func connectMail() async {
        guard mailEnabled else {
            message = "Aktivera mejl först."
            return
        }
        if mailConnected {
            message = "Gmail är redan ansluten."
            return
        }

        isMailWorking = true
        defer { isMailWorking = false }

        do {
            _ = try await GmailOAuthService().startAuthorization()
            mailConnected = OAuthTokenManager.shared.hasStoredToken()
            message = mailConnected ? "Gmail anslöts." : "Gmail kunde inte bekräftas."
        } catch {
            mailConnected = false
            message = "Kunde inte ansluta Gmail: \(error.localizedDescription)"
        }
    }

    func syncMailNow() async {
        guard mailEnabled else {
            message = "Aktivera mejl först."
            return
        }

        if !mailConnected {
            await connectMail()
            guard mailConnected else { return }
        }

        isMailWorking = true
        defer { isMailWorking = false }

        do {
            try await GmailSyncCoordinator().syncInbox()
            message = "Gmail synkades."
        } catch {
            message = "Gmail-synk misslyckades: \(error.localizedDescription)"
        }
    }

    func permissionBadgeText(for status: AppPermissionStatus) -> String {
        switch status {
        case .granted:
            return "Tillåten"
        case .denied:
            return "Nekad"
        case .notDetermined:
            return "Ej vald"
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataSourcesSheetView: View {
    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationSnapshotService: LocationSnapshotService?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var contactsEnabled: Bool
    @State private var photosEnabled: Bool
    @State private var filesEnabled: Bool
    @State private var locationEnabled: Bool
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
        _photosOCREnabled = State(initialValue: sourceConnectionStore.isOCREnabled(for: .photos))
        _filesOCREnabled = State(initialValue: sourceConnectionStore.isOCREnabled(for: .files))
        _hasImportedFiles = State(initialValue: sourceConnectionStore.hasImportedFiles())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                                .disabled(!photosEnabled || isWorking)

                                Button("Fullscan") {
                                    Task { await runPhotoIndex(fullScan: true) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!photosEnabled || isWorking)
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
                            .disabled(!filesEnabled || isWorking)

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
                            .disabled(!locationEnabled || isWorking)

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
            try await PermissionManager.shared.requestAccess(for: .contacts)
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
            sourceConnectionStore.setEnabled(false, for: .photos)
            photosEnabled = false
            return
        }

        do {
            try await PermissionManager.shared.requestAccess(for: .photos)
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
            try await PermissionManager.shared.requestAccess(for: .location)
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
}

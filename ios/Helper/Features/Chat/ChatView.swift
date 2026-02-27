//
//  ChatView.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-24.
//

import SwiftData
import SwiftUI
import CoreLocation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum MessageSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case queued
    case failed(String)
}

public struct ChatView: View {
    @State private var vm: ChatViewModel
    @AppStorage("helper.chat.autosave.enabled") private var autoSaveEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusInput: Bool
    @State private var showImportOptions = false
    @State private var showSupportSettings = false
    @State private var showCreateNote = false
    @State private var showDataSources = false
    @State private var supportSettingsViewModel = SupportSettingsViewModel()
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var showFileImporter = false
    @State private var showCameraCapture = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var importStatusMessage: String?
    @State private var saveStatuses: [UUID: MessageSaveStatus] = [:]

    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationSnapshotService: LocationSnapshotService?
    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    init(
        pipeline: QueryPipeline,
        sourceConnectionStore: SourceConnectionStore,
        photosIndexService: PhotosIndexService,
        filesImportService: FilesImportService,
        locationSnapshotService: LocationSnapshotService? = nil,
        longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator
    ) {
        _vm = State(initialValue: ChatViewModel(pipeline: pipeline))
        self.sourceConnectionStore = sourceConnectionStore
        self.photosIndexService = photosIndexService
        self.filesImportService = filesImportService
        self.locationSnapshotService = locationSnapshotService
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
    }

    public var body: some View {
        @Bindable var bindableVM = vm
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { msg in
                            bubble(for: msg)
                                .id(msg.id)
                        }
                        if vm.isSending {
                            ProgressView().padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: vm.messages.count) { oldValue, newValue in
                    if let last = vm.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    guard autoSaveEnabled, newValue > oldValue else { return }
                    let appended = Array(vm.messages.suffix(newValue - oldValue))
                    Task {
                        await autoSaveMessagesIfNeeded(appended)
                    }
                }
            }

            if showImportOptions {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Importera filer, bilder, kamera och andra datakällor")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Filer", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 20,
                            matching: .images
                        ) {
                            Label("Bilder", systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            Task {
                                await startCameraCaptureFlow()
                            }
                        } label: {
                            Label("Kamera", systemImage: "camera.badge.ellipsis")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            showDataSources = true
                        } label: {
                            Label("Datakällor", systemImage: "externaldrive.connected.to.line.below")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let importStatusMessage {
                        Text(importStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding([.horizontal, .top])
            }

            HStack {
                Button {
                    autoSaveEnabled.toggle()
                    guard autoSaveEnabled else { return }
                    let unsavedMessages = vm.messages.filter { saveStatus(for: $0.id) == .idle }
                    guard !unsavedMessages.isEmpty else { return }
                    Task {
                        await autoSaveMessagesIfNeeded(unsavedMessages)
                    }
                } label: {
                    Label(
                        autoSaveEnabled ? "Auto-spara: På" : "Auto-spara: Av",
                        systemImage: autoSaveEnabled ? "bookmark.fill" : "bookmark"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Button {
                    showImportOptions.toggle()
                } label: {
                    Image(systemName: showImportOptions ? "externaldrive.connected.to.line.below.fill" : "square.and.arrow.down.on.square")
                }
                .accessibilityLabel("Visa eller dölj import av filer, bilder, kamera och datakällor")

                TextField("Skriv en fråga…", text: $bindableVM.query, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusInput)
                    .lineLimit(1...4)
                    .onSubmit {
                        Task { await vm.send() }
                    }

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isSending ? "hourglass" : "paperplane.fill")
                }
                .disabled(vm.isSending || vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Fråga hjälparen")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                NavigationLink {
                    ShortTermMemoryView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Öppna korttidsminne")

                NavigationLink {
                    LongTermMemoryClustersView(
                        longTermMemorySaveCoordinator: longTermMemorySaveCoordinator
                    )
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityLabel("Öppna långtidsminneskluster")

                Button {
                    showDataSources = true
                } label: {
                    Image(systemName: "externaldrive.connected.to.line.below")
                }
                .accessibilityLabel("Datakällor")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateNote = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Skapa anteckning")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSupportSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Öppna stödinställningar")
            }
        }
        .sheet(isPresented: $showSupportSettings) {
            SupportSettingsSheetView(viewModel: supportSettingsViewModel)
        }
        .sheet(isPresented: $showDataSources) {
            DataSourcesSheetView(
                sourceConnectionStore: sourceConnectionStore,
                photosIndexService: photosIndexService,
                filesImportService: filesImportService,
                locationSnapshotService: locationSnapshotService
            )
        }
        .sheet(isPresented: $showCreateNote) {
            NavigationStack {
                Form {
                    Section("Titel") {
                        TextField("Anteckningstitel", text: $noteTitle)
                    }
                    Section("Innehåll") {
                        TextEditor(text: $noteBody)
                            .frame(minHeight: 140)
                    }
                }
                .navigationTitle("Ny anteckning")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") {
                            noteTitle = ""
                            noteBody = ""
                            showCreateNote = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Spara") {
                            createNote()
                        }
                        .disabled(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await importSelectedFiles(urls)
                }
            case .failure(let error):
                vm.error = "Kunde inte välja filer: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showCameraCapture) {
            CameraCaptureSheet { image in
                Task {
                    await importCameraImage(image)
                }
            }
            .ignoresSafeArea()
        }
        .alert("Fel", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .task {
            await longTermMemorySaveCoordinator.processPendingJobs()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await longTermMemorySaveCoordinator.processPendingJobs()
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importSelectedPhotos(newItems)
            }
        }
    }

    // MARK: - Bubblor

    @ViewBuilder private func bubble(for msg: ChatViewModel.ChatMessage) -> some View {
        let isUser = (msg.role == .user)
        let status = saveStatus(for: msg.id)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if !isUser, let component = msg.visualizationComponent {
                visualizationView(for: component, message: msg)
            }

            HStack {
                if isUser { Spacer() }
                Text(msg.text)
                    .padding(12)
                    .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
                if !isUser { Spacer() }
            }

            if !isUser {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await saveMessage(msg)
                        }
                    } label: {
                        Label(saveButtonTitle(for: status), systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(status == .saving)

                    if let text = saveStatusDetail(for: status) {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(saveStatusColor(for: status))
                            .lineLimit(1)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    if !autoSaveEnabled {
                        Button {
                            Task {
                                await saveMessage(msg)
                            }
                        } label: {
                            Label(saveButtonTitle(for: status), systemImage: "bookmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(status == .saving)
                    }

                    if let text = saveStatusDetail(for: status) {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(saveStatusColor(for: status))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func visualizationView(for component: VisualizationComponent) -> some View {
        visualizationView(for: component, message: nil)
    }

    @ViewBuilder
    private func visualizationView(
        for component: VisualizationComponent,
        message: ChatViewModel.ChatMessage?
    ) -> some View {
        switch component {
        case .summaryCards:
            SummaryCardsView(items: summaryCardData(for: message))

        case .narrative:
            NarrativeView(
                title: message?.intentPlan?.domain == .mail ? "Mejl" : "Sammanfattning",
                text: message?.text ?? "Ingen data tillgänglig."
            )

        case .focus:
            FocusView(
                title: focusTitle(for: message),
                value: focusValue(for: message),
                accent: .accentColor
            )

        case .timeline:
            TimelineView(items: timelineItems(for: message))

        case .weekScroll:
            WeekScrollView(days: weekDays(for: message))

        case .groupedList:
            GroupedListView(items: groupedItems(for: message))

        case .map:
            SimpleMapView(coordinate: mapCoordinate(for: message))

        case .flow:
            FlowView(steps: flowSteps(for: message))

        case .heatmap:
            HeatmapView(values: heatmapValues(for: message))
        }
    }

    private func summaryCardData(for message: ChatViewModel.ChatMessage?) -> [SummaryCardData] {
        let entries = message?.entries ?? []
        let latest = latestEntry(from: entries)
        var cards: [SummaryCardData] = [
            SummaryCardData(
                title: "Träffar",
                value: "\(entries.count)",
                caption: entries.isEmpty ? "Ingen data" : "Synkade poster",
                icon: "number.circle"
            )
        ]

        if let range = message?.timeRange {
            cards.append(
                SummaryCardData(
                    title: "Period",
                    value: formattedRange(range),
                    caption: "Avgränsning",
                    icon: "calendar"
                )
            )
        }

        if let status = message?.filters["status"]?.value as? String {
            cards.append(
                SummaryCardData(
                    title: "Filter",
                    value: status.capitalized,
                    caption: "Aktivt filter",
                    icon: "line.3.horizontal.decrease.circle"
                )
            )
        }

        if let latest {
            cards.append(
                SummaryCardData(
                    title: "Senaste",
                    value: latest.title,
                    caption: formatDate(latest.date),
                    icon: "clock"
                )
            )
        }

        return Array(cards.prefix(4))
    }

    private func focusTitle(for message: ChatViewModel.ChatMessage?) -> String {
        guard let entry = latestEntry(from: message?.entries ?? []) else {
            return "Inga resultat"
        }
        return entry.title
    }

    private func focusValue(for message: ChatViewModel.ChatMessage?) -> String {
        guard let entry = latestEntry(from: message?.entries ?? []) else {
            return "0 träffar"
        }
        return formatDate(entry.date)
    }

    private func timelineItems(for message: ChatViewModel.ChatMessage?) -> [TimelineItem] {
        let entries = sortedEntries(message?.entries ?? [])
        guard !entries.isEmpty else {
            return [TimelineItem(title: message?.text ?? "Inga resultat", date: "Nu", subtitle: nil, source: nil)]
        }

        return entries.prefix(10).map { entry in
            TimelineItem(
                title: entry.title,
                date: formatDate(entry.date),
                subtitle: clippedText(entry.body, maxLength: 90),
                source: localizedSourceName(entry.source)
            )
        }
    }

    private func weekDays(for message: ChatViewModel.ChatMessage?) -> [String] {
        let entries = sortedEntries(message?.entries ?? [])
        var days: [String] = []
        var seen: Set<String> = []

        for entry in entries {
            guard let date = entry.date else { continue }
            let value = DateService.shared.dateFormatter(dateFormat: "EEE d MMM").string(from: date)
            if seen.insert(value).inserted {
                days.append(value)
            }
        }

        if days.isEmpty, let range = message?.timeRange {
            var cursor = Calendar.current.startOfDay(for: range.start)
            let end = Calendar.current.startOfDay(for: range.end)
            while cursor <= end && days.count < 14 {
                days.append(DateService.shared.dateFormatter(dateFormat: "EEE d MMM").string(from: cursor))
                cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? cursor
                if cursor == end { break }
            }
        }

        return days.isEmpty ? ["Ingen data"] : days
    }

    private func groupedItems(for message: ChatViewModel.ChatMessage?) -> [GroupedItem] {
        let entries = sortedEntries(message?.entries ?? [])
        guard !entries.isEmpty else {
            return [GroupedItem(title: message?.text ?? "Inga resultat", group: "Resultat", subtitle: nil)]
        }

        return entries.map { entry in
            GroupedItem(
                title: entry.title,
                group: localizedSourceName(entry.source),
                subtitle: groupedItemSubtitle(for: entry)
            )
        }
    }

    private func mapCoordinate(for message: ChatViewModel.ChatMessage?) -> CLLocationCoordinate2D {
        guard
            let coordinateEntry = (message?.entries ?? []).first(where: { $0.latitude != nil && $0.longitude != nil }),
            let latitude = coordinateEntry.latitude,
            let longitude = coordinateEntry.longitude
        else {
            return .init(latitude: 59.3293, longitude: 18.0686)
        }
        return .init(latitude: latitude, longitude: longitude)
    }

    private func flowSteps(for message: ChatViewModel.ChatMessage?) -> [FlowItem] {
        let entries = sortedEntries(message?.entries ?? [])
        if entries.isEmpty {
            return [FlowItem(title: "Inga steg", detail: nil)]
        }
        return entries.prefix(4).map { entry in
            FlowItem(
                title: entry.title,
                detail: flowItemDetail(for: entry)
            )
        }
    }

    private func heatmapValues(for message: ChatViewModel.ChatMessage?) -> [[Double]] {
        let entries = sortedEntries(message?.entries ?? [])
        var grid = Array(repeating: Array(repeating: 0.0, count: 4), count: 7)

        for entry in entries {
            guard let date = entry.date else { continue }
            let weekday = max(1, min(7, Calendar.current.component(.weekday, from: date)))
            let hour = Calendar.current.component(.hour, from: date)
            let bucket = max(0, min(3, hour / 6))
            grid[weekday - 1][bucket] += 1
        }

        let maxValue = grid.flatMap(\.self).max() ?? 0
        if maxValue <= 0 {
            return [
                [0.05, 0.05, 0.05, 0.05],
                [0.05, 0.05, 0.05, 0.05],
                [0.05, 0.05, 0.05, 0.05],
                [0.05, 0.05, 0.05, 0.05],
                [0.05, 0.05, 0.05, 0.05],
                [0.05, 0.05, 0.05, 0.05],
                [0.05, 0.05, 0.05, 0.05]
            ]
        }

        return grid.map { row in
            row.map { value in value / maxValue }
        }
    }

    private func sortedEntries(_ entries: [QueryResult.Entry]) -> [QueryResult.Entry] {
        entries.sorted { lhs, rhs in
            let left = lhs.date ?? .distantPast
            let right = rhs.date ?? .distantPast
            return left > right
        }
    }

    private func latestEntry(from entries: [QueryResult.Entry]) -> QueryResult.Entry? {
        sortedEntries(entries).first
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "Okänd tid" }
        return DateService.shared.dateFormatter(dateStyle: .short, timeStyle: .short).string(from: date)
    }

    private func formattedRange(_ range: DateInterval) -> String {
        let formatter = DateService.shared.dateFormatter(dateStyle: .short, timeStyle: .short)
        return "\(formatter.string(from: range.start))–\(formatter.string(from: range.end))"
    }

    private func localizedSourceName(_ source: QuerySource) -> String {
        switch source {
        case .calendar:
            return "Kalender"
        case .reminders:
            return "Påminnelser"
        case .contacts:
            return "Kontakter"
        case .photos:
            return "Bilder"
        case .files:
            return "Filer"
        case .location:
            return "Plats"
        case .mail:
            return "Mejl"
        case .memory:
            return "Minne"
        case .rawEvents:
            return "Råhändelser"
        }
    }

    private func groupedItemSubtitle(for entry: QueryResult.Entry) -> String? {
        let datePart = entry.date.map(formatDate) ?? ""
        let textPart = clippedText(entry.body, maxLength: 70) ?? ""

        if !datePart.isEmpty && !textPart.isEmpty {
            return "\(datePart) · \(textPart)"
        }
        if !datePart.isEmpty {
            return datePart
        }
        return textPart.isEmpty ? nil : textPart
    }

    private func flowItemDetail(for entry: QueryResult.Entry) -> String? {
        if let body = clippedText(entry.body, maxLength: 60), !body.isEmpty {
            return body
        }
        return entry.date.map(formatDate)
    }

    private func clippedText(_ text: String?, maxLength: Int) -> String? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let flattened = raw.replacingOccurrences(of: "\n", with: " ")
        guard flattened.count > maxLength else { return flattened }
        let endIndex = flattened.index(flattened.startIndex, offsetBy: maxLength)
        return String(flattened[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func importSelectedFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        do {
            let importedCount = try await filesImportService.importDocuments(
                urls: urls,
                in: modelContext
            )
            sourceConnectionStore.setEnabled(true, for: .files)
            sourceConnectionStore.setHasImportedFiles(true)
            importStatusMessage = importedCount > 0
                ? "Importerade \(importedCount) fil\(importedCount == 1 ? "" : "er")."
                : "Filerna finns redan importerade."
        } catch {
            vm.error = "Kunde inte importera filer: \(error.localizedDescription)"
        }
    }

    private func startCameraCaptureFlow() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            vm.error = "Kameran är inte tillgänglig på den här enheten."
            return
        }

        let hasCameraAccess = await ensureCameraAccess()
        guard hasCameraAccess else {
            vm.error = "Kameraåtkomst nekades. Tillåt kamera i Inställningar."
            return
        }

        showCameraCapture = true
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        guard !items.isEmpty else { return }

        var photosImportedCount = 0
        var filesImportedCount = 0

        let hasPhotosAccess = await ensurePhotosAccess()
        if hasPhotosAccess {
            let localIdentifiers = items.compactMap(\.itemIdentifier)
            if !localIdentifiers.isEmpty {
                do {
                    photosImportedCount = try await photosIndexService.indexAssets(
                        localIdentifiers: localIdentifiers,
                        in: modelContext
                    )
                    sourceConnectionStore.setEnabled(true, for: .photos)
                } catch {
                    vm.error = "Kunde inte importera bilder: \(error.localizedDescription)"
                    return
                }
            }
        }

        let fallbackItems = hasPhotosAccess
            ? items.filter { $0.itemIdentifier == nil }
            : items

        if !fallbackItems.isEmpty {
            do {
                var tempURLs: [URL] = []
                tempURLs.reserveCapacity(fallbackItems.count)

                for item in fallbackItems {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        continue
                    }
                    let preferredType = item.supportedContentTypes.first
                    let fileURL = try writeTemporaryImageFile(
                        data: data,
                        preferredType: preferredType
                    )
                    tempURLs.append(fileURL)
                }

                if !tempURLs.isEmpty {
                    filesImportedCount = try await filesImportService.importDocuments(
                        urls: tempURLs,
                        in: modelContext
                    )
                    sourceConnectionStore.setEnabled(true, for: .files)
                    sourceConnectionStore.setHasImportedFiles(true)
                }
            } catch {
                vm.error = "Kunde inte läsa valda bilder: \(error.localizedDescription)"
                return
            }
        }

        let totalImported = photosImportedCount + filesImportedCount
        importStatusMessage = totalImported > 0
            ? "Importerade \(totalImported) bild\(totalImported == 1 ? "" : "er")."
            : "Bilderna finns redan importerade."
    }

    private func importCameraImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            vm.error = "Kunde inte läsa kamerabilden."
            return
        }

        do {
            let url = try writeTemporaryImageFile(data: data, preferredType: .jpeg)
            let importedCount = try await filesImportService.importDocuments(
                urls: [url],
                in: modelContext
            )
            sourceConnectionStore.setEnabled(true, for: .files)
            sourceConnectionStore.setHasImportedFiles(true)
            importStatusMessage = importedCount > 0
                ? "Kamerabild importerad."
                : "Kamerabilden fanns redan importerad."
        } catch {
            vm.error = "Kunde inte importera kamerabilden: \(error.localizedDescription)"
        }
    }

    private func ensurePhotosAccess() async -> Bool {
        do {
            var status = await PermissionManager.shared.status(for: .photos)
            if status == .notDetermined {
                status = try await PermissionManager.shared.requestAccess(for: .photos)
            }
            return status == .granted
        } catch {
            return false
        }
    }

    private func ensureCameraAccess() async -> Bool {
        do {
            var status = await PermissionManager.shared.status(for: .camera)
            if status == .notDetermined {
                status = try await PermissionManager.shared.requestAccess(for: .camera)
            }
            return status == .granted
        } catch {
            return false
        }
    }

    private func writeTemporaryImageFile(
        data: Data,
        preferredType: UTType?
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("helper-chat-imports", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileExtension = preferredType?.preferredFilenameExtension ?? "jpg"
        let filename = "image-\(UUID().uuidString).\(fileExtension)"
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func saveStatus(for messageID: UUID) -> MessageSaveStatus {
        saveStatuses[messageID] ?? .idle
    }

    private func saveButtonTitle(for status: MessageSaveStatus) -> String {
        switch status {
        case .idle:
            return "Spara"
        case .saving:
            return "Sparar..."
        case .saved:
            return "Sparad"
        case .queued:
            return "Köad"
        case .failed:
            return "Spara igen"
        }
    }

    private func saveStatusDetail(for status: MessageSaveStatus) -> String? {
        switch status {
        case .idle:
            return nil
        case .saving:
            return "Bearbetar..."
        case .saved:
            return "Sparad lokalt"
        case .queued:
            return "Köad – försöker igen automatiskt"
        case .failed(let error):
            return error
        }
    }

    private func saveStatusColor(for status: MessageSaveStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .queued:
            return .orange
        case .saved:
            return .green
        default:
            return .secondary
        }
    }

    private func autoSaveMessagesIfNeeded(_ messages: [ChatViewModel.ChatMessage]) async {
        guard autoSaveEnabled else { return }
        for message in messages {
            guard saveStatus(for: message.id) == .idle else { continue }
            await saveMessage(message)
        }
    }

    private func saveMessage(_ message: ChatViewModel.ChatMessage) async {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveStatuses[message.id] = .failed("Tom text kan inte sparas.")
            return
        }

        saveStatuses[message.id] = .saving
        let language = Locale.current.language.languageCode?.identifier ?? "sv"
        let result = await longTermMemorySaveCoordinator.save(
            text: trimmed,
            language: language
        )

        switch result {
        case .saved:
            saveStatuses[message.id] = .saved
        case .queued:
            saveStatuses[message.id] = .queued
        case .failed(let error):
            saveStatuses[message.id] = .failed(error)
        }
    }

    private func createNote() {
        let service = NotesStoreService()
        do {
            _ = try service.createNote(
                title: noteTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                body: noteBody.trimmingCharacters(in: .whitespacesAndNewlines),
                in: modelContext
            )
        } catch {
            vm.error = "Kunde inte spara anteckning: \(error.localizedDescription)"
            return
        }
        noteTitle = ""
        noteBody = ""
        showCreateNote = false
    }
}

private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureSheet

        init(parent: CameraCaptureSheet) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }
    }
}

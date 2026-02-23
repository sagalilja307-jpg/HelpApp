//
//  ChatView.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-24.
//

import SwiftData
import SwiftUI
import CoreLocation

public struct ChatView: View {
    @Bindable var vm: ChatViewModel
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusInput: Bool
    @State private var showContext = false
    @State private var showSupportSettings = false
    @State private var showCreateNote = false
    @State private var showDataSources = false
    @State private var supportSettingsViewModel = SupportSettingsViewModel()
    @State private var gmailOAuthService = GmailOAuthService()
    @State private var gmailConnected = false
    @State private var syncStatusMessage: String?
    @State private var noteTitle = ""
    @State private var noteBody = ""

    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationSnapshotService: LocationSnapshotService?

    init(
        pipeline: QueryPipeline,
        sourceConnectionStore: SourceConnectionStore,
        photosIndexService: PhotosIndexService,
        filesImportService: FilesImportService,
        locationSnapshotService: LocationSnapshotService? = nil
    ) {
        self.vm = ChatViewModel(pipeline: pipeline)
        self.sourceConnectionStore = sourceConnectionStore
        self.photosIndexService = photosIndexService
        self.filesImportService = filesImportService
        self.locationSnapshotService = locationSnapshotService
    }

    public var body: some View {
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
                }
            }

            if showContext {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lägg till kontext (valfritt)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $vm.extraContext)
                        .frame(minHeight: 80, maxHeight: 160)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
                .padding([.horizontal, .top])
            }

            if !gmailConnected {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "envelope.badge.person.crop")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gmail är inte anslutet")
                            .font(.subheadline.weight(.semibold))
                        Text("Logga in för att aktivera mejlsvar i chatten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button("Logga in") {
                        Task { await handleGmailLogin() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                Button {
                    showContext.toggle()
                } label: {
                    Image(systemName: showContext ? "doc.text.magnifyingglass" : "doc.badge.plus")
                }
                .accessibilityLabel("Visa eller dölj kontextruta")

                TextField("Skriv en fråga…", text: $vm.query, axis: .vertical)
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDataSources = true
                } label: {
                    Image(systemName: "externaldrive.connected.to.line.below")
                }
                .accessibilityLabel("Datakallor")
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
        .alert("Fel", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .alert(
            "Gmail",
            isPresented: Binding(
                get: { syncStatusMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        syncStatusMessage = nil
                    }
                }
            )
        ) {
            Button("OK") { syncStatusMessage = nil }
        } message: {
            Text(syncStatusMessage ?? "")
        }
        .task {
            await refreshGmailConnectionState()
        }
    }

    // MARK: - Bubblor

    @ViewBuilder private func bubble(for msg: ChatViewModel.ChatMessage) -> some View {
        let isUser = (msg.role == .user)
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
        var cards: [SummaryCardData] = [
            SummaryCardData(title: "Träffar", value: "\(entries.count)")
        ]

        if let range = message?.timeRange {
            cards.append(SummaryCardData(title: "Period", value: formattedRange(range)))
        }

        if let status = message?.filters["status"]?.value as? String {
            cards.append(SummaryCardData(title: "Filter", value: status))
        }

        if let firstTitle = entries.first?.title, !firstTitle.isEmpty {
            cards.append(SummaryCardData(title: "Första", value: firstTitle))
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
            return [TimelineItem(title: message?.text ?? "Inga resultat", date: "Nu")]
        }

        return entries.prefix(10).map { entry in
            TimelineItem(title: entry.title, date: formatDate(entry.date))
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
            return [GroupedItem(title: message?.text ?? "Inga resultat", group: "Resultat")]
        }

        return entries.map { entry in
            GroupedItem(title: entry.title, group: localizedSourceName(entry.source))
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
            return [FlowItem(title: "Inga steg")]
        }
        return entries.prefix(4).map { FlowItem(title: $0.title) }
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

    private func handleGmailLogin() async {
        if OAuthTokenManager.shared.hasStoredToken() {
            gmailConnected = true
            syncStatusMessage = "Gmail är redan ansluten."
            return
        }

        do {
            _ = try await gmailOAuthService.startAuthorization()
            gmailConnected = true
            syncStatusMessage = "Gmail anslöts."
        } catch {
            gmailConnected = false
            syncStatusMessage = "Kunde inte ansluta Gmail: \(error.localizedDescription)"
        }
    }

    private func refreshGmailConnectionState() async {
        gmailConnected = OAuthTokenManager.shared.hasStoredToken()
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

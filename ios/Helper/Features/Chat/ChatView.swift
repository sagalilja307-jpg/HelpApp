//
//  ChatView.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-24.
//

import SwiftData
import SwiftUI

public struct ChatView: View {
    @Bindable var vm: ChatViewModel
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusInput: Bool
    @State private var showContext = false
    @State private var showSupportSettings = false
    @State private var showCreateNote = false
    @State private var showDataSources = false
    @State private var supportSettingsViewModel = SupportSettingsViewModel()
    @State private var gmailSyncCoordinator = GmailSyncCoordinator()
    @State private var gmailOAuthService = GmailOAuthService()
    @State private var syncStatusMessage: String?
    @State private var noteTitle = ""
    @State private var noteBody = ""

    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService

    init(
        pipeline: QueryPipeline,
        sourceConnectionStore: SourceConnectionStore,
        photosIndexService: PhotosIndexService,
        filesImportService: FilesImportService
    ) {
        self.vm = ChatViewModel(pipeline: pipeline)
        self.sourceConnectionStore = sourceConnectionStore
        self.photosIndexService = photosIndexService
        self.filesImportService = filesImportService
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
                    Task { await handleGmailSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("Synka Gmail")
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
                filesImportService: filesImportService
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
    }

    // MARK: - Bubblor

    @ViewBuilder private func bubble(for msg: ChatViewModel.ChatMessage) -> some View {
        let isUser = (msg.role == .user)
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

    private func handleGmailSync() async {
        do {
            _ = try await OAuthTokenManager.shared.loadToken()
        } catch {
            do {
                _ = try await gmailOAuthService.startAuthorization()
            } catch {
                syncStatusMessage = "Kunde inte ansluta Gmail: \(error.localizedDescription)"
                return
            }
        }

        do {
            try await gmailSyncCoordinator.syncInbox()
            syncStatusMessage = "Gmail synkades."
        } catch {
            syncStatusMessage = "Gmail-synk misslyckades: \(error.localizedDescription)"
        }
    }

    private func createNote() {
        let service = NotesStoreService(context: modelContext)
        do {
            _ = try service.createNote(
                title: noteTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                body: noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
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

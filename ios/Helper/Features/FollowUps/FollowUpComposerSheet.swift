import SwiftUI
import UIKit

struct FollowUpComposerSheet: View {
    let draft: FollowUpComposerDraft
    let onCopy: @MainActor (FollowUpComposerDraft) async -> Bool
    let onShare: @MainActor (FollowUpComposerDraft) async -> Bool
    let onMarkSent: @MainActor (FollowUpComposerDraft) async -> Bool
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var contextText: String
    @State private var draftText: String
    @State private var isWorking = false

    init(
        draft: FollowUpComposerDraft,
        onCopy: @escaping @MainActor (FollowUpComposerDraft) async -> Bool,
        onShare: @escaping @MainActor (FollowUpComposerDraft) async -> Bool,
        onMarkSent: @escaping @MainActor (FollowUpComposerDraft) async -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onCopy = onCopy
        self.onShare = onShare
        self.onMarkSent = onMarkSent
        self.onCancel = onCancel
        _title = State(initialValue: draft.title)
        _contextText = State(initialValue: draft.contextText)
        _draftText = State(initialValue: draft.draftText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("Uppföljning", text: $title)
                }

                Section("Sammanhang") {
                    TextEditor(text: $contextText)
                        .frame(minHeight: 100)
                }

                Section("Meddelande") {
                    TextEditor(text: $draftText)
                        .frame(minHeight: 160)
                }

                Section("Påminnelse") {
                    HStack {
                        Text("Planerad till")
                        Spacer()
                        Text(draft.dueAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task { @MainActor in
                            await perform(action: onShare)
                        }
                    } label: {
                        Label("Dela", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)

                    Button {
                        Task { @MainActor in
                            await perform(action: onCopy)
                        }
                    } label: {
                        Label("Kopiera", systemImage: "doc.on.doc")
                    }
                    .disabled(isWorking)

                    Button {
                        Task { @MainActor in
                            await perform(action: onMarkSent)
                        }
                    } label: {
                        Label("Markera som skickat", systemImage: "checkmark.circle")
                    }
                    .disabled(isWorking)
                }
            }
            .navigationTitle("Uppföljning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
        }
    }
}

private extension FollowUpComposerSheet {
    @MainActor
    func perform(
        action: @escaping @MainActor (FollowUpComposerDraft) async -> Bool
    ) async {
        isWorking = true
        let didSave = await action(
            FollowUpComposerDraft(
                id: draft.id,
                sourceMessageID: draft.sourceMessageID,
                clusterID: draft.clusterID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                contextText: contextText.trimmingCharacters(in: .whitespacesAndNewlines),
                draftText: draftText.trimmingCharacters(in: .whitespacesAndNewlines),
                waitingSince: draft.waitingSince,
                eligibleAt: draft.eligibleAt,
                dueAt: draft.dueAt
            )
        )
        isWorking = false
        if didSave {
            dismiss()
        }
    }
}

struct TextShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

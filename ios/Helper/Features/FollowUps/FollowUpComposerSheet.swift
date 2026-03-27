import SwiftUI
import UIKit

struct FollowUpComposerSheet: View {
    let draft: FollowUpComposerDraft
    let onCopy: (FollowUpComposerDraft) async -> Void
    let onShare: (FollowUpComposerDraft) async -> Void
    let onMarkSent: (FollowUpComposerDraft) async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var contextText: String
    @State private var draftText: String
    @State private var isWorking = false

    init(
        draft: FollowUpComposerDraft,
        onCopy: @escaping (FollowUpComposerDraft) async -> Void,
        onShare: @escaping (FollowUpComposerDraft) async -> Void,
        onMarkSent: @escaping (FollowUpComposerDraft) async -> Void,
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
                        Task { await perform(action: onShare) }
                    } label: {
                        Label("Dela", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)

                    Button {
                        Task { await perform(action: onCopy) }
                    } label: {
                        Label("Kopiera", systemImage: "doc.on.doc")
                    }
                    .disabled(isWorking)

                    Button {
                        Task { await perform(action: onMarkSent) }
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
    func perform(
        action: @escaping (FollowUpComposerDraft) async -> Void
    ) async {
        isWorking = true
        await action(
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
        dismiss()
    }
}

struct TextShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

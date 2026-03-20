import SwiftUI

struct ChatSuggestionCardView: View {
    let suggestion: ChatSuggestionCard
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(suggestion.kind.badgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(suggestion.title)
                .font(.subheadline.weight(.semibold))

            Text(suggestion.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let statusText = statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            if shouldShowActions {
                HStack(spacing: 8) {
                    Button(action: onPrimary) {
                        if suggestion.state == .executing {
                            Label("Förbereder...", systemImage: "hourglass")
                        } else {
                            Text(suggestion.primaryActionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(suggestion.state == .executing)

                    Button("Inte nu", action: onDismiss)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(suggestion.state == .executing)
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.18))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var shouldShowActions: Bool {
        switch suggestion.state {
        case .visible, .executing, .failed:
            return true
        case .dismissed, .completed:
            return false
        }
    }

    private var statusText: String? {
        switch suggestion.state {
        case .visible:
            return nil
        case .dismissed:
            return nil
        case .executing:
            return "Förbereder..."
        case .completed:
            return "Klart"
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch suggestion.state {
        case .failed:
            return .red
        case .completed:
            return .green
        default:
            return .secondary
        }
    }
}

struct ChatReminderDraftSheet: View {
    let draft: ChatSuggestionDraft.ReminderDraft
    let onConfirm: (ChatSuggestionDraft.ReminderDraft) async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var dueDateEnabled: Bool
    @State private var dueDate: Date
    @State private var notes: String
    @State private var location: String
    @State private var priority: ChatSuggestionReminderPriority?
    @State private var isSaving = false

    init(
        draft: ChatSuggestionDraft.ReminderDraft,
        onConfirm: @escaping (ChatSuggestionDraft.ReminderDraft) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: draft.title)
        _dueDateEnabled = State(initialValue: draft.dueDate != nil)
        _dueDate = State(initialValue: draft.dueDate ?? DateService.shared.now())
        _notes = State(initialValue: draft.notes)
        _location = State(initialValue: draft.location ?? "")
        _priority = State(initialValue: draft.priority)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("Påminnelse", text: $title)
                }

                Section("Tid") {
                    Toggle("Sätt förfallodatum", isOn: $dueDateEnabled)
                    if dueDateEnabled {
                        DatePicker("Förfaller", selection: $dueDate)
                    }
                }

                Section("Detaljer") {
                    TextField("Plats", text: $location)
                    Picker("Prioritet", selection: $priority) {
                        Text("Ingen").tag(ChatSuggestionReminderPriority?.none)
                        ForEach(ChatSuggestionReminderPriority.allCases) { level in
                            Text(level.displayTitle).tag(Optional(level))
                        }
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Ny påminnelse")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skapa") {
                        let payload = ChatSuggestionDraft.ReminderDraft(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            dueDate: dueDateEnabled ? dueDate : nil,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                            priority: priority
                        )
                        isSaving = true
                        Task {
                            await onConfirm(payload)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ChatNoteDraftSheet: View {
    let draft: ChatSuggestionDraft.NoteDraft
    let saveLabel: String
    let onConfirm: (ChatSuggestionDraft.NoteDraft) async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var noteBody: String
    @State private var isSaving = false

    init(
        draft: ChatSuggestionDraft.NoteDraft,
        saveLabel: String = "Spara",
        onConfirm: @escaping (ChatSuggestionDraft.NoteDraft) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.saveLabel = saveLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: draft.title)
        _noteBody = State(initialValue: draft.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("Anteckningstitel", text: $title)
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
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        let payload = ChatSuggestionDraft.NoteDraft(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            body: noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        isSaving = true
                        Task {
                            await onConfirm(payload)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(
                        isSaving
                        || (
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    )
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

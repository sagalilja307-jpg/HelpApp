import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SupportSettingsViewModel {
    var settings: SupportSettingsSnapshot
    var learning: LearningSettingsSnapshot
    var isLoading = false
    var isUpdating = false
    var errorMessage: String?
    var resetSummary: String?

    private var hasLoaded = false
    private let service = SupportSettingsAPIService.shared

    init() {
        self.settings = SupportSettingsCache.loadSupport() ?? .fallback
        self.learning = SupportSettingsCache.loadLearning() ?? .empty
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let support = try await service.fetchSupportSettings()
            settings = support
            let learningSettings = try await service.fetchLearningSettings()
            learning = learningSettings
            settings.adaptationEnabled = learningSettings.adaptationEnabled
            SupportSettingsCache.saveSupport(settings)
            SupportSettingsCache.saveLearning(learningSettings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setSupportLevel(_ level: Int) async {
        let previous = settings
        settings.supportLevel = max(0, min(3, level))
        isUpdating = true
        defer { isUpdating = false }

        do {
            let updated = try await service.updateSupportSettings(supportLevel: settings.supportLevel)
            settings = updated
            SupportSettingsCache.saveSupport(updated)
        } catch {
            settings = previous
            errorMessage = error.localizedDescription
        }
    }

    func setSupportPaused(_ paused: Bool) async {
        let previous = settings
        settings.paused = paused
        isUpdating = true
        defer { isUpdating = false }

        do {
            let updated = try await service.updateSupportSettings(paused: paused)
            settings = updated
            SupportSettingsCache.saveSupport(updated)
        } catch {
            settings = previous
            errorMessage = error.localizedDescription
        }
    }

    func setAdaptationPaused(_ paused: Bool) async {
        let previous = settings.adaptationEnabled
        settings.adaptationEnabled = !paused
        isUpdating = true
        defer { isUpdating = false }

        do {
            let learningSettings = try await service.setLearningPaused(paused)
            learning = learningSettings
            settings.adaptationEnabled = learningSettings.adaptationEnabled
            if let updatedSupport = try? await service.fetchSupportSettings() {
                settings = updatedSupport
                settings.adaptationEnabled = learningSettings.adaptationEnabled
                SupportSettingsCache.saveSupport(settings)
            }
            SupportSettingsCache.saveLearning(learningSettings)
        } catch {
            settings.adaptationEnabled = previous
            errorMessage = error.localizedDescription
        }
    }

    func resetLearning() async {
        isUpdating = true
        defer { isUpdating = false }

        do {
            let reset = try await service.resetLearning()
            let learningSettings = try await service.fetchLearningSettings()
            let supportSettings = try await service.fetchSupportSettings()

            learning = learningSettings
            settings = supportSettings
            settings.adaptationEnabled = learningSettings.adaptationEnabled
            resetSummary = "Återställde \(reset.removedCount) lärda nycklar."
            SupportSettingsCache.saveSupport(settings)
            SupportSettingsCache.saveLearning(learningSettings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func levelDescription(for level: Int) -> String {
        switch level {
        case 0:
            return "Nivå 0: endast översikt, inga aktiva nudges."
        case 1:
            return "Nivå 1: endast tidskritiska signaler."
        case 2:
            return "Nivå 2: strukturerande förslag inom vald nivå."
        default:
            return "Nivå 3: aktiv uppstarts- och påminnelsehjälp."
        }
    }

    func formattedValue(_ value: AnyCodable) -> String {
        if let boolValue = value.value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let intValue = value.value as? Int {
            return String(intValue)
        }
        if let doubleValue = value.value as? Double {
            return String(format: "%.2f", doubleValue)
        }
        if let stringValue = value.value as? String {
            return stringValue
        }
        if let dictValue = value.value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dictValue, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        if let arrayValue = value.value as? [Any] {
            return arrayValue.map { String(describing: $0) }.joined(separator: ", ")
        }
        return String(describing: value.value)
    }

    func formattedPayload(_ payload: [String: AnyCodable]) -> String {
        guard payload.isEmpty == false else { return "—" }
        return payload
            .sorted(by: { $0.key < $1.key })
            .map { key, value in "\(key): \(formattedValue(value))" }
            .joined(separator: " · ")
    }
}

struct SupportSettingsSheetView: View {
    @Bindable var viewModel: SupportSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Stödnivå") {
                    Picker("Stödnivå", selection: Binding(
                        get: { viewModel.settings.supportLevel },
                        set: { newLevel in
                            Task { await viewModel.setSupportLevel(newLevel) }
                        })
                    ) {
                        Text("0").tag(0)
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)

                    Text(viewModel.levelDescription(for: viewModel.settings.supportLevel))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let cap = viewModel.settings.dailyCaps[String(viewModel.settings.supportLevel)] {
                        Text("Dagligt nudgetak för nivå \(viewModel.settings.supportLevel): \(cap)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Kontroller") {
                    Toggle(
                        "Pausa stödinterventioner",
                        isOn: Binding(
                            get: { viewModel.settings.paused },
                            set: { newValue in
                                Task { await viewModel.setSupportPaused(newValue) }
                            }
                        )
                    )

                    Toggle(
                        "Pausa adaptation",
                        isOn: Binding(
                            get: { !viewModel.settings.adaptationEnabled },
                            set: { pauseAdaptation in
                                Task { await viewModel.setAdaptationPaused(pauseAdaptation) }
                            }
                        )
                    )

                    Text("Adaptivitet justerar inom vald nivå och höjer aldrig grundintensiteten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Lärda mönster") {
                    if viewModel.learning.patterns.isEmpty {
                        Text("Inga lärda mönster ännu.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.learning.patterns) { pattern in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pattern.key)
                                    .font(.headline)
                                Text(viewModel.formattedValue(pattern.value))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Ändringsorsaker") {
                    if viewModel.learning.events.isEmpty {
                        Text("Inga händelser loggade ännu.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.learning.events.prefix(20)) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.eventType)
                                    .font(.headline)
                                Text(event.createdAt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(viewModel.formattedPayload(event.payload))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Återställning") {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Text("Reset learning")
                    }

                    if let resetSummary = viewModel.resetSummary {
                        Text(resetSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Stödinställningar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Stäng") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoading || viewModel.isUpdating {
                        ProgressView()
                    } else {
                        Button("Uppdatera") {
                            Task { await viewModel.refresh() }
                        }
                    }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .alert(
                "Fel",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            viewModel.clearError()
                        }
                    }
                )
            ) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Återställ lärda mönster?", isPresented: $showResetConfirmation) {
                Button("Avbryt", role: .cancel) {}
                Button("Återställ", role: .destructive) {
                    Task { await viewModel.resetLearning() }
                }
            } message: {
                Text("Detta nollställer endast lärda vikter och behåller vald stödnivå.")
            }
        }
    }
}

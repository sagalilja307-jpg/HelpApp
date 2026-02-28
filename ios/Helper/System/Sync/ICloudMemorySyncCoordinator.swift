import Foundation

struct MemorySyncOutcome: Sendable {
    enum Status: Sendable {
        case synced
        case skipped
        case failed
    }

    let status: Status
    let message: String
    let mergedNotes: Int
    let mergedLongTermItems: Int
}

private struct SyncedMemoryPayload: Codable {
    let version: Int
    let exportedAt: Date
    let deviceID: String
    let notes: [UserNoteSyncRecord]
    let longTermItems: [LongTermMemorySyncRecord]
}

@MainActor
final class ICloudMemorySyncCoordinator {
    private enum Constants {
        static let fileName = "helper-memory-sync-v1.json"
        static let payloadVersion = 1
        static let lastSyncAtKey = "helper.icloud.memory.last_sync_at"
        static let deviceIDKey = "helper.icloud.memory.device_id"
    }

    private let memoryService: MemoryService
    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator
    private let keyValueSyncCoordinator: ICloudKeyValueSyncCoordinator
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        memoryService: MemoryService,
        longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator,
        keyValueSyncCoordinator: ICloudKeyValueSyncCoordinator,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        self.memoryService = memoryService
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
        self.keyValueSyncCoordinator = keyValueSyncCoordinator
        self.fileManager = fileManager
        self.defaults = defaults

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    var lastSyncAt: Date? {
        defaults.object(forKey: Constants.lastSyncAtKey) as? Date
    }

    func syncNow() async -> MemorySyncOutcome {
        guard keyValueSyncCoordinator.isSyncEnabled else {
            return MemorySyncOutcome(
                status: .skipped,
                message: "iCloud-synk är avstängd i appen.",
                mergedNotes: 0,
                mergedLongTermItems: 0
            )
        }

        guard keyValueSyncCoordinator.hasICloudAccount else {
            return MemorySyncOutcome(
                status: .skipped,
                message: "Ingen iCloud-inloggning hittad på enheten.",
                mergedNotes: 0,
                mergedLongTermItems: 0
            )
        }

        guard let fileURL = syncFileURL() else {
            return MemorySyncOutcome(
                status: .failed,
                message: "Kunde inte nå iCloud-behållaren för datasynk.",
                mergedNotes: 0,
                mergedLongTermItems: 0
            )
        }

        var mergedNotes = 0
        var mergedLongTermItems = 0

        if let incomingData = try? Data(contentsOf: fileURL), !incomingData.isEmpty {
            do {
                let incoming = try decoder.decode(SyncedMemoryPayload.self, from: incomingData)
                mergedNotes = memoryService.mergeUserNoteSyncRecords(incoming.notes)
                mergedLongTermItems = longTermMemorySaveCoordinator.mergeSyncRecords(incoming.longTermItems)
            } catch {
                return MemorySyncOutcome(
                    status: .failed,
                    message: "Kunde inte läsa inkommande iCloud-data: \(error.localizedDescription)",
                    mergedNotes: 0,
                    mergedLongTermItems: 0
                )
            }
        }

        let outgoing = SyncedMemoryPayload(
            version: Constants.payloadVersion,
            exportedAt: DateService.shared.now(),
            deviceID: localDeviceID(),
            notes: memoryService.exportUserNoteSyncRecords(),
            longTermItems: longTermMemorySaveCoordinator.exportSyncRecords()
        )

        do {
            let data = try encoder.encode(outgoing)
            try data.write(to: fileURL, options: .atomic)
            defaults.set(outgoing.exportedAt, forKey: Constants.lastSyncAtKey)
            return MemorySyncOutcome(
                status: .synced,
                message: "Synk klar. \(mergedNotes) anteckningar och \(mergedLongTermItems) långtidsminnen hämtades.",
                mergedNotes: mergedNotes,
                mergedLongTermItems: mergedLongTermItems
            )
        } catch {
            return MemorySyncOutcome(
                status: .failed,
                message: "Kunde inte skriva iCloud-data: \(error.localizedDescription)",
                mergedNotes: mergedNotes,
                mergedLongTermItems: mergedLongTermItems
            )
        }
    }

    private func syncFileURL() -> URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }

        return documentsURL.appendingPathComponent(Constants.fileName)
    }

    private func localDeviceID() -> String {
        if let stored = defaults.string(forKey: Constants.deviceIDKey), !stored.isEmpty {
            return stored
        }

        let created = UUID().uuidString
        defaults.set(created, forKey: Constants.deviceIDKey)
        return created
    }
}

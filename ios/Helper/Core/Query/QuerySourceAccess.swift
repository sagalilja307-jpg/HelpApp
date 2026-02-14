import Foundation
#if canImport(EventKit)
import EventKit
#endif
#if canImport(Contacts)
import Contacts
#endif
#if canImport(PhotoKit)
import PhotoKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

// ===============================================================
// File: Helper/Core/Query/QuerySourceAccess.swift
// ===============================================================

/// Which internal data source the system may read from.
enum QuerySource: String, Sendable, Codable {
    case memory
    case rawEvents
    case calendar
    case reminders
    case contacts
    case photos
    case files
    case location
}

protocol QuerySourceAccessing: Sendable {
    func isAllowed(_ source: QuerySource) -> Bool
    func assertAllowed(_ source: QuerySource) throws
    func deniedReason(for source: QuerySource) -> String
}

struct QuerySourceAccess: QuerySourceAccessing, Sendable {

    enum MemoryAccess: Sendable {
        case allowed
        case denied(reason: String)
    }

    private let memoryAccess: MemoryAccess
    private let rawEventsAccess: MemoryAccess
    private let sourceConnectionStore: SourceConnectionStoring

    init(
        memory: MemoryAccess = .allowed,
        rawEvents: MemoryAccess = .allowed,
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared
    ) {
        self.memoryAccess = memory
        self.rawEventsAccess = rawEvents
        self.sourceConnectionStore = sourceConnectionStore
    }

    // MARK: - Public API

    func isAllowed(_ source: QuerySource) -> Bool {
        switch source {
        case .memory:
            return isAllowed(memoryAccess)
        case .rawEvents:
            return isAllowed(rawEventsAccess)
        case .calendar:
            return calendarAuthorized()
        case .reminders:
            return remindersAuthorized()
        case .contacts:
            return sourceConnectionStore.isEnabled(.contacts) && contactsAuthorized()
        case .photos:
            return sourceConnectionStore.isEnabled(.photos) && photosAuthorized()
        case .files:
            return sourceConnectionStore.isEnabled(.files) && sourceConnectionStore.hasImportedFiles()
        case .location:
            return sourceConnectionStore.isEnabled(.location) && locationAuthorized()
        }
    }

    func assertAllowed(_ source: QuerySource) throws {
        guard isAllowed(source) else {
            throw QueryPipelineError.sourceNotAllowed(
                source,
                deniedReason(for: source)
            )
        }
    }

    func deniedReason(for source: QuerySource) -> String {
        switch source {
        case .memory:
            return reason(
                for: memoryAccess,
                fallback: "Jag kan inte läsa minnen – du har inte godkänt åtkomst."
            )
        case .rawEvents:
            return reason(
                for: rawEventsAccess,
                fallback: "Jag kan inte se råhändelser – du har inte godkänt åtkomst."
            )
        case .calendar:
            return "Jag kan inte se kalendern – du har inte godkänt åtkomst."
        case .reminders:
            return "Jag kan inte se påminnelser – du har inte godkänt åtkomst."
        case .contacts:
            if !sourceConnectionStore.isEnabled(.contacts) {
                return "Kontakter är inte aktiverad som datakälla."
            }
            return "Jag kan inte läsa kontakter – du har inte godkänt åtkomst."
        case .photos:
            if !sourceConnectionStore.isEnabled(.photos) {
                return "Bilder är inte aktiverad som datakälla."
            }
            return "Jag kan inte läsa bilder – du har inte godkänt åtkomst."
        case .files:
            if !sourceConnectionStore.isEnabled(.files) {
                return "Filer är inte aktiverad som datakälla."
            }
            return "Jag hittar ingen importerad fil-data ännu."
        case .location:
            if !sourceConnectionStore.isEnabled(.location) {
                return "Plats är inte aktiverad som datakälla."
            }
            return "Jag kan inte läsa plats – du har inte godkänt åtkomst."
        }
    }
}

// MARK: - Helpers

private extension QuerySourceAccess {

    func isAllowed(_ access: MemoryAccess) -> Bool {
        if case .allowed = access { return true }
        return false
    }

    func reason(for access: MemoryAccess, fallback: String) -> String {
        switch access {
        case .allowed:
            return ""
        case .denied(let reason):
            return reason
        }
    }

    func calendarAuthorized() -> Bool {
        #if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess || status == .writeOnly
        } else {
            return status == .authorized
        }
        #else
        return false
        #endif
    }

    func remindersAuthorized() -> Bool {
        #if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess || status == .writeOnly
        } else {
            return status == .authorized
        }
        #else
        return false
        #endif
    }

    func contactsAuthorized() -> Bool {
        #if canImport(Contacts)
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized
        #else
        return false
        #endif
    }

    func photosAuthorized() -> Bool {
        #if canImport(PhotoKit)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
        #else
        return false
        #endif
    }

    func locationAuthorized() -> Bool {
        #if canImport(CoreLocation)
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
        #else
        return false
        #endif
    }
}

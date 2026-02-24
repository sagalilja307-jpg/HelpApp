//
//  CalendarSyncManager.swift
//  Helper
//
//  Created by Saga Lilja on 2026-02-18.
//


import Foundation
import EventKit
import Combine

@MainActor
public final class CalendarSyncManager: ObservableObject {

    // MARK: - Permission State

    /// För chat/use-cases är det viktigt att skilja på "write only" och "full access"
    /// eftersom man inte kan läsa kalenderhändelser med write-only.
    public enum PermissionState: Equatable {
        case unknown
        case denied
        case writeOnly
        case fullAccess
    }

    @Published public private(set) var permission: PermissionState = .unknown

    // MARK: - Private

    private let store: EKEventStore
    var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        refreshAuthorizationStatus()
        observeEventStoreChanges()
    }

    // MARK: - Public API

    /// True om appen kan läsa kalenderhändelser (behövs för “vad har jag i kalendern?”)
    public var canReadEvents: Bool {
        permission == .fullAccess
    }

    /// True om appen kan skapa events (write-only eller full access)
    public var canWriteEvents: Bool {
        permission == .writeOnly || permission == .fullAccess
    }

    public func refreshAuthorizationStatus() {
        let op = "CalendarRefreshAuthorizationStatus"
        DataSourceDebug.start(op)
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .notDetermined:
            permission = .unknown

        case .denied, .restricted:
            permission = .denied

        case .writeOnly:
            permission = .writeOnly

        case .authorized, .fullAccess:
            permission = .fullAccess

        @unknown default:
            permission = .unknown
        }
        DataSourceDebug.success(op)
    }

    /// Begär FULL ACCESS (läs + skriv) till kalendern.
    /// Returnerar true endast om vi faktiskt har full access efteråt.
    public func requestAccess() async -> Bool {
        let op = "CalendarRequestAccess"
        DataSourceDebug.start(op)
        do {
            if #available(iOS 17.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestAccess(to: .event)
            }

            refreshAuthorizationStatus()
            let granted = permission == .fullAccess
            DataSourceDebug.success(op, count: granted ? 1 : 0)
            return granted

        } catch {
            refreshAuthorizationStatus()
            DataSourceDebug.failure(op, error)
            return false
        }
    }
}

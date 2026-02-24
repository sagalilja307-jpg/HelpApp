import Foundation
import EventKit
import Combine

extension CalendarSyncManager {

    // MARK: - Event Observation

    func observeEventStoreChanges() {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAuthorizationStatus()
            }
            .store(in: &cancellables)
    }
}

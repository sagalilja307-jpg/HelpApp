import XCTest
@testable import Helper

final class SourceConnectionStoreTests: XCTestCase {

    func testPhotosCannotBeDisabled() {
        let (store, suiteName) = makeStore()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(store.isEnabled(.photos))

        store.setEnabled(false, for: .photos)

        XCTAssertTrue(store.isEnabled(.photos))
    }

    func testOtherSourcesKeepNormalToggleBehavior() {
        let (store, suiteName) = makeStore()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        store.setEnabled(false, for: .contacts)
        store.setEnabled(false, for: .mail)
        store.setEnabled(false, for: .files)
        store.setEnabled(false, for: .location)

        XCTAssertFalse(store.isEnabled(.contacts))
        XCTAssertFalse(store.isEnabled(.mail))
        XCTAssertFalse(store.isEnabled(.files))
        XCTAssertFalse(store.isEnabled(.location))

        store.setEnabled(true, for: .contacts)
        store.setEnabled(true, for: .mail)
        store.setEnabled(true, for: .files)
        store.setEnabled(true, for: .location)

        XCTAssertTrue(store.isEnabled(.contacts))
        XCTAssertTrue(store.isEnabled(.mail))
        XCTAssertTrue(store.isEnabled(.files))
        XCTAssertTrue(store.isEnabled(.location))
    }

    private func makeStore() -> (SourceConnectionStore, String) {
        let suiteName = "SourceConnectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (SourceConnectionStore(defaults: defaults), suiteName)
    }
}

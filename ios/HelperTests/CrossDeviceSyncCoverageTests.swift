import XCTest
@testable import Helper

final class CrossDeviceSyncCoverageTests: XCTestCase {

    func testAllMemorySchemaModelsHaveExplicitSyncDecision() {
        let uncovered = CrossDeviceSyncPolicy.uncoveredMemoryModels(in: MemorySchemaV3.models)

        XCTAssertTrue(
            uncovered.isEmpty,
            "Nya modeller i MemorySchemaV3 saknar sync-beslut: \(uncovered.joined(separator: ", ")). " +
            "Uppdatera CrossDeviceSyncPolicy och implementera synk om modellen är relevant."
        )
    }

    func testSyncPolicyHasNoStaleEntries() {
        let staleEntries = CrossDeviceSyncPolicy.staleMemoryPolicyEntries(in: MemorySchemaV3.models)

        XCTAssertTrue(
            staleEntries.isEmpty,
            "CrossDeviceSyncPolicy innehåller poster som inte längre finns i schema: \(staleEntries.joined(separator: ", "))."
        )
    }

    func testCurrentSyncedModelsAreExpectedOnes() {
        XCTAssertEqual(
            CrossDeviceSyncPolicy.syncedMemoryModelNames,
            Set(["UserNote", "LongTermMemoryItem"]),
            "Om du ändrar synkomfång: uppdatera testet och sync-implementationen samtidigt."
        )
    }
}

import XCTest
import SwiftData
@testable import Helper

@MainActor
final class MemorySchemaMigrationTests: XCTestCase {

    func testMigrationPlanDefinesV1ToV2LightweightStage() {
        XCTAssertEqual(MemorySchemaMigrationPlan.schemas.count, 2)
        XCTAssertTrue(MemorySchemaMigrationPlan.schemas[0] == MemorySchemaV1.self)
        XCTAssertTrue(MemorySchemaMigrationPlan.schemas[1] == MemorySchemaV2.self)

        XCTAssertEqual(MemorySchemaMigrationPlan.stages.count, 1)
        guard case let .lightweight(fromVersion, toVersion) = MemorySchemaMigrationPlan.stages[0] else {
            return XCTFail("Expected a lightweight migration stage")
        }
        XCTAssertTrue(fromVersion == MemorySchemaV1.self)
        XCTAssertTrue(toVersion == MemorySchemaV2.self)
    }

    func testV2SchemaDropsLegacyCheckpointAndKeepsPrimaryModels() {
        let schema = Schema(versionedSchema: MemorySchemaV2.self)
        let entityNames = Set(schema.entities.map(\.name))

        XCTAssertTrue(entityNames.contains("RawEvent"))
        XCTAssertTrue(entityNames.contains("UserNote"))
        XCTAssertFalse(entityNames.contains("LegacyIngestCheckpoint"))
    }
}

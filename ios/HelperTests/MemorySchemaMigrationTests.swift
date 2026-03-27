import XCTest
import SwiftData
@testable import Helper

@MainActor
final class MemorySchemaMigrationTests: XCTestCase {

    func testMigrationPlanDefinesV1ToV2LightweightStage() {
        XCTAssertEqual(MemorySchemaMigrationPlan.schemas.count, 4)
        XCTAssertTrue(MemorySchemaMigrationPlan.schemas[0] == MemorySchemaV1.self)
        XCTAssertTrue(MemorySchemaMigrationPlan.schemas[1] == MemorySchemaV2.self)
        XCTAssertTrue(MemorySchemaMigrationPlan.schemas[2] == MemorySchemaV3.self)
        XCTAssertTrue(MemorySchemaMigrationPlan.schemas[3] == MemorySchemaV4.self)

        XCTAssertEqual(MemorySchemaMigrationPlan.stages.count, 3)
        guard case let .lightweight(fromVersion, toVersion) = MemorySchemaMigrationPlan.stages[0] else {
            return XCTFail("Expected a lightweight migration stage")
        }
        XCTAssertTrue(fromVersion == MemorySchemaV1.self)
        XCTAssertTrue(toVersion == MemorySchemaV2.self)

        guard case let .lightweight(fromVersion, toVersion) = MemorySchemaMigrationPlan.stages[1] else {
            return XCTFail("Expected a second lightweight migration stage")
        }
        XCTAssertTrue(fromVersion == MemorySchemaV2.self)
        XCTAssertTrue(toVersion == MemorySchemaV3.self)

        guard case let .lightweight(fromVersion, toVersion) = MemorySchemaMigrationPlan.stages[2] else {
            return XCTFail("Expected a third lightweight migration stage")
        }
        XCTAssertTrue(fromVersion == MemorySchemaV3.self)
        XCTAssertTrue(toVersion == MemorySchemaV4.self)
    }

    func testV4SchemaIncludesLongTermMemoryAndPendingFollowUps() {
        let schema = Schema(versionedSchema: MemorySchemaV4.self)
        let entityNames = Set(schema.entities.map(\.name))

        XCTAssertTrue(entityNames.contains("RawEvent"))
        XCTAssertTrue(entityNames.contains("UserNote"))
        XCTAssertTrue(entityNames.contains("LongTermMemoryItem"))
        XCTAssertTrue(entityNames.contains("LongTermMemoryPendingJob"))
        XCTAssertTrue(entityNames.contains("PendingFollowUp"))
        XCTAssertFalse(entityNames.contains("LegacyIngestCheckpoint"))
    }
}

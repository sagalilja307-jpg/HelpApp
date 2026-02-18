import XCTest
@testable import Helper

final class LocationSnapshotServiceTests: XCTestCase {
    
    // MARK: - Coordinate Rounding Tests
    
    func testCoordinateRoundingToTwoDecimals() {
        // Verify coarse rounding to ~1.1 km precision
        XCTAssertEqual(LocationSnapshotService.roundCoordinate(59.3293), 59.33)
        XCTAssertEqual(LocationSnapshotService.roundCoordinate(59.3249), 59.32)
        XCTAssertEqual(LocationSnapshotService.roundCoordinate(18.0686), 18.07)
        XCTAssertEqual(LocationSnapshotService.roundCoordinate(-33.8688), -33.87)
    }
    
    func testCoordinateRoundingPreservesSign() {
        XCTAssertEqual(LocationSnapshotService.roundCoordinate(-0.1276), -0.13)
        XCTAssertEqual(LocationSnapshotService.roundCoordinate(0.0001), 0.0)
    }
    
    // MARK: - Fallback Logic Tests
    
    func testFallbackMaxAgeConstant() {
        // Verify 30 minute fallback constant
        XCTAssertEqual(LocationSnapshotService.fallbackMaxAge, 30 * 60)
    }
    
    // MARK: - Authorization Status Tests
    
    #if canImport(CoreLocation)
    func testServiceInitializesCorrectly() throws {
        // This test just verifies the service can be initialized
        // without crashing when CoreLocation is available
        let service = LocationSnapshotService()
        XCTAssertNotNil(service)
    }
    #endif
}

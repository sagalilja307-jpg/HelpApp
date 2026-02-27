import XCTest
@testable import Helper

final class LongTermMemoryClusteringServiceTests: XCTestCase {
    func testClusterReturnsEmptyForNoItems() {
        let service = LongTermMemoryClusteringService()

        let clusters = service.cluster(items: [], preferredClusterCount: 2)

        XCTAssertTrue(clusters.isEmpty)
    }

    func testClusterFormsTwoSeparatedGroups() {
        let service = LongTermMemoryClusteringService()

        let items = [
            LongTermMemoryItem(
                originalText: "alpha-1",
                cleanText: "alpha-1",
                suggestedType: "Idea",
                tags: ["alpha"],
                embedding: [1.0, 0.0]
            ),
            LongTermMemoryItem(
                originalText: "alpha-2",
                cleanText: "alpha-2",
                suggestedType: "Idea",
                tags: ["alpha"],
                embedding: [0.95, 0.05]
            ),
            LongTermMemoryItem(
                originalText: "beta-1",
                cleanText: "beta-1",
                suggestedType: "Risk",
                tags: ["beta"],
                embedding: [-1.0, 0.0]
            ),
            LongTermMemoryItem(
                originalText: "beta-2",
                cleanText: "beta-2",
                suggestedType: "Risk",
                tags: ["beta"],
                embedding: [-0.95, -0.05]
            )
        ]

        let clusters = service.cluster(items: items, preferredClusterCount: 2)

        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.map(\.itemCount).sorted(), [2, 2])
        XCTAssertEqual(Set(clusters.flatMap(\.memberIDs)), Set(items.map(\.id)))

        let dominantTypes = Set(clusters.map(\.dominantType))
        XCTAssertEqual(dominantTypes, Set([.idea, .risk]))
    }

    func testClusterIgnoresMismatchedEmbeddingDimensions() {
        let service = LongTermMemoryClusteringService()

        let keptA = LongTermMemoryItem(
            originalText: "kept-1",
            cleanText: "kept-1",
            suggestedType: "Insight",
            tags: ["kept"],
            embedding: [0.4, 0.9]
        )
        let keptB = LongTermMemoryItem(
            originalText: "kept-2",
            cleanText: "kept-2",
            suggestedType: "Insight",
            tags: ["kept"],
            embedding: [0.5, 0.8]
        )
        let droppedA = LongTermMemoryItem(
            originalText: "drop-1",
            cleanText: "drop-1",
            suggestedType: "Insight",
            tags: ["drop"],
            embedding: [0.4, 0.9, 0.1]
        )
        let droppedB = LongTermMemoryItem(
            originalText: "drop-2",
            cleanText: "drop-2",
            suggestedType: "Insight",
            tags: ["drop"],
            embedding: []
        )

        let clusters = service.cluster(
            items: [keptA, keptB, droppedA, droppedB],
            preferredClusterCount: 2
        )

        XCTAssertEqual(Set(clusters.flatMap(\.memberIDs)), Set([keptA.id, keptB.id]))
    }
}

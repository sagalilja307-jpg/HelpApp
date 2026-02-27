import Foundation

struct LongTermMemoryCluster: Identifiable, Equatable, Sendable {
    let id: Int
    let memberIDs: [UUID]
    let centroid: [Float]
    let topTags: [String]
    let dominantType: LongTermMemoryType
    let sampleText: String?

    var itemCount: Int {
        memberIDs.count
    }
}

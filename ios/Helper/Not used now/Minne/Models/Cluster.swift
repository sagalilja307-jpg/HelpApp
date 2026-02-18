import SwiftData
import Foundation

@Model
public final class Cluster {
    @Attribute(.unique) public var clusterId: String
    public var label: String
    public var requiresPrep: RequiresPrep
    public var confidence: Double
    public var status: ClusterStatus
    public var proposedBy: ActorRaw
    public var updatedAt: Date
    public var centroidData: Data
    public var title: String?
    public var titleConfidence: TitleConfidenceRaw

    // 🆕 E: Follow-up metadata
    public var waitingSince: Date?
    public var followUpSuggested: Bool

    @Relationship(deleteRule: .cascade, inverse: \ClusterItem.cluster)
    public var items: [ClusterItem] = []

    public init(
        clusterId: String,
        label: String,
        requiresPrep: RequiresPrep = .unknown,
        confidence: Double = 0.0,
        status: ClusterStatus = .proposed,
        proposedBy: Actor,
        updatedAt: Date = DateService.shared.now(),
        centroid: [Double] = [],
        title: String? = nil,
        titleConfidence: TitleConfidence = .low,
        waitingSince: Date? = nil,
        followUpSuggested: Bool = false
    ) {
        self.clusterId = clusterId
        self.label = label
        self.requiresPrep = requiresPrep
        self.confidence = confidence
        self.status = status
        self.proposedBy = ActorRaw(value: proposedBy.rawValue)
        self.updatedAt = updatedAt
        self.centroidData = try! JSONEncoder().encode(centroid)
        self.title = title
        self.titleConfidence = TitleConfidenceRaw(value: titleConfidence)
        self.waitingSince = waitingSince
        self.followUpSuggested = followUpSuggested
    }

    public var centroid: [Double] {
        get { (try? JSONDecoder().decode([Double].self, from: centroidData)) ?? [] }
        set { centroidData = try! JSONEncoder().encode(newValue) }
    }

    public func addItem(_ item: ClusterItem) {
        items.append(item)
        updatedAt = item.addedAt

        // 🧠 Om något händer → avsluta väntan
        if status == .waitingForResponse {
            status = .active
            waitingSince = nil
            followUpSuggested = false
        }
    }
}

extension Cluster {
    public func toContext() -> ClusterContext {
        let texts = items
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map { $0.rawText }

        return ClusterContext(
            clusterId: clusterId,
            title: title,
            state: status,
            lastUpdated: updatedAt,
            recentTexts: texts,
            itemCount: items.count,
            followUpSuggested: followUpSuggested // 🆕 VIKTIG RAD
        )
    }
}

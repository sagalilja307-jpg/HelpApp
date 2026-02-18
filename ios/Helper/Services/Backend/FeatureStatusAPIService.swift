import Foundation

// Deprecated in Snapshot DataIntent v1.
// Kept as a lightweight placeholder to avoid project-file churn.
protocol FeatureStatusFetching {}

final class FeatureStatusAPIService: FeatureStatusFetching {
    static let shared = FeatureStatusAPIService()
    private init() {}
}

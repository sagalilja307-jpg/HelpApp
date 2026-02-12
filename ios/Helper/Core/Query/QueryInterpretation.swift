import Foundation

/// Result of interpreting a query (meaning only; no data).
struct QueryInterpretation: Codable, Equatable, Sendable {
    let intent: QueryIntent

    /// Which internal data sources are REQUIRED to answer the query.
    let requiredSources: [QuerySource]

    let timeRange: DateInterval?
    let confidence: Double?
}

import SwiftData
import Foundation

/// Ett mönster som systemet har noterat över tid.
/// Dessa är observationer – inte sanningar.
/// Mönster är tidsberoende och kan blekna när beteendet ändras.
@Model
public final class BehaviorPattern {

    /// En kort, neutral etikett för beteendet
    /// Ex: "repeated_no_action:reminder:123"
    @Attribute(.unique)
    public var pattern: String

    /// Hur starkt mönstret är just nu (0.0–1.0)
    /// Bygger på frekvens och volym inom ett tidsfönster
    public var confidence: Double

    /// Underlag för mönstret (för transparens)
    /// Ex:
    /// {
    ///   "window_days": 90,
    ///   "frequency": 0.75,
    ///   "occurrences": 12,
    ///   "strength": 0.68,
    ///   "retention_days": 120
    /// }
    public var evidenceJSON: String?

    /// När mönstret senast uppdaterades
    /// Används för att avgöra om mönstret fortfarande är relevant
    public var updatedAt: Date

    public init(
        pattern: String,
        confidence: Double,
        evidenceJSON: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.pattern = pattern
        self.confidence = confidence
        self.evidenceJSON = evidenceJSON
        self.updatedAt = updatedAt
    }
}

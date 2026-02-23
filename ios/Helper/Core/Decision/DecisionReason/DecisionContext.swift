
import Foundation

/// Samlar all kontextuell information som beslutsregler använder.
public struct DecisionContext {
    public let policy: DecisionPolicy
    public let temporaryContext: TemporaryContext?
    public let clusterContext: ClusterContext?

    public init(
        policy: DecisionPolicy,
        temporaryContext: TemporaryContext? = nil,
        clusterContext: ClusterContext? = nil
    ) {
        self.policy = policy
        self.temporaryContext = temporaryContext
        self.clusterContext = clusterContext
    }
}

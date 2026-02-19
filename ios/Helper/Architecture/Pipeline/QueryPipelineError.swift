import Foundation

/// Simple pipeline error used by access assertions.
enum QueryPipelineError: Error, Sendable {
    case sourceNotAllowed(QuerySource, String)
}

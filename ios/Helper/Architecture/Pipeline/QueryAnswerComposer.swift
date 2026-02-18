import Foundation

/// Legacy placeholder kept for binary/source stability.
/// Answer composition now happens directly inside `QueryPipeline`.
final class QueryAnswerComposer {
    func compose(result: QueryResult) async throws -> QueryResult {
        result
    }
}

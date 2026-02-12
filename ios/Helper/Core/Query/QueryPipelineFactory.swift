import Foundation
import SwiftData

struct QueryPipelineFactory {

    static func make(memoryService: MemoryService) -> QueryPipeline {
        QueryPipeline(
            interpreter: QueryInterpreter(),
            access: QuerySourceAccess(memory: .allowed, rawEvents: .allowed),
            fetcher: QueryDataFetcher(),
            composer: QueryAnswerComposer()
        )
    }
}

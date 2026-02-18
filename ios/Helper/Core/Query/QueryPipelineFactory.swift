import Foundation

struct QueryPipelineFactory {

    static func make(memoryService: MemoryService) -> QueryPipeline {
        QueryPipeline(
            access: QuerySourceAccess(memory: .allowed, rawEvents: .allowed),
            fetcher: QueryDataFetcher(memoryService: memoryService),
            ingestService: AssistantIngestAPIService.shared,
            backendQueryService: BackendQueryAPIService.shared,
            memoryService: memoryService
        )
    }
}

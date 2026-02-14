import Foundation
import SwiftData

/// Coordinates query data collection for QueryPipeline
/// Owns ModelContext lifecycle - creates fresh context per operation
@MainActor
final class QueryDataCoordinator {
    
    private let memoryService: MemoryService
    private let notesService: NotesStoreService
    private let contactsCollector: ContactsCollectorService
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationCollector: LocationCollectorService
    private let checkpointStore: Etapp2IngestCheckpointStore
    
    init(
        memoryService: MemoryService,
        sourceConnectionStore: SourceConnectionStore,
        fileTextExtraction: FileTextExtractionService
    ) {
        self.memoryService = memoryService
        self.notesService = NotesStoreService()
        self.contactsCollector = ContactsCollectorService()
        self.photosIndexService = PhotosIndexService(sourceConnectionStore: sourceConnectionStore)
        self.filesImportService = FilesImportService(
            textExtractionService: fileTextExtraction,
            sourceConnectionStore: sourceConnectionStore
        )
        self.locationCollector = LocationCollectorService(
            snapshotService: LocationSnapshotService()
        )
        self.checkpointStore = Etapp2IngestCheckpointStore()
    }
    
    // MARK: - Combined Query Data Collection
    
    /// Collects all relevant data for a query in a single context
    func collectQueryData(
        forQuery query: String,
        includeNotes: Bool = true,
        includeContacts: Bool = true,
        includePhotos: Bool = true,
        includeFiles: Bool = true,
        includeLocations: Bool = true
    ) throws -> QueryDataSnapshot {
        let context = memoryService.context()
        
        var notes: [UserNote] = []
        var contacts: [IndexedContact] = []
        var photos: [IndexedPhotoAsset] = []
        var files: [IndexedFileDocument] = []
        var locations: [IndexedLocationSnapshot] = []
        
        if includeNotes {
            notes = try notesService.searchNotesByKeyword(query, in: context)
        }
        
        if includeContacts {
            contacts = try contactsCollector.searchContactsByName(query, in: context)
        }
        
        if includePhotos {
            photos = try photosIndexService.searchPhotosByOCR(query, in: context)
        }
        
        if includeFiles {
            files = try filesImportService.searchFilesByContent(query, in: context)
        }
        
        if includeLocations {
            locations = try locationCollector.searchLocationsByName(query, in: context)
        }
        
        return QueryDataSnapshot(
            query: query,
            notes: notes,
            contacts: contacts,
            photos: photos,
            files: files,
            locations: locations,
            collectedAt: Date()
        )
    }
    
    // MARK: - Individual Source Queries
    
    func queryNotes(_ searchText: String) throws -> [UserNote] {
        let context = memoryService.context()
        return try notesService.searchNotesByKeyword(searchText, in: context)
    }
    
    func queryContacts(_ searchText: String) throws -> [IndexedContact] {
        let context = memoryService.context()
        return try contactsCollector.searchContactsByName(searchText, in: context)
    }
    
    func queryPhotos(_ searchText: String) throws -> [IndexedPhotoAsset] {
        let context = memoryService.context()
        return try photosIndexService.searchPhotosByOCR(searchText, in: context)
    }
    
    func queryFiles(_ searchText: String) throws -> [IndexedFileDocument] {
        let context = memoryService.context()
        return try filesImportService.searchFilesByContent(searchText, in: context)
    }
    
    func queryLocations(_ searchText: String) throws -> [IndexedLocationSnapshot] {
        let context = memoryService.context()
        return try locationCollector.searchLocationsByName(searchText, in: context)
    }
    
    // MARK: - Recent Data
    
    func fetchRecentNotes(limit: Int = 10) throws -> [UserNote] {
        let context = memoryService.context()
        let allNotes = try notesService.listNotes(in: context)
        return Array(allNotes.prefix(limit))
    }
    
    func fetchRecentLocations(limit: Int = 10) throws -> [IndexedLocationSnapshot] {
        let context = memoryService.context()
        return try locationCollector.fetchRecentLocations(limit: limit, in: context)
    }
    
    // MARK: - Checkpoint Queries
    
    func getLastIngestTimestamp(source: String) throws -> Date? {
        let context = memoryService.context()
        return try checkpointStore.getLastIngestTimestamp(source: source, in: context)
    }
}

// MARK: - Data Snapshot

struct QueryDataSnapshot {
    let query: String
    let notes: [UserNote]
    let contacts: [IndexedContact]
    let photos: [IndexedPhotoAsset]
    let files: [IndexedFileDocument]
    let locations: [IndexedLocationSnapshot]
    let collectedAt: Date
    
    var totalResults: Int {
        notes.count + contacts.count + photos.count + files.count + locations.count
    }
}

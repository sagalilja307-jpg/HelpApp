import Foundation
import SwiftData
import Contacts

/// Coordinates Stage 2 source indexing (Contacts, Photos, Files, Locations)
/// Owns ModelContext lifecycle - creates fresh context per operation
@MainActor
final class IndexingCoordinator {
    
    private let memoryService: MemoryService
    private let contactsCollector: ContactsCollectorService
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationCollector: LocationCollectorService
    private let locationSnapshotService: LocationSnapshotService
    private let checkpointStore: Etapp2IngestCheckpointStore
    
    init(
        memoryService: MemoryService,
        sourceConnectionStore: SourceConnectionStore,
        fileTextExtraction: FileTextExtractionService
    ) {
        self.memoryService = memoryService
        self.contactsCollector = ContactsCollectorService()
        self.photosIndexService = PhotosIndexService(sourceConnectionStore: sourceConnectionStore)
        self.filesImportService = FilesImportService(
            fileTextExtraction: fileTextExtraction,
            sourceConnectionStore: sourceConnectionStore
        )
        self.locationSnapshotService = LocationSnapshotService()
        self.locationCollector = LocationCollectorService(locationSnapshot: locationSnapshotService)
        self.checkpointStore = Etapp2IngestCheckpointStore()
    }
    
    // MARK: - Contacts
    
    func indexContacts() async throws -> Int {
        let context = memoryService.context()
        return try await contactsCollector.indexAllContacts(in: context)
    }
    
    func fetchIndexedContact(identifier: String) throws -> IndexedContact? {
        let context = memoryService.context()
        return try contactsCollector.fetchIndexedContact(identifier: identifier, in: context)
    }
    
    func searchContactsByName(_ searchText: String) throws -> [IndexedContact] {
        let context = memoryService.context()
        return try contactsCollector.searchContactsByName(searchText, in: context)
    }
    
    // MARK: - Photos
    
    func indexAllPhotos() async throws -> Int {
        let context = memoryService.context()
        return try await photosIndexService.indexAllPhotos(in: context)
    }
    
    func indexRecentPhotos(since date: Date) async throws -> Int {
        let context = memoryService.context()
        return try await photosIndexService.indexRecentPhotos(since: date, in: context)
    }
    
    func fetchIndexedPhoto(localIdentifier: String) throws -> IndexedPhotoAsset? {
        let context = memoryService.context()
        return try photosIndexService.fetchIndexedPhoto(localIdentifier: localIdentifier, in: context)
    }
    
    func searchPhotosByOCR(_ searchText: String) throws -> [IndexedPhotoAsset] {
        let context = memoryService.context()
        return try photosIndexService.searchPhotosByOCR(searchText, in: context)
    }
    
    // MARK: - Files
    
    func importFile(at url: URL) async throws -> IndexedFileDocument {
        let context = memoryService.context()
        return try await filesImportService.importFile(at: url, in: context)
    }
    
    func fetchIndexedFile(identifier: String) throws -> IndexedFileDocument? {
        let context = memoryService.context()
        return try filesImportService.fetchIndexedFile(identifier: identifier, in: context)
    }
    
    func searchFilesByContent(_ searchText: String) throws -> [IndexedFileDocument] {
        let context = memoryService.context()
        return try filesImportService.searchFilesByContent(searchText, in: context)
    }
    
    // MARK: - Locations
    
    func captureCurrentLocation() async throws -> IndexedLocationSnapshot {
        let context = memoryService.context()
        return try await locationCollector.captureCurrentLocation(in: context)
    }
    
    func fetchRecentLocations(limit: Int = 50) throws -> [IndexedLocationSnapshot] {
        let context = memoryService.context()
        return try locationCollector.fetchRecentLocations(limit: limit, in: context)
    }
    
    func searchLocationsByName(_ searchText: String) throws -> [IndexedLocationSnapshot] {
        let context = memoryService.context()
        return try locationCollector.searchLocationsByName(searchText, in: context)
    }
    
    // MARK: - Checkpoints
    
    func getLastIngestTimestamp(source: String) throws -> Date? {
        let context = memoryService.context()
        return try checkpointStore.getLastIngestTimestamp(source: source, in: context)
    }
    
    func updateIngestCheckpoint(source: String, timestamp: Date) throws {
        let context = memoryService.context()
        try checkpointStore.updateIngestCheckpoint(source: source, timestamp: timestamp, in: context)
    }
    
    func getAllCheckpoints() throws -> [Etapp2IngestCheckpoint] {
        let context = memoryService.context()
        return try checkpointStore.getAllCheckpoints(in: context)
    }
}

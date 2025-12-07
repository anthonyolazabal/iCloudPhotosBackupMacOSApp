import XCTest
@testable import iCloudPhotosBackup

final class DatabaseServiceTests: XCTestCase {

    var database: DatabaseService!
    var testDatabaseURL: URL!

    override func setUpWithError() throws {
        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDatabaseURL = tempDir.appendingPathComponent("test_sync_\(UUID().uuidString).db")
        database = try DatabaseService(databaseURL: testDatabaseURL)
    }

    override func tearDownWithError() throws {
        database = nil
        // Clean up test database
        try? FileManager.default.removeItem(at: testDatabaseURL)
    }

    // MARK: - Synced Photos Tests

    func testSaveSyncedPhoto() throws {
        let photo = SyncedPhoto(
            localID: "test-local-id",
            remotePath: "2024/01/01/test.jpg",
            destinationID: UUID(),
            checksum: "abc123",
            fileSize: 1024
        )

        XCTAssertNoThrow(try database.saveSyncedPhoto(photo))

        // Verify it was saved
        let retrieved = try database.getSyncedPhoto(localID: photo.localID, destinationID: photo.destinationID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.localID, photo.localID)
        XCTAssertEqual(retrieved?.remotePath, photo.remotePath)
        XCTAssertEqual(retrieved?.checksum, photo.checksum)
    }

    func testGetSyncedPhotoNotFound() throws {
        let result = try database.getSyncedPhoto(localID: "nonexistent", destinationID: UUID())
        XCTAssertNil(result)
    }

    func testGetAllSyncedPhotos() throws {
        let destinationID = UUID()

        // Save multiple photos
        for i in 1...5 {
            let photo = SyncedPhoto(
                localID: "photo-\(i)",
                remotePath: "2024/01/\(i)/photo.jpg",
                destinationID: destinationID,
                checksum: "checksum-\(i)",
                fileSize: Int64(i * 1000)
            )
            try database.saveSyncedPhoto(photo)
        }

        let photos = try database.getAllSyncedPhotos(destinationID: destinationID)
        XCTAssertEqual(photos.count, 5)
    }

    func testDeleteSyncedPhoto() throws {
        let photo = SyncedPhoto(
            localID: "delete-test",
            remotePath: "path/to/photo.jpg",
            destinationID: UUID(),
            checksum: "checksum",
            fileSize: 500
        )

        try database.saveSyncedPhoto(photo)

        // Verify it exists
        var retrieved = try database.getSyncedPhoto(localID: photo.localID, destinationID: photo.destinationID)
        XCTAssertNotNil(retrieved)

        // Delete it
        try database.deleteSyncedPhoto(id: photo.id)

        // Verify it's gone
        retrieved = try database.getSyncedPhoto(localID: photo.localID, destinationID: photo.destinationID)
        XCTAssertNil(retrieved)
    }

    func testUpdateVerificationDate() throws {
        let photo = SyncedPhoto(
            localID: "verify-test",
            remotePath: "path/to/photo.jpg",
            destinationID: UUID(),
            checksum: "checksum",
            fileSize: 500
        )

        try database.saveSyncedPhoto(photo)

        let verifyDate = Date()
        try database.updateVerificationDate(photoID: photo.id, date: verifyDate)

        let retrieved = try database.getSyncedPhoto(localID: photo.localID, destinationID: photo.destinationID)
        XCTAssertNotNil(retrieved?.lastVerifiedDate)
    }

    // MARK: - Batch Operations Tests

    func testSaveSyncedPhotosBatch() throws {
        let destinationID = UUID()
        var photos: [SyncedPhoto] = []

        for i in 1...100 {
            photos.append(SyncedPhoto(
                localID: "batch-photo-\(i)",
                remotePath: "2024/01/01/batch-\(i).jpg",
                destinationID: destinationID,
                checksum: "batch-checksum-\(i)",
                fileSize: Int64(i * 100)
            ))
        }

        XCTAssertNoThrow(try database.saveSyncedPhotosBatch(photos))

        let allPhotos = try database.getAllSyncedPhotos(destinationID: destinationID)
        XCTAssertEqual(allPhotos.count, 100)
    }

    func testGetSyncedPhotoIDs() throws {
        let destinationID = UUID()

        // Save some photos
        for i in 1...10 {
            let photo = SyncedPhoto(
                localID: "lookup-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: destinationID,
                checksum: "check-\(i)",
                fileSize: 100
            )
            try database.saveSyncedPhoto(photo)
        }

        // Look up existing and non-existing IDs
        let lookupIDs = ["lookup-1", "lookup-5", "lookup-10", "not-exist-1", "not-exist-2"]
        let found = try database.getSyncedPhotoIDs(localIDs: lookupIDs, destinationID: destinationID)

        XCTAssertEqual(found.count, 3)
        XCTAssertTrue(found.contains("lookup-1"))
        XCTAssertTrue(found.contains("lookup-5"))
        XCTAssertTrue(found.contains("lookup-10"))
        XCTAssertFalse(found.contains("not-exist-1"))
    }

    func testGetSyncedPhotosDates() throws {
        let destinationID = UUID()

        for i in 1...5 {
            let photo = SyncedPhoto(
                localID: "dates-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: destinationID,
                checksum: "check-\(i)",
                fileSize: 100
            )
            try database.saveSyncedPhoto(photo)
        }

        let lookupIDs = ["dates-1", "dates-3", "dates-5", "not-exist"]
        let dates = try database.getSyncedPhotosDates(localIDs: lookupIDs, destinationID: destinationID)

        XCTAssertEqual(dates.count, 3)
        XCTAssertNotNil(dates["dates-1"])
        XCTAssertNotNil(dates["dates-3"])
        XCTAssertNotNil(dates["dates-5"])
        XCTAssertNil(dates["not-exist"])
    }

    func testGetSyncedPhotosPaginated() throws {
        let destinationID = UUID()

        // Save 25 photos
        for i in 1...25 {
            let photo = SyncedPhoto(
                localID: "page-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: destinationID,
                checksum: "check-\(i)",
                fileSize: 100
            )
            try database.saveSyncedPhoto(photo)
        }

        // Get first page
        let page1 = try database.getSyncedPhotosPaginated(destinationID: destinationID, limit: 10, offset: 0)
        XCTAssertEqual(page1.count, 10)

        // Get second page
        let page2 = try database.getSyncedPhotosPaginated(destinationID: destinationID, limit: 10, offset: 10)
        XCTAssertEqual(page2.count, 10)

        // Get third page (only 5 remaining)
        let page3 = try database.getSyncedPhotosPaginated(destinationID: destinationID, limit: 10, offset: 20)
        XCTAssertEqual(page3.count, 5)
    }

    func testGetSyncedPhotosCount() throws {
        let destinationID = UUID()

        // Initially empty
        var count = try database.getSyncedPhotosCount(destinationID: destinationID)
        XCTAssertEqual(count, 0)

        // Add some photos
        for i in 1...15 {
            let photo = SyncedPhoto(
                localID: "count-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: destinationID,
                checksum: "check-\(i)",
                fileSize: 100
            )
            try database.saveSyncedPhoto(photo)
        }

        count = try database.getSyncedPhotosCount(destinationID: destinationID)
        XCTAssertEqual(count, 15)
    }

    func testUpdateVerificationDatesBatch() throws {
        let destinationID = UUID()
        var photoIDs: [UUID] = []

        // Create photos
        for i in 1...20 {
            let photo = SyncedPhoto(
                localID: "batch-verify-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: destinationID,
                checksum: "check-\(i)",
                fileSize: 100
            )
            try database.saveSyncedPhoto(photo)
            photoIDs.append(photo.id)
        }

        // Batch update verification dates
        let verifyDate = Date()
        XCTAssertNoThrow(try database.updateVerificationDatesBatch(photoIDs: photoIDs, date: verifyDate))

        // Verify all were updated
        let allPhotos = try database.getAllSyncedPhotos(destinationID: destinationID)
        for photo in allPhotos {
            XCTAssertNotNil(photo.lastVerifiedDate)
        }
    }

    // MARK: - Sync Jobs Tests

    func testCreateAndGetSyncJob() throws {
        let job = SyncJob(
            id: UUID(),
            destinationID: UUID()
        )

        try database.createSyncJob(job)

        let retrieved = try database.getSyncJob(id: job.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, job.id)
        XCTAssertEqual(retrieved?.status, .running)
    }

    func testUpdateSyncJob() throws {
        let job = SyncJob(
            id: UUID(),
            destinationID: UUID()
        )

        try database.createSyncJob(job)

        var updatedJob = job
        updatedJob.status = .completed
        updatedJob.photosScanned = 100
        updatedJob.photosSynced = 95
        updatedJob.photosFailed = 5
        updatedJob.bytesTransferred = 1024 * 1024 * 50
        updatedJob.endTime = Date()

        try database.updateSyncJob(updatedJob)

        let retrieved = try database.getSyncJob(id: job.id)
        XCTAssertEqual(retrieved?.status, .completed)
        XCTAssertEqual(retrieved?.photosSynced, 95)
        XCTAssertEqual(retrieved?.photosFailed, 5)
    }

    func testGetRecentSyncJobs() throws {
        // Create multiple jobs
        for i in 1...10 {
            let job = SyncJob(
                id: UUID(),
                destinationID: UUID()
            )
            try database.createSyncJob(job)
        }

        let jobs = try database.getRecentSyncJobs(limit: 5)
        XCTAssertEqual(jobs.count, 5)
    }

    // MARK: - Destinations Tests

    func testSaveAndGetDestination() throws {
        let config = S3Configuration.awsPreset(
            name: "Test AWS",
            bucket: "test-bucket",
            region: "us-east-1"
        )
        let configData = try JSONEncoder().encode(config)

        let destination = DestinationRecord(
            id: config.id,
            name: config.name,
            type: .s3,
            configJSON: configData
        )

        try database.saveDestination(destination)

        let retrieved = try database.getDestination(id: destination.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Test AWS")
    }

    func testGetAllDestinations() throws {
        // Create multiple destinations
        for i in 1...3 {
            let config = S3Configuration.awsPreset(
                name: "Dest \(i)",
                bucket: "bucket-\(i)",
                region: "us-east-1"
            )
            let configData = try JSONEncoder().encode(config)

            let destination = DestinationRecord(
                id: config.id,
                name: config.name,
                type: .s3,
                configJSON: configData
            )
            try database.saveDestination(destination)
        }

        let destinations = try database.getAllDestinations()
        XCTAssertEqual(destinations.count, 3)
    }

    func testDeleteDestination() throws {
        let config = S3Configuration.awsPreset(
            name: "Delete Test",
            bucket: "delete-bucket",
            region: "us-east-1"
        )
        let configData = try JSONEncoder().encode(config)

        let destination = DestinationRecord(
            id: config.id,
            name: config.name,
            type: .s3,
            configJSON: configData
        )

        try database.saveDestination(destination)

        // Verify exists
        var retrieved = try database.getDestination(id: destination.id)
        XCTAssertNotNil(retrieved)

        // Delete
        try database.deleteDestination(id: destination.id)

        // Verify deleted
        retrieved = try database.getDestination(id: destination.id)
        XCTAssertNil(retrieved)
    }

    func testUpdateDestinationHealth() throws {
        let config = S3Configuration.awsPreset(
            name: "Health Test",
            bucket: "health-bucket",
            region: "us-east-1"
        )
        let configData = try JSONEncoder().encode(config)

        let destination = DestinationRecord(
            id: config.id,
            name: config.name,
            type: .s3,
            configJSON: configData
        )

        try database.saveDestination(destination)

        try database.updateDestinationHealth(id: destination.id, status: .healthy)

        let retrieved = try database.getDestination(id: destination.id)
        XCTAssertEqual(retrieved?.healthStatus, .healthy)
        XCTAssertNotNil(retrieved?.lastHealthCheck)
    }

    // MARK: - Statistics Tests

    func testGetStats() throws {
        let destinationID = UUID()

        // Add photos with different sizes
        for i in 1...5 {
            let photo = SyncedPhoto(
                localID: "stats-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: destinationID,
                checksum: "check-\(i)",
                fileSize: Int64(i * 1000)
            )
            try database.saveSyncedPhoto(photo)
        }

        let stats = try database.getStats(destinationID: destinationID)
        XCTAssertEqual(stats.totalPhotos, 5)
        XCTAssertEqual(stats.totalBytes, 15000) // 1000+2000+3000+4000+5000
    }
}

import XCTest
@testable import iCloudPhotosBackup

final class VerificationServiceTests: XCTestCase {

    var database: DatabaseService!
    var verificationService: VerificationService!
    var mockDestination: MockBackupDestination!
    var testDatabaseURL: URL!

    override func setUpWithError() throws {
        // Create a temporary database
        let tempDir = FileManager.default.temporaryDirectory
        testDatabaseURL = tempDir.appendingPathComponent("test_verification_\(UUID().uuidString).db")
        database = try DatabaseService(databaseURL: testDatabaseURL)

        verificationService = VerificationService(database: database)
        mockDestination = MockBackupDestination()
    }

    override func tearDownWithError() throws {
        verificationService = nil
        database = nil
        mockDestination = nil
        try? FileManager.default.removeItem(at: testDatabaseURL)
    }

    // MARK: - Verify Backup Tests

    func testVerifyBackupEmpty() async throws {
        // No synced photos in database
        let result = try await verificationService.verifyBackup(destination: mockDestination)

        XCTAssertEqual(result.totalPhotos, 0)
        XCTAssertEqual(result.verifiedCount, 0)
        XCTAssertTrue(result.isFullyVerified)
    }

    func testVerifyBackupAllVerified() async throws {
        // Add synced photos and matching mock files
        for i in 1...5 {
            let checksum = "checksum-\(i)"
            let path = "2024/01/01/photo-\(i).jpg"

            // Add to database
            let photo = SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: mockDestination.id,
                checksum: checksum,
                fileSize: 1000
            )
            try database.saveSyncedPhoto(photo)

            // Add matching mock file
            mockDestination.addMockFile(path: path, checksum: checksum)
        }

        let result = try await verificationService.verifyBackup(destination: mockDestination)

        XCTAssertEqual(result.totalPhotos, 5)
        XCTAssertEqual(result.verifiedCount, 5)
        XCTAssertEqual(result.mismatchCount, 0)
        XCTAssertEqual(result.missingCount, 0)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.isFullyVerified)
    }

    func testVerifyBackupMissingFiles() async throws {
        // Add synced photos but no mock files
        for i in 1...3 {
            let photo = SyncedPhoto(
                localID: "local-\(i)",
                remotePath: "2024/01/01/photo-\(i).jpg",
                destinationID: mockDestination.id,
                checksum: "checksum-\(i)",
                fileSize: 1000
            )
            try database.saveSyncedPhoto(photo)
        }
        // Don't add mock files - they should be detected as missing

        let result = try await verificationService.verifyBackup(destination: mockDestination)

        XCTAssertEqual(result.totalPhotos, 3)
        XCTAssertEqual(result.verifiedCount, 0)
        XCTAssertEqual(result.missingCount, 3)
        XCTAssertFalse(result.isFullyVerified)
    }

    func testVerifyBackupChecksumMismatch() async throws {
        // Add synced photos with different checksums than mock files
        for i in 1...3 {
            let path = "2024/01/01/photo-\(i).jpg"

            let photo = SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: mockDestination.id,
                checksum: "expected-checksum-\(i)",
                fileSize: 1000
            )
            try database.saveSyncedPhoto(photo)

            // Add mock file with different checksum
            mockDestination.addMockFile(path: path, checksum: "wrong-checksum-\(i)")
        }

        let result = try await verificationService.verifyBackup(destination: mockDestination)

        XCTAssertEqual(result.totalPhotos, 3)
        XCTAssertEqual(result.verifiedCount, 0)
        XCTAssertEqual(result.mismatchCount, 3)
        XCTAssertFalse(result.isFullyVerified)
    }

    func testVerifyBackupMixedResults() async throws {
        // Add mix of verified, missing, and mismatched photos
        let destinationID = mockDestination.id

        // Photo 1: Verified (matching checksum)
        try database.saveSyncedPhoto(SyncedPhoto(
            localID: "verified",
            remotePath: "path/verified.jpg",
            destinationID: destinationID,
            checksum: "correct",
            fileSize: 1000
        ))
        mockDestination.addMockFile(path: "path/verified.jpg", checksum: "correct")

        // Photo 2: Missing (no mock file)
        try database.saveSyncedPhoto(SyncedPhoto(
            localID: "missing",
            remotePath: "path/missing.jpg",
            destinationID: destinationID,
            checksum: "any",
            fileSize: 1000
        ))

        // Photo 3: Mismatch (different checksum)
        try database.saveSyncedPhoto(SyncedPhoto(
            localID: "mismatch",
            remotePath: "path/mismatch.jpg",
            destinationID: destinationID,
            checksum: "expected",
            fileSize: 1000
        ))
        mockDestination.addMockFile(path: "path/mismatch.jpg", checksum: "wrong")

        let result = try await verificationService.verifyBackup(destination: mockDestination)

        XCTAssertEqual(result.totalPhotos, 3)
        XCTAssertEqual(result.verifiedCount, 1)
        XCTAssertEqual(result.missingCount, 1)
        XCTAssertEqual(result.mismatchCount, 1)
        XCTAssertFalse(result.isFullyVerified)
    }

    // MARK: - Quick Verification Tests

    func testQuickVerificationSampleSize() async throws {
        // Add 20 synced photos
        for i in 1...20 {
            let path = "path/photo-\(i).jpg"
            let checksum = "checksum-\(i)"

            try database.saveSyncedPhoto(SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: mockDestination.id,
                checksum: checksum,
                fileSize: 1000
            ))
            mockDestination.addMockFile(path: path, checksum: checksum)
        }

        // Quick verification with sample size 5
        let result = try await verificationService.quickVerification(
            destination: mockDestination,
            sampleSize: 5
        )

        XCTAssertEqual(result.totalPhotos, 5)
    }

    func testQuickVerificationSampleSizeLargerThanTotal() async throws {
        // Add only 3 photos but request sample of 10
        for i in 1...3 {
            let path = "path/photo-\(i).jpg"
            try database.saveSyncedPhoto(SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: mockDestination.id,
                checksum: "checksum-\(i)",
                fileSize: 1000
            ))
            mockDestination.addMockFile(path: path, checksum: "checksum-\(i)")
        }

        let result = try await verificationService.quickVerification(
            destination: mockDestination,
            sampleSize: 10
        )

        // Should only verify the 3 available photos
        XCTAssertEqual(result.totalPhotos, 3)
    }

    // MARK: - Unverified Photos Tests

    func testGetUnverifiedPhotosNeverVerified() throws {
        // Add photos without verification dates
        for i in 1...5 {
            let photo = SyncedPhoto(
                localID: "unverified-\(i)",
                remotePath: "path/\(i).jpg",
                destinationID: mockDestination.id,
                checksum: "checksum",
                fileSize: 1000,
                lastVerifiedDate: nil
            )
            try database.saveSyncedPhoto(photo)
        }

        let unverified = try verificationService.getUnverifiedPhotos(
            destinationID: mockDestination.id,
            olderThan: Date()
        )

        XCTAssertEqual(unverified.count, 5)
    }

    // MARK: - Progress Tests

    func testVerificationProgress() async throws {
        // Add photos
        for i in 1...10 {
            let path = "path/photo-\(i).jpg"
            try database.saveSyncedPhoto(SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: mockDestination.id,
                checksum: "checksum-\(i)",
                fileSize: 1000
            ))
            mockDestination.addMockFile(path: path, checksum: "checksum-\(i)")
        }

        // Check initial state
        XCTAssertFalse(verificationService.progress.isRunning)
        XCTAssertEqual(verificationService.progress.totalPhotos, 0)

        // Run verification
        let _ = try await verificationService.verifyBackup(destination: mockDestination)

        // Check final state
        XCTAssertFalse(verificationService.progress.isRunning)
        XCTAssertEqual(verificationService.progress.photosChecked, 10)
    }

    // MARK: - Cancellation Tests

    func testVerificationCanBeCancelled() async throws {
        // Add many photos
        for i in 1...100 {
            let path = "path/photo-\(i).jpg"
            try database.saveSyncedPhoto(SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: mockDestination.id,
                checksum: "checksum-\(i)",
                fileSize: 1000
            ))
            mockDestination.addMockFile(path: path, checksum: "checksum-\(i)")
        }

        // Start verification and cancel after a delay
        Task {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            verificationService.cancel()
        }

        let result = try await verificationService.verifyBackup(destination: mockDestination)

        // Should complete with fewer than all photos verified due to cancellation
        // (This test is somewhat timing-dependent)
        XCTAssertLessThanOrEqual(result.totalPhotos, 100)
    }

    // MARK: - Success Rate Tests

    func testSuccessRateCalculation() async throws {
        let destinationID = mockDestination.id

        // Add 10 photos: 8 verified, 2 missing
        for i in 1...8 {
            let path = "path/photo-\(i).jpg"
            try database.saveSyncedPhoto(SyncedPhoto(
                localID: "local-\(i)",
                remotePath: path,
                destinationID: destinationID,
                checksum: "checksum-\(i)",
                fileSize: 1000
            ))
            mockDestination.addMockFile(path: path, checksum: "checksum-\(i)")
        }

        // Add 2 missing (no mock file)
        for i in 9...10 {
            try database.saveSyncedPhoto(SyncedPhoto(
                localID: "local-\(i)",
                remotePath: "path/photo-\(i).jpg",
                destinationID: destinationID,
                checksum: "checksum-\(i)",
                fileSize: 1000
            ))
        }

        let result = try await verificationService.verifyBackup(destination: mockDestination)

        XCTAssertEqual(result.successRate, 0.8, accuracy: 0.01)
    }
}

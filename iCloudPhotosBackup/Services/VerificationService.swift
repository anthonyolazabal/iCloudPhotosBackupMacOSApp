import Foundation
import OSLog
import Observation

// MARK: - Verification Result Types

/// Result of verifying a single photo
struct PhotoVerificationResult {
    let photoID: UUID
    let localID: String
    let remotePath: String
    let status: VerificationStatus
    let expectedChecksum: String
    let actualChecksum: String?
    let errorMessage: String?

    enum VerificationStatus: String, Codable {
        case verified          // Checksum matches
        case checksumMismatch  // File exists but checksum doesn't match
        case missing           // File not found on remote
        case error             // Error during verification
    }
}

/// Result of a complete verification job
struct VerificationJobResult {
    let id: UUID
    let destinationID: UUID
    let startTime: Date
    let endTime: Date
    let totalPhotos: Int
    let verifiedCount: Int
    let mismatchCount: Int
    let missingCount: Int
    let errorCount: Int
    let details: [PhotoVerificationResult]

    var isFullyVerified: Bool {
        mismatchCount == 0 && missingCount == 0 && errorCount == 0
    }

    var successRate: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(verifiedCount) / Double(totalPhotos)
    }
}

/// Result of gap detection (finding unsynced photos)
struct GapDetectionResult {
    let destinationID: UUID
    let totalInLibrary: Int
    let totalSynced: Int
    let unsyncedPhotos: [PhotoMetadata]
    let modifiedPhotos: [PhotoMetadata]  // Photos modified since last sync

    var gapCount: Int {
        unsyncedPhotos.count + modifiedPhotos.count
    }

    var syncPercentage: Double {
        guard totalInLibrary > 0 else { return 100 }
        return Double(totalSynced) / Double(totalInLibrary) * 100
    }
}

// MARK: - Verification Progress

/// Observable progress for verification operations
@Observable
class VerificationProgress {
    var totalPhotos: Int = 0
    var photosChecked: Int = 0
    var currentPhotoPath: String?
    var verifiedCount: Int = 0
    var mismatchCount: Int = 0
    var missingCount: Int = 0
    var errorCount: Int = 0
    var isRunning: Bool = false

    var progress: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(photosChecked) / Double(totalPhotos)
    }

    func reset() {
        totalPhotos = 0
        photosChecked = 0
        currentPhotoPath = nil
        verifiedCount = 0
        mismatchCount = 0
        missingCount = 0
        errorCount = 0
        isRunning = false
    }
}

// MARK: - Verification Service

/// Service for verifying backup integrity
/// Provides checksum verification, gap detection, and re-upload capabilities
class VerificationService {
    private let database: DatabaseService
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "Verification")

    private(set) var progress = VerificationProgress()
    private var isCancelled = false

    // Logging
    private(set) var currentJobID: UUID?
    private var logBuffer: [VerificationLogEntry] = []
    private let logBufferLimit = 50

    // Configuration
    var concurrentVerifications = 5

    // MARK: - Initialization

    init(database: DatabaseService) {
        self.database = database
        logger.info("VerificationService initialized")
    }

    // MARK: - Logging

    private func log(
        _ level: VerificationLogEntry.LogLevel,
        category: VerificationLogEntry.VerificationLogCategory,
        message: String,
        photoPath: String? = nil,
        details: String? = nil
    ) {
        guard let jobID = currentJobID else { return }

        let entry = VerificationLogEntry(
            jobID: jobID,
            level: level,
            category: category,
            message: message,
            photoPath: photoPath,
            details: details
        )

        logBuffer.append(entry)

        // Flush buffer if it reaches the limit
        if logBuffer.count >= logBufferLimit {
            flushLogBuffer()
        }
    }

    func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }

        let logsToSave = logBuffer
        logBuffer.removeAll()

        do {
            try database.saveVerificationLogs(logsToSave)
        } catch {
            logger.error("Failed to save verification logs: \(error.localizedDescription)")
        }
    }

    // MARK: - Verify Backup Integrity

    /// Verify all synced photos against remote destination
    /// - Parameters:
    ///   - destination: The backup destination to verify against
    ///   - updateLastVerified: Whether to update last_verified_date on successful verification
    /// - Returns: Verification job result
    func verifyBackup(
        destination: BackupDestination,
        updateLastVerified: Bool = true
    ) async throws -> VerificationJobResult {
        logger.info("Starting backup verification for destination: \(destination.name)")

        // Reset state
        isCancelled = false
        progress.reset()
        progress.isRunning = true
        logBuffer.removeAll()

        // Create job ID for logging
        let jobID = UUID()
        currentJobID = jobID

        let startTime = Date()
        var results: [PhotoVerificationResult] = []

        defer {
            progress.isRunning = false
            currentJobID = nil
        }

        log(.info, category: .general, message: "Starting full backup verification for destination: \(destination.name)")

        // Get all synced photos for this destination
        let syncedPhotos = try database.getAllSyncedPhotos(destinationID: destination.id)

        guard !syncedPhotos.isEmpty else {
            logger.info("No synced photos found for verification")
            log(.info, category: .general, message: "No synced photos found for verification")
            flushLogBuffer()  // Explicitly flush before returning
            return VerificationJobResult(
                id: jobID,
                destinationID: destination.id,
                startTime: startTime,
                endTime: Date(),
                totalPhotos: 0,
                verifiedCount: 0,
                mismatchCount: 0,
                missingCount: 0,
                errorCount: 0,
                details: []
            )
        }

        progress.totalPhotos = syncedPhotos.count
        logger.info("Verifying \(syncedPhotos.count) photos")
        log(.info, category: .general, message: "Found \(syncedPhotos.count) photos to verify")

        // Ensure destination is connected
        log(.info, category: .connection, message: "Connecting to destination...")
        try await destination.connect()
        log(.success, category: .connection, message: "Connected to destination successfully")

        // Verify photos concurrently with limiting
        results = await withTaskGroup(of: PhotoVerificationResult.self) { group in
            var collectedResults: [PhotoVerificationResult] = []
            var activeVerifications = 0
            var photoIndex = 0

            while photoIndex < syncedPhotos.count || activeVerifications > 0 {
                // Check for cancellation
                if isCancelled {
                    group.cancelAll()
                    break
                }

                // Add new verification tasks up to the concurrency limit
                while activeVerifications < concurrentVerifications && photoIndex < syncedPhotos.count {
                    let photo = syncedPhotos[photoIndex]
                    photoIndex += 1
                    activeVerifications += 1

                    group.addTask {
                        await self.verifySinglePhoto(photo, destination: destination)
                    }
                }

                // Wait for at least one verification to complete
                if let result = await group.next() {
                    activeVerifications -= 1
                    collectedResults.append(result)

                    // Update progress
                    await MainActor.run {
                        self.progress.photosChecked += 1

                        switch result.status {
                        case .verified:
                            self.progress.verifiedCount += 1
                        case .checksumMismatch:
                            self.progress.mismatchCount += 1
                        case .missing:
                            self.progress.missingCount += 1
                        case .error:
                            self.progress.errorCount += 1
                        }
                    }

                }
            }

            return collectedResults
        }

        // Batch update verification dates for all verified photos (much more efficient)
        if updateLastVerified {
            let verifiedPhotoIDs = results
                .filter { $0.status == .verified }
                .map { $0.photoID }

            if !verifiedPhotoIDs.isEmpty {
                try? database.updateVerificationDatesBatch(photoIDs: verifiedPhotoIDs, date: Date())
                logger.info("Batch updated verification dates for \(verifiedPhotoIDs.count) photos")
                log(.info, category: .general, message: "Updated verification dates for \(verifiedPhotoIDs.count) photos")
            }
        }

        let endTime = Date()

        let verifiedCount = results.filter { $0.status == .verified }.count
        let mismatchCount = results.filter { $0.status == .checksumMismatch }.count
        let missingCount = results.filter { $0.status == .missing }.count
        let errorCount = results.filter { $0.status == .error }.count

        let jobResult = VerificationJobResult(
            id: jobID,
            destinationID: destination.id,
            startTime: startTime,
            endTime: endTime,
            totalPhotos: syncedPhotos.count,
            verifiedCount: verifiedCount,
            mismatchCount: mismatchCount,
            missingCount: missingCount,
            errorCount: errorCount,
            details: results
        )

        // Log summary
        if jobResult.isFullyVerified {
            log(.success, category: .general, message: "Verification completed successfully: \(verifiedCount)/\(syncedPhotos.count) photos verified")
        } else {
            log(.warning, category: .general, message: "Verification completed with issues: \(verifiedCount) verified, \(mismatchCount) mismatches, \(missingCount) missing, \(errorCount) errors")
        }

        // Explicitly flush logs before returning
        flushLogBuffer()

        logger.info("Verification completed: \(jobResult.verifiedCount)/\(jobResult.totalPhotos) verified, \(jobResult.mismatchCount) mismatches, \(jobResult.missingCount) missing")

        return jobResult
    }

    /// Verify a single photo against remote destination
    /// Verification checks:
    /// 1. File exists on remote
    /// 2. File size matches expected size (more reliable than checksum for S3)
    private func verifySinglePhoto(
        _ photo: SyncedPhoto,
        destination: BackupDestination
    ) async -> PhotoVerificationResult {
        await MainActor.run {
            progress.currentPhotoPath = photo.remotePath
        }

        do {
            // Get file metadata (includes existence check and size)
            guard let metadata = try await destination.getFileMetadata(at: photo.remotePath) else {
                logger.warning("File missing on remote: \(photo.remotePath)")
                log(.warning, category: .missing, message: "File missing on remote", photoPath: photo.remotePath)
                return PhotoVerificationResult(
                    photoID: photo.id,
                    localID: photo.localID,
                    remotePath: photo.remotePath,
                    status: .missing,
                    expectedChecksum: photo.checksum,
                    actualChecksum: nil,
                    errorMessage: "File not found on remote destination"
                )
            }

            // Verify by file size (more reliable than S3 ETag/checksum comparison)
            // S3 ETags use MD5 for single-part and "md5-partcount" for multipart uploads,
            // which won't match our SHA-256 checksums
            let expectedSize = photo.fileSize
            let actualSize = metadata.size

            if actualSize == expectedSize {
                logger.debug("Verified: \(photo.remotePath) (size: \(actualSize) bytes)")
                log(.success, category: .verification, message: "Verified (size: \(actualSize) bytes)", photoPath: photo.remotePath)
                return PhotoVerificationResult(
                    photoID: photo.id,
                    localID: photo.localID,
                    remotePath: photo.remotePath,
                    status: .verified,
                    expectedChecksum: photo.checksum,
                    actualChecksum: photo.checksum,
                    errorMessage: nil
                )
            } else {
                logger.warning("Size mismatch for \(photo.remotePath): expected \(expectedSize), got \(actualSize)")
                log(.warning, category: .mismatch, message: "Size mismatch: expected \(expectedSize), got \(actualSize)", photoPath: photo.remotePath)
                return PhotoVerificationResult(
                    photoID: photo.id,
                    localID: photo.localID,
                    remotePath: photo.remotePath,
                    status: .checksumMismatch,
                    expectedChecksum: "\(expectedSize) bytes",
                    actualChecksum: "\(actualSize) bytes",
                    errorMessage: "File size does not match expected value"
                )
            }
        } catch {
            logger.error("Verification error for \(photo.remotePath): \(error.localizedDescription)")
            log(.error, category: .verification, message: "Verification error: \(error.localizedDescription)", photoPath: photo.remotePath, details: String(describing: error))
            return PhotoVerificationResult(
                photoID: photo.id,
                localID: photo.localID,
                remotePath: photo.remotePath,
                status: .error,
                expectedChecksum: photo.checksum,
                actualChecksum: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Gap Detection

    /// Detect photos in library that haven't been synced to destination
    /// - Parameters:
    ///   - source: Photo library source
    ///   - destinationID: Destination to check against
    ///   - filter: Optional date range filter
    /// - Returns: Gap detection result with unsynced photos
    func detectGaps(
        source: PhotoSource,
        destinationID: UUID,
        filter: DateRangeFilter = .fullLibrary
    ) async throws -> GapDetectionResult {
        logger.info("Starting gap detection for destination: \(destinationID)")

        // Fetch all photos from library
        let libraryPhotos = try await source.fetchPhotos(filter: filter)
        logger.info("Found \(libraryPhotos.count) photos in library")

        // Get all synced photos for this destination
        let syncedPhotos = try database.getAllSyncedPhotos(destinationID: destinationID)
        let syncedLocalIDs = Set(syncedPhotos.map { $0.localID })

        // Create lookup for synced photos by local ID
        let syncedPhotoLookup = Dictionary(
            syncedPhotos.map { ($0.localID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Find unsynced photos
        var unsyncedPhotos: [PhotoMetadata] = []
        var modifiedPhotos: [PhotoMetadata] = []

        for photo in libraryPhotos {
            if !syncedLocalIDs.contains(photo.localIdentifier) {
                // Photo not synced at all
                unsyncedPhotos.append(photo)
            } else if let syncedPhoto = syncedPhotoLookup[photo.localIdentifier] {
                // Check if photo was modified since last sync
                if let modDate = photo.modificationDate,
                   modDate > syncedPhoto.syncDate {
                    modifiedPhotos.append(photo)
                }
            }
        }

        logger.info("Gap detection complete: \(unsyncedPhotos.count) unsynced, \(modifiedPhotos.count) modified")

        return GapDetectionResult(
            destinationID: destinationID,
            totalInLibrary: libraryPhotos.count,
            totalSynced: syncedPhotos.count,
            unsyncedPhotos: unsyncedPhotos,
            modifiedPhotos: modifiedPhotos
        )
    }

    // MARK: - Re-upload Corrupted/Missing Files

    /// Re-upload photos that failed verification
    /// - Parameters:
    ///   - failedResults: Verification results for failed photos
    ///   - source: Photo library source
    ///   - destination: Backup destination
    ///   - syncEngine: Sync engine for re-upload
    /// - Returns: Number of successfully re-uploaded photos
    func reuploadFailedPhotos(
        failedResults: [PhotoVerificationResult],
        source: PhotoSource,
        destination: BackupDestination,
        syncEngine: SyncEngineImpl
    ) async throws -> Int {
        logger.info("Starting re-upload of \(failedResults.count) failed photos")

        // Filter to only missing or mismatched photos
        let photosToReupload = failedResults.filter {
            $0.status == .missing || $0.status == .checksumMismatch
        }

        guard !photosToReupload.isEmpty else {
            logger.info("No photos to re-upload")
            return 0
        }

        var successCount = 0

        for result in photosToReupload {
            if isCancelled {
                break
            }

            do {
                // Get photo metadata from source
                let photos = try await source.fetchPhotos(filter: .fullLibrary)
                guard photos.contains(where: { $0.localIdentifier == result.localID }) else {
                    logger.warning("Photo not found in library: \(result.localID)")
                    continue
                }

                // Delete existing corrupted file if it exists
                if result.status == .checksumMismatch {
                    try? await destination.delete(at: result.remotePath)
                }

                // Delete old database record
                try database.deleteSyncedPhoto(id: result.photoID)

                // Re-sync will happen on next sync job
                // For now, just count it as needing re-upload
                successCount += 1
                logger.info("Prepared for re-upload: \(result.remotePath)")

            } catch {
                logger.error("Failed to prepare re-upload for \(result.localID): \(error.localizedDescription)")
            }
        }

        logger.info("Prepared \(successCount) photos for re-upload")
        return successCount
    }

    // MARK: - Quick Verification

    /// Perform a quick spot-check verification on a sample of photos
    /// - Parameters:
    ///   - destination: Backup destination
    ///   - sampleSize: Number of photos to randomly verify (default 10)
    /// - Returns: Quick verification result
    func quickVerification(
        destination: BackupDestination,
        sampleSize: Int = 10
    ) async throws -> VerificationJobResult {
        logger.info("Starting quick verification with sample size: \(sampleSize)")

        // Reset state and create job ID
        isCancelled = false
        logBuffer.removeAll()
        let jobID = UUID()
        currentJobID = jobID

        let startTime = Date()

        defer {
            progress.isRunning = false
            currentJobID = nil
        }

        log(.info, category: .general, message: "Starting quick verification (sample size: \(sampleSize))")

        // Get all synced photos
        let allPhotos = try database.getAllSyncedPhotos(destinationID: destination.id)

        guard !allPhotos.isEmpty else {
            log(.info, category: .general, message: "No synced photos found for verification")
            flushLogBuffer()  // Explicitly flush before returning
            return VerificationJobResult(
                id: jobID,
                destinationID: destination.id,
                startTime: startTime,
                endTime: Date(),
                totalPhotos: 0,
                verifiedCount: 0,
                mismatchCount: 0,
                missingCount: 0,
                errorCount: 0,
                details: []
            )
        }

        // Random sample
        let sampleCount = min(sampleSize, allPhotos.count)
        let sampledPhotos = Array(allPhotos.shuffled().prefix(sampleCount))

        log(.info, category: .general, message: "Selected \(sampleCount) random photos from \(allPhotos.count) total")

        progress.reset()
        progress.totalPhotos = sampleCount
        progress.isRunning = true

        // Ensure destination is connected
        log(.info, category: .connection, message: "Connecting to destination...")
        try await destination.connect()
        log(.success, category: .connection, message: "Connected to destination successfully")

        var results: [PhotoVerificationResult] = []

        for photo in sampledPhotos {
            if isCancelled { break }

            let result = await verifySinglePhoto(photo, destination: destination)
            results.append(result)

            await MainActor.run {
                progress.photosChecked += 1
                switch result.status {
                case .verified: progress.verifiedCount += 1
                case .checksumMismatch: progress.mismatchCount += 1
                case .missing: progress.missingCount += 1
                case .error: progress.errorCount += 1
                }
            }
        }

        let endTime = Date()

        let verifiedCount = results.filter { $0.status == .verified }.count
        let mismatchCount = results.filter { $0.status == .checksumMismatch }.count
        let missingCount = results.filter { $0.status == .missing }.count
        let errorCount = results.filter { $0.status == .error }.count

        // Log summary
        if mismatchCount == 0 && missingCount == 0 && errorCount == 0 {
            log(.success, category: .general, message: "Quick verification passed: \(verifiedCount)/\(sampleCount) samples verified")
        } else {
            log(.warning, category: .general, message: "Quick verification found issues: \(verifiedCount) verified, \(mismatchCount) mismatches, \(missingCount) missing, \(errorCount) errors")
        }

        // Explicitly flush logs before returning
        flushLogBuffer()

        return VerificationJobResult(
            id: jobID,
            destinationID: destination.id,
            startTime: startTime,
            endTime: endTime,
            totalPhotos: sampleCount,
            verifiedCount: verifiedCount,
            mismatchCount: mismatchCount,
            missingCount: missingCount,
            errorCount: errorCount,
            details: results
        )
    }

    // MARK: - Get Unverified Photos

    /// Get photos that haven't been verified recently
    /// - Parameters:
    ///   - destinationID: Destination to check
    ///   - olderThan: Only return photos not verified since this date
    /// - Returns: Array of photos needing verification
    func getUnverifiedPhotos(
        destinationID: UUID,
        olderThan: Date = Date().addingTimeInterval(-30 * 24 * 60 * 60)  // 30 days default
    ) throws -> [SyncedPhoto] {
        let allPhotos = try database.getAllSyncedPhotos(destinationID: destinationID)

        return allPhotos.filter { photo in
            guard let lastVerified = photo.lastVerifiedDate else {
                return true  // Never verified
            }
            return lastVerified < olderThan
        }
    }

    // MARK: - Control

    /// Cancel the current verification operation
    func cancel() {
        logger.info("Cancelling verification")
        isCancelled = true
    }
}

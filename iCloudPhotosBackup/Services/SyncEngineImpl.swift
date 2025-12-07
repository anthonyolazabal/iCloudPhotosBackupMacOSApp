import Foundation
import OSLog
import Observation

/// Implementation of the sync engine
/// Orchestrates backup operations between photo source and destinations
@Observable
class SyncEngineImpl: SyncEngine {
    private(set) var state: SyncJobState = .idle
    private(set) var progress: SyncProgress = SyncProgress()
    private(set) var currentJobID: UUID?

    private let database: DatabaseService
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "SyncEngine")

    private var isCancelled = false
    private var isPaused = false

    // Configuration
    private var concurrentUploadsLimit = 3
    private var exportSettings = ExportSettings.default
    private var encryptionService: EncryptionService?

    // Log buffer for batch saving
    private var logBuffer: [SyncLogEntry] = []
    private let logBufferLimit = 50

    // MARK: - Initialization

    init(database: DatabaseService, exportSettings: ExportSettings = .default, encryptionService: EncryptionService? = nil) {
        self.database = database
        self.exportSettings = exportSettings
        self.encryptionService = encryptionService
        logger.info("SyncEngine initialized")
    }

    // MARK: - Start Sync

    func startSync(
        source: PhotoSource,
        destination: BackupDestination,
        filter: DateRangeFilter
    ) async throws {
        guard state == .idle else {
            throw SyncError.alreadyRunning
        }

        logger.info("Starting sync operation")

        // Reset state
        isCancelled = false
        isPaused = false
        state = .preparing
        logBuffer.removeAll()

        // Create sync job record
        let jobID = UUID()
        currentJobID = jobID

        let job = SyncJob(
            id: jobID,
            destinationID: destination.id
        )

        try database.createSyncJob(job)

        log(.info, category: .general, message: "Sync job started")
        log(.info, category: .general, message: "Filter: \(String(describing: filter))")

        do {
            // Ensure destination is connected
            log(.info, category: .connection, message: "Connecting to destination...")
            try await destination.connect()
            log(.success, category: .connection, message: "Connected to destination successfully")

            // Fetch photos from source
            logger.info("Fetching photos from library")
            log(.info, category: .general, message: "Fetching photos from library...")
            state = .preparing
            let photos = try await source.fetchPhotos(filter: filter)

            guard !photos.isEmpty else {
                log(.warning, category: .general, message: "No photos found matching the filter")
                flushLogBuffer()
                throw SyncError.noPhotosToSync
            }

            logger.info("Found \(photos.count) photos to process")
            log(.info, category: .general, message: "Found \(photos.count) photos in library")
            progress.totalPhotos = photos.count

            // Filter out already synced photos (deduplication with remote verification)
            log(.info, category: .deduplication, message: "Checking for already synced photos with remote verification...")
            let photosToSync = try await filterAlreadySyncedPhotos(photos, destinationID: destination.id, destination: destination)

            logger.info("\(photosToSync.count) photos need to be synced")
            let skippedCount = photos.count - photosToSync.count
            log(.info, category: .deduplication, message: "\(skippedCount) photos already synced, \(photosToSync.count) need syncing")

            // Send notification that backup is starting
            NotificationService.shared.notifyBackupStarted(
                destinationName: destination.name,
                photoCount: photosToSync.count
            )

            if photosToSync.isEmpty {
                logger.info("All photos already synced, nothing to do")
                log(.success, category: .general, message: "All photos already synced - nothing to do")
                flushLogBuffer()

                // Set progress to 100% - all photos are "done" (already synced)
                progress.totalPhotos = photos.count
                progress.photosCompleted = photos.count

                state = .completed
                try completeJob(jobID, photosScanned: photos.count, photosSynced: 0, photosFailed: 0, bytesTransferred: 0)
                return
            }

            progress.totalPhotos = photosToSync.count

            // Update job
            var updatedJob = job
            updatedJob.photosScanned = photos.count
            try database.updateSyncJob(updatedJob)

            // Start syncing
            state = .syncing
            log(.info, category: .upload, message: "Starting upload of \(photosToSync.count) photos...")

            try await syncPhotos(
                photosToSync,
                source: source,
                destination: destination,
                jobID: jobID
            )

            // Complete job
            if isCancelled {
                state = .idle
                var finalJob = try database.getSyncJob(id: jobID)!
                finalJob.status = .cancelled
                finalJob.endTime = Date()
                try database.updateSyncJob(finalJob)
                logger.info("Sync cancelled by user")
                log(.warning, category: .general, message: "Sync cancelled by user")

                // Send cancellation notification
                NotificationService.shared.notifyBackupCancelled(destinationName: destination.name)
            } else {
                state = .completed
                let duration = Date().timeIntervalSince(job.startTime)
                try completeJob(
                    jobID,
                    photosScanned: photos.count,
                    photosSynced: progress.photosCompleted,
                    photosFailed: progress.photosFailed,
                    bytesTransferred: progress.bytesTransferred
                )
                logger.info("Sync completed: \(self.progress.photosCompleted) succeeded, \(self.progress.photosFailed) failed")

                let bytesFormatted = ByteCountFormatter.string(fromByteCount: progress.bytesTransferred, countStyle: .file)
                log(.success, category: .general, message: "Sync completed successfully")
                log(.info, category: .general, message: "Summary: \(progress.photosCompleted) synced, \(progress.photosFailed) failed, \(bytesFormatted) transferred")

                // Send completion notification
                NotificationService.shared.notifyBackupCompleted(
                    destinationName: destination.name,
                    photosUploaded: progress.photosCompleted,
                    photosFailed: progress.photosFailed,
                    duration: duration
                )
            }

            flushLogBuffer()

        } catch {
            state = .failed
            logger.error("Sync failed: \(error.localizedDescription)")
            log(.error, category: .general, message: "Sync failed: \(error.localizedDescription)", details: String(describing: error))
            flushLogBuffer()

            if let jobID = currentJobID {
                var failedJob = try? database.getSyncJob(id: jobID)
                failedJob?.status = .failed
                failedJob?.endTime = Date()
                if let job = failedJob {
                    try? database.updateSyncJob(job)
                }
            }

            // Send failure notification
            NotificationService.shared.notifyBackupFailed(
                destinationName: destination.name,
                error: error.localizedDescription
            )

            throw error
        }
    }

    // MARK: - Pause/Resume/Cancel

    func pause() async throws {
        guard state == .syncing else {
            throw SyncError.notRunning
        }

        logger.info("Pausing sync")
        isPaused = true
        state = .paused

        if let jobID = currentJobID {
            var job = try database.getSyncJob(id: jobID)
            job?.status = .paused
            if let j = job {
                try database.updateSyncJob(j)
            }
        }
    }

    func resume() async throws {
        guard state == .paused else {
            throw SyncError.notRunning
        }

        logger.info("Resuming sync")
        isPaused = false
        state = .syncing

        if let jobID = currentJobID {
            var job = try database.getSyncJob(id: jobID)
            job?.status = .running
            if let j = job {
                try database.updateSyncJob(j)
            }
        }
    }

    func cancel() async throws {
        guard state == .syncing || state == .paused else {
            throw SyncError.notRunning
        }

        logger.info("Cancelling sync")
        isCancelled = true
        state = .idle
    }

    // MARK: - Deduplication (Batch Optimized with Remote Verification)

    private func filterAlreadySyncedPhotos(
        _ photos: [PhotoMetadata],
        destinationID: UUID,
        destination: BackupDestination
    ) async throws -> [PhotoMetadata] {
        // Use batch query for much better performance with large libraries
        let localIDs = photos.map { $0.localIdentifier }

        // Get full synced photo records for verification
        let syncedPhotos = try database.getSyncedPhotosForVerification(localIDs: localIDs, destinationID: destinationID)

        logger.info("Batch deduplication: \(syncedPhotos.count) already synced of \(photos.count) total")
        log(.info, category: .deduplication, message: "Checking \(photos.count) photos against \(syncedPhotos.count) synced records")

        var photosToSync: [PhotoMetadata] = []
        var skippedCount = 0
        var newCount = 0
        var modifiedCount = 0
        var remoteVerifyFailedCount = 0

        for photo in photos {
            if let syncedPhoto = syncedPhotos[photo.localIdentifier] {
                // Photo was previously synced - check if modified
                if let modDate = photo.modificationDate, modDate > syncedPhoto.syncDate {
                    // Photo was modified, needs re-sync
                    logger.debug("Photo modified since last sync: \(photo.localIdentifier)")
                    log(.debug, category: .deduplication, message: "Modified since sync (mod: \(modDate.formatted()), synced: \(syncedPhoto.syncDate.formatted()))", photoID: photo.localIdentifier)
                    photosToSync.append(photo)
                    modifiedCount += 1
                } else {
                    // Photo not modified locally - verify it exists on remote with correct size
                    let remoteVerified = await verifyRemoteFile(syncedPhoto: syncedPhoto, destination: destination)

                    if remoteVerified {
                        // Skip - already synced, not modified, and verified on remote
                        skippedCount += 1
                        if skippedCount <= 5 {
                            let modDateStr = photo.modificationDate?.formatted() ?? "nil"
                            logger.debug("Skipping verified: \(photo.localIdentifier)")
                            log(.debug, category: .deduplication, message: "Verified on remote, skipping (mod: \(modDateStr), synced: \(syncedPhoto.syncDate.formatted()))", photoID: photo.localIdentifier)
                        }
                    } else {
                        // Remote verification failed - needs re-sync
                        logger.warning("Remote verification failed, will re-sync: \(photo.localIdentifier)")
                        log(.warning, category: .deduplication, message: "Remote verification failed - file missing or size mismatch, will re-upload", photoID: photo.localIdentifier, details: "Expected path: \(syncedPhoto.remotePath), size: \(syncedPhoto.fileSize)")
                        photosToSync.append(photo)
                        remoteVerifyFailedCount += 1
                    }
                }
            } else {
                // New photo - not in database
                logger.debug("New photo to sync: \(photo.localIdentifier)")
                log(.debug, category: .deduplication, message: "New photo (not in database)", photoID: photo.localIdentifier)
                photosToSync.append(photo)
                newCount += 1
            }
        }

        logger.info("Deduplication result: \(newCount) new, \(modifiedCount) modified, \(remoteVerifyFailedCount) remote-failed, \(skippedCount) verified-skipped")
        log(.info, category: .deduplication, message: "Result: \(newCount) new, \(modifiedCount) modified, \(remoteVerifyFailedCount) remote verification failed, \(skippedCount) verified and skipped")

        return photosToSync
    }

    /// Verify that a synced photo exists on the remote destination with the correct file size
    private func verifyRemoteFile(syncedPhoto: SyncedPhoto, destination: BackupDestination) async -> Bool {
        do {
            // Check if file exists and get its metadata
            guard let remoteMetadata = try await destination.getFileMetadata(at: syncedPhoto.remotePath) else {
                logger.debug("Remote file not found: \(syncedPhoto.remotePath)")
                return false
            }

            // Verify file size matches
            if remoteMetadata.size != syncedPhoto.fileSize {
                logger.debug("Remote file size mismatch: expected \(syncedPhoto.fileSize), got \(remoteMetadata.size)")
                return false
            }

            return true
        } catch {
            logger.debug("Failed to verify remote file: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Sync Photos

    private func syncPhotos(
        _ photos: [PhotoMetadata],
        source: PhotoSource,
        destination: BackupDestination,
        jobID: UUID
    ) async throws {
        let startTime = Date()
        var totalBytesTransferred: Int64 = 0
        var lastFlushTime = Date()
        let flushInterval: TimeInterval = 5.0 // Flush logs every 5 seconds for real-time viewing

        // Process photos with concurrent upload limiting
        await withTaskGroup(of: SyncResult.self) { group in
            var activeUploads = 0
            var photoIndex = 0

            while photoIndex < photos.count || activeUploads > 0 {
                // Check for pause/cancel
                if isCancelled {
                    group.cancelAll()
                    break
                }

                while isPaused {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }

                // Add new tasks up to the concurrency limit
                while activeUploads < concurrentUploadsLimit && photoIndex < photos.count {
                    let photo = photos[photoIndex]
                    photoIndex += 1
                    activeUploads += 1

                    group.addTask {
                        await self.syncSinglePhoto(
                            photo,
                            source: source,
                            destination: destination,
                            jobID: jobID
                        )
                    }
                }

                // Wait for at least one task to complete
                if let result = await group.next() {
                    activeUploads -= 1

                    switch result {
                    case .success(let bytes):
                        progress.photosCompleted += 1
                        progress.bytesTransferred += bytes
                        totalBytesTransferred += bytes
                    case .failure:
                        progress.photosFailed += 1
                    }

                    // Update speed calculation
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > 0 {
                        progress.averageSpeed = Double(totalBytesTransferred) / elapsed / 1_048_576 // MB/s
                        progress.currentSpeed = progress.averageSpeed // Simplified, could be more sophisticated

                        // Estimate time remaining
                        let remainingPhotos = progress.totalPhotos - progress.photosCompleted
                        let avgTimePerPhoto = elapsed / Double(progress.photosCompleted)
                        progress.estimatedTimeRemaining = avgTimePerPhoto * Double(remainingPhotos)
                    }

                    // Periodic log flushing for real-time log viewing
                    let now = Date()
                    if now.timeIntervalSince(lastFlushTime) >= flushInterval {
                        flushLogBuffer()
                        lastFlushTime = now
                    }
                }
            }
        }
    }

    // MARK: - Sync Single Photo

    private func syncSinglePhoto(
        _ photo: PhotoMetadata,
        source: PhotoSource,
        destination: BackupDestination,
        jobID: UUID
    ) async -> SyncResult {
        logger.debug("Syncing photo: \(photo.localIdentifier)")
        let photoName = photo.originalFilename ?? photo.localIdentifier

        do {
            // Update progress
            await MainActor.run {
                progress.currentPhotoName = photoName
            }

            // Export photo from library
            log(.debug, category: .export, message: "Exporting photo from library", photoID: photo.localIdentifier)
            let exportResult = try await source.exportPhoto(photo) { exportProgress in
                // Could update UI with export progress here
            }

            let exportSize = ByteCountFormatter.string(fromByteCount: Int64(exportResult.exportedFileURL.fileSize ?? 0), countStyle: .file)
            log(.debug, category: .export, message: "Exported: \(exportSize)", photoID: photo.localIdentifier)

            // Build remote path
            var remotePath = buildRemotePath(for: photo, exportResult: exportResult)

            // Encrypt file if encryption is enabled
            var fileToUpload = exportResult.exportedFileURL
            if exportSettings.encryptFiles, let encryption = encryptionService {
                logger.debug("Encrypting photo before upload: \(photo.localIdentifier)")
                log(.debug, category: .encryption, message: "Encrypting file before upload", photoID: photo.localIdentifier)

                let encryptedURL = exportResult.exportedFileURL.deletingLastPathComponent()
                    .appendingPathComponent(exportResult.exportedFileURL.lastPathComponent + ".encrypted")

                try encryption.encryptFile(at: exportResult.exportedFileURL, to: encryptedURL)
                fileToUpload = encryptedURL
                remotePath += ".encrypted" // Add .encrypted extension to remote path

                logger.debug("Photo encrypted successfully")
                log(.debug, category: .encryption, message: "Encryption completed", photoID: photo.localIdentifier)
            }

            // Upload to destination
            log(.debug, category: .upload, message: "Uploading to: \(remotePath)", photoID: photo.localIdentifier)
            let uploadResult = try await destination.upload(
                file: fileToUpload,
                to: remotePath
            ) { uploadProgress in
                // Could update UI with upload progress here
            }

            // Save sync record to database
            let syncedPhoto = SyncedPhoto(
                localID: photo.localIdentifier,
                remotePath: remotePath,
                destinationID: destination.id,
                checksum: uploadResult.checksum,
                fileSize: uploadResult.size
            )

            try database.saveSyncedPhoto(syncedPhoto)
            log(.debug, category: .database, message: "Saved sync record", photoID: photo.localIdentifier)

            // Clean up temporary files
            try? FileManager.default.removeItem(at: exportResult.exportedFileURL)
            if fileToUpload != exportResult.exportedFileURL {
                try? FileManager.default.removeItem(at: fileToUpload)
            }
            log(.debug, category: .cleanup, message: "Cleaned up temporary files", photoID: photo.localIdentifier)

            logger.info("Successfully synced photo: \(photo.localIdentifier)")
            let sizeFormatted = ByteCountFormatter.string(fromByteCount: uploadResult.size, countStyle: .file)
            log(.success, category: .upload, message: "Synced successfully (\(sizeFormatted))", photoID: photo.localIdentifier, details: "Remote path: \(remotePath)")

            return .success(uploadResult.size)

        } catch {
            logger.error("Failed to sync photo: \(error.localizedDescription)")
            log(.error, category: .upload, message: "Failed: \(error.localizedDescription)", photoID: photo.localIdentifier, details: String(describing: error))

            // Save error to database
            let errorEntry = SyncErrorEntry(
                photoID: photo.localIdentifier,
                errorMessage: error.localizedDescription,
                errorCategory: categorizeError(error)
            )

            try? database.saveSyncError(errorEntry, jobID: jobID)

            return .failure(error)
        }
    }

    // MARK: - Helper Methods

    private func buildRemotePath(for photo: PhotoMetadata, exportResult: PhotoExportResult) -> String {
        // Format: YYYY/MM/DD/filename_assetid.ext

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"

        let datePath: String
        if let creationDate = photo.creationDate {
            datePath = dateFormatter.string(from: creationDate)
        } else {
            datePath = "unknown"
        }

        let filename: String
        if exportSettings.obfuscateFilenames {
            // Use UUID for privacy
            let fileExtension = exportResult.exportedFileURL.pathExtension
            filename = "\(UUID().uuidString).\(fileExtension)"
        } else if let originalName = photo.originalFilename {
            filename = originalName
        } else {
            // Generate from date and asset ID
            let assetID = photo.localIdentifier.replacingOccurrences(of: "/", with: "_")
            let ext = exportResult.exportedFileURL.pathExtension
            filename = "\(assetID).\(ext)"
        }

        return "\(datePath)/\(filename)"
    }

    private func categorizeError(_ error: Error) -> String {
        if let appError = error as? AppErrorProtocol {
            return String(describing: appError.errorCategory)
        }
        return "unknown"
    }

    private func completeJob(
        _ jobID: UUID,
        photosScanned: Int,
        photosSynced: Int,
        photosFailed: Int,
        bytesTransferred: Int64
    ) throws {
        var job = try database.getSyncJob(id: jobID)

        job?.status = photosFailed > 0 ? .completed : .completed
        job?.endTime = Date()
        job?.photosScanned = photosScanned
        job?.photosSynced = photosSynced
        job?.photosFailed = photosFailed
        job?.bytesTransferred = bytesTransferred
        job?.averageSpeed = progress.averageSpeed

        if let j = job {
            try database.updateSyncJob(j)
        }
    }

    // MARK: - Configuration

    func setConcurrentUploadsLimit(_ limit: Int) {
        concurrentUploadsLimit = max(1, min(limit, 10))
        logger.info("Concurrent uploads limit set to: \(self.concurrentUploadsLimit)")
    }

    func setExportSettings(_ settings: ExportSettings) {
        exportSettings = settings
        logger.info("Export settings updated")
    }

    // MARK: - Sync Logging

    /// Flush any pending logs to database (public interface)
    func flushLogs() {
        flushLogBuffer()
    }

    private func log(
        _ level: SyncLogEntry.LogLevel,
        category: SyncLogEntry.LogCategory,
        message: String,
        photoID: String? = nil,
        details: String? = nil
    ) {
        guard let jobID = currentJobID else { return }

        let entry = SyncLogEntry(
            jobID: jobID,
            level: level,
            category: category,
            message: message,
            photoID: photoID,
            details: details
        )

        logBuffer.append(entry)

        // Flush buffer if it reaches the limit
        if logBuffer.count >= logBufferLimit {
            flushLogBuffer()
        }
    }

    private func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }

        let logsToSave = logBuffer
        logBuffer.removeAll()

        do {
            try database.saveSyncLogs(logsToSave)
        } catch {
            logger.error("Failed to save sync logs: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sync Result

private enum SyncResult {
    case success(Int64)  // bytes transferred
    case failure(Error)
}

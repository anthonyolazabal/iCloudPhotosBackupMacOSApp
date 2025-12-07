import Foundation
import Observation

/// Global application state
@Observable
class AppState {
    // Services
    private(set) var database: DatabaseService
    private(set) var photoLibrary: PhotoLibraryService
    private(set) var syncEngine: SyncEngineImpl
    private(set) var backgroundScheduler: BackgroundScheduler?
    private(set) var encryptionService: EncryptionService
    private(set) var verificationService: VerificationService?

    // State
    var destinations: [DestinationRecord] = []
    var recentJobs: [SyncJob] = []
    var scheduledJobs: [ScheduledBackupJob] = []
    var currentSyncProgress: SyncProgress?
    var verificationProgress: VerificationProgress?
    var stats: [UUID: SyncStats] = [:]

    // Verification Results
    var lastVerificationResult: VerificationJobResult?
    var lastGapDetectionResult: GapDetectionResult?
    var recentVerificationJobs: [VerificationJob] = []

    // UI State
    var selectedDestination: DestinationRecord?
    var isConfiguring: Bool = false
    var errorMessage: String?

    // Settings
    var exportSettings: ExportSettings = .default
    var concurrentUploads: Int = 3

    // MARK: - Initialization

    init() {
        do {
            // Initialize database first
            let db = try DatabaseService()
            self.database = db

            // Initialize other services using local variables
            let photoLib = PhotoLibraryService()
            self.photoLibrary = photoLib

            let encryption = EncryptionService()
            self.encryptionService = encryption

            let engine = SyncEngineImpl(
                database: db,
                exportSettings: .default,
                encryptionService: encryption
            )
            self.syncEngine = engine

            // Initialize verification service
            let verification = VerificationService(database: db)
            self.verificationService = verification
            self.verificationProgress = verification.progress

            // Clean up any stale jobs from previous sessions
            try? db.cleanupStaleJobs()

            // Clean up old logs and jobs (older than 14 days)
            try? db.cleanupOldLogs(olderThanDays: 14)

            // Initialize background scheduler after services are ready
            Task { @MainActor in
                self.backgroundScheduler = BackgroundScheduler(appState: self)

                // Load initial data
                await self.loadDestinations()
                await self.loadRecentJobs()
                await self.loadScheduledJobs()
                await self.loadRecentVerificationJobs()
                await self.loadStats()

                // Request notification permissions
                _ = await NotificationService.shared.requestAuthorization()
            }
        } catch {
            fatalError("Failed to initialize app state: \(error)")
        }
    }

    // MARK: - Data Loading

    @MainActor
    func loadDestinations() async {
        do {
            destinations = try database.getAllDestinations()
        } catch {
            errorMessage = "Failed to load destinations: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadRecentJobs() async {
        do {
            recentJobs = try database.getRecentSyncJobs(limit: 20)
        } catch {
            errorMessage = "Failed to load jobs: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadStats() async {
        stats.removeAll()
        for destination in destinations {
            do {
                let destStats = try database.getStats(destinationID: destination.id)
                stats[destination.id] = destStats
            } catch {
                // Continue loading other stats
            }
        }
    }

    @MainActor
    func loadScheduledJobs() async {
        do {
            scheduledJobs = try database.getAllScheduledBackupJobs()
        } catch {
            errorMessage = "Failed to load scheduled jobs: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteSyncJob(id: UUID) async {
        do {
            try database.deleteSyncJob(id: id)
            await loadRecentJobs()
        } catch {
            errorMessage = "Failed to delete sync job: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteAllSyncJobs() async {
        do {
            try database.deleteAllSyncJobs()
            await loadRecentJobs()
        } catch {
            errorMessage = "Failed to delete sync jobs: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteVerificationJob(id: UUID) async {
        do {
            try database.deleteVerificationJob(id: id)
            await loadRecentVerificationJobs()
        } catch {
            errorMessage = "Failed to delete verification job: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteAllVerificationJobs() async {
        do {
            for job in recentVerificationJobs {
                try database.deleteVerificationJob(id: job.id)
            }
            await loadRecentVerificationJobs()
        } catch {
            errorMessage = "Failed to delete verification jobs: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadRecentVerificationJobs() async {
        do {
            recentVerificationJobs = try database.getRecentVerificationJobs(limit: 20)
        } catch {
            errorMessage = "Failed to load verification jobs: \(error.localizedDescription)"
        }
    }

    // MARK: - Destination Management

    @MainActor
    func addDestination(_ config: S3Configuration) async throws {
        // Create destination record
        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)

        let record = DestinationRecord(
            id: config.id,
            name: config.name,
            type: .s3,
            configJSON: configData
        )

        // Save to database
        try database.saveDestination(record)

        // Reload destinations
        await loadDestinations()
    }

    @MainActor
    func removeDestination(_ id: UUID) async throws {
        try database.deleteDestination(id: id)
        await loadDestinations()
        await loadStats()
    }

    @MainActor
    func updateDestination(_ id: UUID, config: S3Configuration) async throws {
        // Encode the updated configuration
        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)

        // Create updated destination record
        let record = DestinationRecord(
            id: id,
            name: config.name,
            type: .s3,
            configJSON: configData,
            createdAt: config.createdAt
        )

        // Update in database
        try database.saveDestination(record)

        // Reload destinations
        await loadDestinations()
    }

    @MainActor
    func testDestination(_ config: S3Configuration) async throws -> Bool {
        let service = try S3DestinationService(configuration: config)
        return try await service.testConnection()
    }

    // MARK: - SMB Destination Management

    @MainActor
    func addSMBDestination(_ config: SMBConfiguration) async throws {
        // Validate configuration
        try config.validate()

        // Create destination record
        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)

        let record = DestinationRecord(
            id: config.id,
            name: config.name,
            type: .smb,
            configJSON: configData
        )

        // Save to database
        try database.saveDestination(record)

        // Reload destinations
        await loadDestinations()
    }

    @MainActor
    func updateSMBDestination(_ id: UUID, config: SMBConfiguration) async throws {
        // Validate configuration
        try config.validate()

        // Encode the updated configuration
        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)

        // Create updated destination record
        let record = DestinationRecord(
            id: id,
            name: config.name,
            type: .smb,
            configJSON: configData,
            createdAt: config.createdAt
        )

        // Update in database
        try database.saveDestination(record)

        // Reload destinations
        await loadDestinations()
    }

    @MainActor
    func testSMBDestination(_ config: SMBConfiguration) async throws -> Bool {
        let service = try SMBDestinationService(configuration: config)
        return try await service.testConnection()
    }

    // MARK: - Destination Service Factory

    func createDestinationService(for destination: DestinationRecord) throws -> BackupDestination {
        let decoder = JSONDecoder()

        switch destination.type {
        case .s3:
            let config = try decoder.decode(S3Configuration.self, from: destination.configJSON)
            return try S3DestinationService(configuration: config)
        case .smb:
            let config = try decoder.decode(SMBConfiguration.self, from: destination.configJSON)
            return try SMBDestinationService(configuration: config)
        default:
            throw DestinationError.invalidConfiguration(reason: "Unsupported destination type: \(destination.type.rawValue)")
        }
    }

    // MARK: - Sync Operations

    @MainActor
    func startSync(destinationID: UUID, filter: DateRangeFilter) async throws {
        // Load destination
        guard let destRecord = destinations.first(where: { $0.id == destinationID }) else {
            throw DestinationError.invalidConfiguration(reason: "Destination not found")
        }

        // Create destination service using factory method
        let destination = try createDestinationService(for: destRecord)

        // Request photo library authorization
        _ = try await photoLibrary.requestAuthorization()

        // Start sync
        currentSyncProgress = syncEngine.progress
        defer {
            // Clear progress when sync completes (success or failure)
            currentSyncProgress = nil
        }

        try await syncEngine.startSync(
            source: photoLibrary,
            destination: destination,
            filter: filter
        )

        // Reload after sync
        await loadRecentJobs()
        await loadStats()
    }

    @MainActor
    func pauseSync() async throws {
        try await syncEngine.pause()
    }

    @MainActor
    func resumeSync() async throws {
        try await syncEngine.resume()
    }

    @MainActor
    func cancelSync() async throws {
        try await syncEngine.cancel()
        currentSyncProgress = nil
    }

    // MARK: - Verification Operations

    @MainActor
    func saveVerificationResult(_ result: VerificationJobResult, type: VerificationJobType) async {
        // Convert VerificationJobResult to VerificationJob for persistence
        let job = VerificationJob(
            id: result.id,
            destinationID: result.destinationID,
            type: type,
            startTime: result.startTime,
            endTime: result.endTime,
            totalPhotos: result.totalPhotos,
            verifiedCount: result.verifiedCount,
            mismatchCount: result.mismatchCount,
            missingCount: result.missingCount,
            errorCount: result.errorCount
        )

        do {
            try database.saveVerificationJob(job)
            lastVerificationResult = result
            await loadRecentVerificationJobs()
        } catch {
            errorMessage = "Failed to save verification result: \(error.localizedDescription)"
        }
    }

    @MainActor
    func runVerification(
        destinationID: UUID,
        type: VerificationJobType,
        sampleSize: Int = 10
    ) async throws -> VerificationJobResult {
        guard let destRecord = destinations.first(where: { $0.id == destinationID }) else {
            throw DestinationError.invalidConfiguration(reason: "Destination not found")
        }

        // Create destination service using factory method
        let destination = try createDestinationService(for: destRecord)

        guard let service = verificationService else {
            throw DestinationError.invalidConfiguration(reason: "Verification service not initialized")
        }

        // Send notification that verification is starting
        let typeString = switch type {
        case .quick: "Quick"
        case .full: "Full"
        case .incremental: "Incremental"
        }
        NotificationService.shared.notifyVerificationStarted(
            destinationName: destRecord.name,
            type: typeString
        )

        let result: VerificationJobResult

        do {
            switch type {
            case .quick:
                result = try await service.quickVerification(destination: destination, sampleSize: sampleSize)
            case .full:
                result = try await service.verifyBackup(destination: destination)
            case .incremental:
                // For incremental, we only verify photos not verified in the last 30 days
                result = try await service.verifyBackup(destination: destination)
            }

            // Save result to database
            await saveVerificationResult(result, type: type)

            // Send completion notification
            NotificationService.shared.notifyVerificationCompleted(
                destinationName: destRecord.name,
                verified: result.verifiedCount,
                missing: result.missingCount,
                mismatched: result.mismatchCount,
                errors: result.errorCount
            )

            return result
        } catch {
            // Send failure notification
            NotificationService.shared.notifyVerificationFailed(
                destinationName: destRecord.name,
                error: error.localizedDescription
            )
            throw error
        }
    }

    @MainActor
    func runGapDetection(destinationID: UUID) async throws -> GapDetectionResult {
        guard let service = verificationService else {
            throw DestinationError.invalidConfiguration(reason: "Verification service not initialized")
        }

        guard let destRecord = destinations.first(where: { $0.id == destinationID }) else {
            throw DestinationError.invalidConfiguration(reason: "Destination not found")
        }

        // Request photo library authorization
        _ = try await photoLibrary.requestAuthorization()

        let result = try await service.detectGaps(
            source: photoLibrary,
            destinationID: destinationID
        )

        lastGapDetectionResult = result

        // Send notification with gap detection results
        NotificationService.shared.notifyGapDetectionCompleted(
            destinationName: destRecord.name,
            gapsFound: result.gapCount
        )

        return result
    }

    @MainActor
    func cancelVerification() {
        verificationService?.cancel()
    }

    // MARK: - Scheduled Jobs Management

    @MainActor
    func addScheduledBackupJob(_ job: ScheduledBackupJob) async {
        do {
            try database.saveScheduledBackupJob(job)
            await loadScheduledJobs()
        } catch {
            errorMessage = "Failed to save scheduled job: \(error.localizedDescription)"
        }
    }

    @MainActor
    func updateScheduledJob(_ job: ScheduledBackupJob) async {
        do {
            try database.saveScheduledBackupJob(job)
            await loadScheduledJobs()
        } catch {
            errorMessage = "Failed to update scheduled job: \(error.localizedDescription)"
        }
    }

    @MainActor
    func toggleScheduledJob(id: UUID, isEnabled: Bool) async {
        do {
            try database.toggleScheduledBackupJob(id: id, isEnabled: isEnabled)
            await loadScheduledJobs()
        } catch {
            errorMessage = "Failed to toggle scheduled job: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteScheduledJob(id: UUID) async {
        do {
            try database.deleteScheduledBackupJob(id: id)
            await loadScheduledJobs()
        } catch {
            errorMessage = "Failed to delete scheduled job: \(error.localizedDescription)"
        }
    }

    @MainActor
    func runScheduledJobNow(_ job: ScheduledBackupJob) async {
        guard let scheduler = backgroundScheduler else {
            errorMessage = "Background scheduler not available"
            return
        }

        await scheduler.runScheduledJob(job)
    }
}
